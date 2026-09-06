import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/secure_key_store.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../signaling/signaling_client.dart';
import '../signaling/signaling_message.dart';
import 'peer_connection_state.dart';

/// Central Connection Manager orchestrating:
/// - Persistent connection state per peer
/// - Automatic reconnection
/// - Offline local outbox queuing & flushing
/// - End-to-end encrypted packet transmission
/// - Delivery receipts
class ConnectionManager extends ChangeNotifier {
  final KeyPairBundle myIdentity;
  final CryptoService cryptoService;
  final ContactRepository contactRepository;
  final ChatRepository chatRepository;
  final SignalingClient signalingClient;
  final SecureKeyStore? secureKeyStore;

  // Track real-time connectivity status per peer device ID
  final Map<String, PeerConnectionState> _peerStates = {};
  final Map<String, DateTime> _lastPeerActivity = {};

  // Cache derived session keys: peerDeviceId -> List<int>
  final Map<String, List<int>> _sessionKeys = {};

  StreamSubscription? _envelopeSub;
  StreamSubscription? _signalingStateSub;
  StreamSubscription? _peerStatusSub;
  final bool enablePeriodicFlush;
  Timer? _outboxPollTimer;
  final Map<String, Set<String>> _pendingReadReceipts = {};

  final _messageStreamController = StreamController<MessageModel>.broadcast();
  final _receiptStreamController = StreamController<String>.broadcast();
  final _readReceiptStreamController = StreamController<String>.broadcast();

  Stream<MessageModel> get onMessageReceived => _messageStreamController.stream;
  Stream<String> get onDeliveryReceipt => _receiptStreamController.stream;
  Stream<String> get onReadReceipt => _readReceiptStreamController.stream;

  ConnectionManager({
    required this.myIdentity,
    required this.cryptoService,
    required this.contactRepository,
    required this.chatRepository,
    required this.signalingClient,
    this.secureKeyStore,
    this.enablePeriodicFlush = true,
  }) {
    _init();
  }

  void _init() {
    // 1. Listen for incoming zero-knowledge encrypted envelopes
    _envelopeSub = signalingClient.onEnvelopeReceived.listen(_handleIncomingEnvelope);

    // 2. Listen for signaling server connectivity changes
    _signalingStateSub = signalingClient.onStateChanged.listen((state) {
      if (state == SignalingServerState.connected) {
        _checkAllPeersStatus();
        flushOutbox();
        flushPendingReadReceipts();
        notifyListeners();
      } else {
        // Mark all peers offline/reconnecting if signaling gateway drops
        for (final peerId in _peerStates.keys) {
          _peerStates[peerId] = PeerConnectionState.reconnecting;
        }
        notifyListeners();
      }
    });

    // 3. Listen for peer status responses from signaling
    _peerStatusSub = signalingClient.onPeerStatusChanged.listen((statusMap) {
      final peerId = statusMap['targetId'];
      final status = statusMap['status'];
      if (peerId != null && peerId.isNotEmpty) {
        if (status == 'online') {
          _setPeerOnline(peerId);
        } else {
          final upper = peerId.trim().toUpperCase();
          final raw = peerId.trim();
          _peerStates[upper] = PeerConnectionState.offline;
          _peerStates[raw] = PeerConnectionState.offline;
          notifyListeners();
        }
      }
    });

    if (enablePeriodicFlush) {
      // 4. Start periodic poll & presence refresh timer (every 15s)
      _outboxPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        flushOutbox();
        _checkAllPeersStatus();
        _pruneOfflinePeers();
      });

      // Connect to signaling gateway
      signalingClient.connect();

      // If already connected, probe peers immediately
      if (signalingClient.state == SignalingServerState.connected) {
        _checkAllPeersStatus();
      }
    }
  }

  void _setPeerOnline(String peerDeviceId) {
    final upper = peerDeviceId.trim().toUpperCase();
    final raw = peerDeviceId.trim();
    final now = DateTime.now();
    _lastPeerActivity[upper] = now;
    _lastPeerActivity[raw] = now;

    bool stateChanged = false;
    if (_peerStates[upper] != PeerConnectionState.online) {
      _peerStates[upper] = PeerConnectionState.online;
      _peerStates[raw] = PeerConnectionState.online;
      stateChanged = true;
    }
    if (stateChanged) {
      notifyListeners();
      _deliverPendingForPeer(upper);
      _deliverPendingForPeer(raw);
    }
  }

  void _pruneOfflinePeers() {
    final now = DateTime.now();
    bool changed = false;
    for (final entry in _peerStates.entries) {
      if (entry.value == PeerConnectionState.online) {
        final lastActive = _lastPeerActivity[entry.key];
        if (lastActive != null && now.difference(lastActive).inSeconds > 45) {
          _peerStates[entry.key] = PeerConnectionState.offline;
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Returns current connectivity state for a given peer device ID
  PeerConnectionState getPeerState(String peerDeviceId) {
    final upper = peerDeviceId.trim().toUpperCase();
    final raw = peerDeviceId.trim();
    final state = _peerStates[upper] ?? _peerStates[raw] ?? PeerConnectionState.offline;

    if (state == PeerConnectionState.online) {
      final lastActive = _lastPeerActivity[upper] ?? _lastPeerActivity[raw];
      if (lastActive != null && DateTime.now().difference(lastActive).inSeconds > 45) {
        return PeerConnectionState.offline;
      }
    }
    return state;
  }

  /// Actively checks status of a peer via presence subscription and direct ping probe
  void checkPeer(String peerDeviceId, {bool force = false}) {
    signalingClient.checkPeerStatus(peerDeviceId);
    final upper = peerDeviceId.trim().toUpperCase();
    final lastActive = _lastPeerActivity[upper];
    if (force ||
        _peerStates[upper] != PeerConnectionState.online ||
        lastActive == null ||
        DateTime.now().difference(lastActive).inSeconds > 20) {
      _sendPing(peerDeviceId);
    }
  }

  void _sendPing(String toPeerDeviceId) {
    if (signalingClient.state != SignalingServerState.connected) return;
    try {
      final envelope = SignalingEnvelope(
        to: toPeerDeviceId.trim(),
        from: myIdentity.deviceId,
        type: 'ping',
        payload: 'ping',
        timestamp: DateTime.now(),
      );
      signalingClient.sendEnvelope(envelope);
    } catch (_) {}
  }

  void _sendPong(String toPeerDeviceId) {
    if (signalingClient.state != SignalingServerState.connected) return;
    try {
      final envelope = SignalingEnvelope(
        to: toPeerDeviceId.trim(),
        from: myIdentity.deviceId,
        type: 'pong',
        payload: 'pong',
        timestamp: DateTime.now(),
      );
      signalingClient.sendEnvelope(envelope);
    } catch (_) {}
  }

  void _checkAllPeersStatus() async {
    final contacts = await contactRepository.getContacts();
    final now = DateTime.now();
    for (final contact in contacts) {
      signalingClient.checkPeerStatus(contact.peerDeviceId);
      final upper = contact.peerDeviceId.trim().toUpperCase();
      final lastActive = _lastPeerActivity[upper];
      if (_peerStates[upper] != PeerConnectionState.online ||
          lastActive == null ||
          now.difference(lastActive).inSeconds > 25) {
        _sendPing(contact.peerDeviceId);
      }
    }
  }

  /// Sends a plaintext message to a contact:
  /// 1. Derives/reuses E2EE session key
  /// 2. Encrypts plaintext into AES-256-GCM ciphertext
  /// 3. Saves ciphertext to local database
  /// 4. If peer is online, delivers immediately; otherwise keeps in local outbox
  Future<MessageModel> sendMessage({
    required ContactModel contact,
    required ConversationModel conversation,
    required String text,
    MessageType messageType = MessageType.text,
  }) async {
    // Derive or retrieve shared session key
    final sessionKey = await _getOrDeriveSessionKey(contact);

    // Encrypt into ciphertext JSON (n, c, m)
    final ciphertext = await cryptoService.encryptMessage(
      plaintext: text,
      sessionKeyBytes: sessionKey,
    );

    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${myIdentity.deviceId.substring(0, 4)}';
    final now = DateTime.now();

    // Create local message record with initial pending status
    final message = MessageModel(
      id: messageId,
      conversationId: conversation.id,
      senderId: myIdentity.deviceId,
      ciphertext: ciphertext,
      timestamp: now,
      status: MessageStatus.pending,
      messageType: messageType,
      decryptedContent: text,
    );

    // Save strictly ciphertext in local database
    await chatRepository.saveMessage(message);
    notifyListeners();

    // Attempt delivery if connected to signaling gateway
    if (signalingClient.state == SignalingServerState.connected) {
      try {
        final envelope = SignalingEnvelope(
          to: contact.peerDeviceId,
          from: myIdentity.deviceId,
          type: 'message',
          payload: ciphertext,
          messageId: messageId,
          senderDhPublicKey: myIdentity.dhPublicKeyHex,
          senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
          timestamp: now,
        );
        signalingClient.sendEnvelope(envelope);

        // Successfully dispatched from sender device to signaling network -> Sent (Single tick)
        await chatRepository.updateMessageStatus(messageId, MessageStatus.sent);
        final sentMessage = message.copyWith(status: MessageStatus.sent);
        notifyListeners();
        return sentMessage;
      } catch (_) {
        // Remains pending in outbox (Clock icon)
      }
    }

    return message;
  }

  /// Delivers pending outbox messages for all online peers
  Future<void> flushOutbox() async {
    flushPendingReadReceipts();
    if (signalingClient.state != SignalingServerState.connected) return;

    final pending = await chatRepository.getPendingOutgoingMessages();
    if (pending.isEmpty) return;

    final contacts = await contactRepository.getContacts();
    final contactMap = {for (var c in contacts) c.id: c};

    for (final msg in pending) {
      if (msg.senderId == myIdentity.deviceId) {
        // Find conversation
        final conv = await _findConversationForMessage(msg);
        if (conv != null && contactMap.containsKey(conv.contactId)) {
          final contact = contactMap[conv.contactId]!;
          // If peer state is unknown, check it
          signalingClient.checkPeerStatus(contact.peerDeviceId);

          if (getPeerState(contact.peerDeviceId) == PeerConnectionState.online) {
            try {
              final envelope = SignalingEnvelope(
                to: contact.peerDeviceId,
                from: myIdentity.deviceId,
                type: 'message',
                payload: msg.ciphertext,
                messageId: msg.id,
                senderDhPublicKey: myIdentity.dhPublicKeyHex,
                senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
                timestamp: msg.timestamp,
              );
              signalingClient.sendEnvelope(envelope);
              await chatRepository.updateMessageStatus(msg.id, MessageStatus.sent);
            } catch (_) {}
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> _deliverPendingForPeer(String peerDeviceId) async {
    final contact = await contactRepository.findByPeerDeviceId(peerDeviceId);
    if (contact == null) return;

    final pending = await chatRepository.getPendingOutgoingMessages();
    for (final msg in pending) {
      if (msg.senderId == myIdentity.deviceId) {
        try {
          final envelope = SignalingEnvelope(
            to: peerDeviceId,
            from: myIdentity.deviceId,
            type: 'message',
            payload: msg.ciphertext,
            messageId: msg.id,
            senderDhPublicKey: myIdentity.dhPublicKeyHex,
            senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
            timestamp: msg.timestamp,
          );
          signalingClient.sendEnvelope(envelope);
          await chatRepository.updateMessageStatus(msg.id, MessageStatus.sent);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<ConversationModel?> _findConversationForMessage(MessageModel msg) async {
    final convs = await chatRepository.getConversations();
    for (final c in convs) {
      if (c.id == msg.conversationId) return c;
    }
    return null;
  }

  /// Handles incoming blind envelope
  Future<void> _handleIncomingEnvelope(SignalingEnvelope envelope) async {
    final senderDeviceId = envelope.from;
    _setPeerOnline(senderDeviceId);

    if (envelope.type == 'ping') {
      _sendPong(senderDeviceId);
      return;
    }

    if (envelope.type == 'pong') {
      return;
    }

    if (envelope.type == 'key_request') {
      try {
        final localPasscode = (await secureKeyStore?.getOrGeneratePasscode())?.trim();
        final incomingPasscode = envelope.payload.trim();

        debugPrint('[ConnectionManager] Incoming key_request from $senderDeviceId with passcode "$incomingPasscode", local is "$localPasscode"');

        if (localPasscode == null || localPasscode.isEmpty || incomingPasscode != localPasscode) {
          debugPrint('[ConnectionManager] Rejected key_request from $senderDeviceId: incorrect passcode');
          final rejectEnvelope = SignalingEnvelope(
            to: senderDeviceId,
            from: myIdentity.deviceId,
            type: 'key_rejected',
            timestamp: DateTime.now(),
            payload: 'INCORRECT_PASSCODE',
          );
          signalingClient.sendEnvelope(rejectEnvelope);
          return;
        }

        // Passcode valid -> send public keys
        final replyEnvelope = SignalingEnvelope(
          to: senderDeviceId,
          from: myIdentity.deviceId,
          type: 'key_response',
          senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
          senderDhPublicKey: myIdentity.dhPublicKeyHex,
          timestamp: DateTime.now(),
          payload: 'key_response',
        );
        signalingClient.sendEnvelope(replyEnvelope);
      } catch (e) {
        debugPrint('[ConnectionManager] Error handling key_request: $e');
      }
      return;
    }

    if (envelope.type == 'key_response') {
      if (envelope.senderIdentityPublicKey != null && envelope.senderDhPublicKey != null) {
        signalingClient.recordPeerKeys(
          peerDeviceId: senderDeviceId,
          ik: envelope.senderIdentityPublicKey!,
          dh: envelope.senderDhPublicKey!,
        );
      }
      return;
    }

    if (envelope.type == 'delivery_receipt') {
      final msgId = envelope.messageId;
      if (msgId != null) {
        await chatRepository.updateMessageStatus(msgId, MessageStatus.delivered);
        _receiptStreamController.add(msgId);
        notifyListeners();
      }
      return;
    }

    if (envelope.type == 'read_receipt') {
      final Set<String> msgIds = {};
      if (envelope.messageId != null && envelope.messageId!.isNotEmpty) {
        msgIds.add(envelope.messageId!.trim());
      }
      if (envelope.payload.isNotEmpty) {
        final parts = envelope.payload.split(',');
        for (final p in parts) {
          final cleaned = p.replaceAll(RegExp(r'[^\w-]'), '').trim();
          if (cleaned.isNotEmpty) msgIds.add(cleaned);
        }
      }

      debugPrint('[ConnectionManager] Received read receipt for: $msgIds from ${envelope.from}');
      for (final id in msgIds) {
        await chatRepository.updateMessageStatus(id, MessageStatus.read);
        _readReceiptStreamController.add(id);
      }
      notifyListeners();
      return;
    }

    if (envelope.type == 'message') {
      // Find or verify contact
      var contact = await contactRepository.findByPeerDeviceId(senderDeviceId);
      if (contact == null) {
        // Drop message from unknown sender who hasn't been added with authorized Passcode
        debugPrint('[ConnectionManager] Dropping message from unknown/unauthorized sender $senderDeviceId');
        return;
      }

      final conversation = await chatRepository.getOrCreateConversation(contact.id);
      final sessionKey = await _getOrDeriveSessionKey(contact);

      String decryptedText;
      try {
        decryptedText = await cryptoService.decryptMessage(
          encryptedJson: envelope.payload,
          sessionKeyBytes: sessionKey,
        );
      } catch (e) {
        // Ciphertext failed validation
        return;
      }

      final incomingMessage = MessageModel(
        id: envelope.messageId ?? 'recv_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversation.id,
        senderId: senderDeviceId,
        ciphertext: envelope.payload,
        timestamp: envelope.timestamp,
        status: MessageStatus.delivered,
        messageType: MessageType.text,
        decryptedContent: decryptedText,
      );

      await chatRepository.saveMessage(incomingMessage);

      // Send back a delivery receipt
      if (envelope.messageId != null) {
        final receipt = SignalingEnvelope(
          to: senderDeviceId,
          from: myIdentity.deviceId,
          type: 'delivery_receipt',
          payload: '',
          messageId: envelope.messageId,
        );
        signalingClient.sendEnvelope(receipt);
      }

      _messageStreamController.add(incomingMessage);
      notifyListeners();
    }
  }

  Future<List<int>> _getOrDeriveSessionKey(ContactModel contact) async {
    if (_sessionKeys.containsKey(contact.peerDeviceId)) {
      return _sessionKeys[contact.peerDeviceId]!;
    }

    final key = await cryptoService.deriveSessionKey(
      myDhPrivateKeyHex: myIdentity.dhPrivateKeyHex,
      peerDhPublicKeyHex: contact.peerDhPublicKey,
    );

    _sessionKeys[contact.peerDeviceId] = key;
    return key;
  }

  /// Decrypts a message into its transient memory field
  Future<String?> decryptMessageContent(MessageModel message, ContactModel contact) async {
    if (message.decryptedContent != null) return message.decryptedContent;
    try {
      final sessionKey = await _getOrDeriveSessionKey(contact);
      final decrypted = await cryptoService.decryptMessage(
        encryptedJson: message.ciphertext,
        sessionKeyBytes: sessionKey,
      );
      message.decryptedContent = decrypted;
      return decrypted;
    } catch (_) {
      return '[Unable to decrypt]';
    }
  }

  void flushPendingReadReceipts() {
    if (signalingClient.state != SignalingServerState.connected) return;
    if (_pendingReadReceipts.isEmpty) return;

    final copy = Map<String, Set<String>>.from(_pendingReadReceipts);
    _pendingReadReceipts.clear();

    for (final entry in copy.entries) {
      final peerId = entry.key;
      final msgIds = entry.value.toList();
      if (msgIds.isNotEmpty) {
        try {
          final receipt = SignalingEnvelope(
            to: peerId,
            from: myIdentity.deviceId,
            type: 'read_receipt',
            payload: msgIds.join(','),
            messageId: msgIds.last,
          );
          signalingClient.sendEnvelope(receipt);
          debugPrint('[ConnectionManager] Flushed pending read receipts (${msgIds.length}) to $peerId');
        } catch (_) {
          _pendingReadReceipts.putIfAbsent(peerId, () => <String>{}).addAll(msgIds);
        }
      }
    }
  }

  /// Sends read receipt to peer and marks messages as read locally
  Future<void> sendReadReceipt(ContactModel contact, List<String> messageIds) async {
    if (messageIds.isEmpty) return;

    for (final id in messageIds) {
      await chatRepository.updateMessageStatus(id, MessageStatus.read);
    }
    notifyListeners();

    final targetPeer = contact.peerDeviceId.trim().toUpperCase();

    if (signalingClient.state == SignalingServerState.connected) {
      try {
        final receipt = SignalingEnvelope(
          to: targetPeer,
          from: myIdentity.deviceId,
          type: 'read_receipt',
          payload: messageIds.join(','),
          messageId: messageIds.last,
        );
        signalingClient.sendEnvelope(receipt);
        debugPrint('[ConnectionManager] Sent read receipt for ${messageIds.length} msgs to $targetPeer');
      } catch (e) {
        debugPrint('[ConnectionManager] Error sending read receipt: $e');
        _pendingReadReceipts.putIfAbsent(targetPeer, () => <String>{}).addAll(messageIds);
      }
    } else {
      _pendingReadReceipts.putIfAbsent(targetPeer, () => <String>{}).addAll(messageIds);
    }
  }

  /// Formats and validates a 12-character device ID (e.g. UU72-7FYQ-K6N5 or UU727FYQK6N5)
  static String? normalizeDeviceId(String input) {
    final clean = input.replaceAll('-', '').replaceAll(' ', '').trim().toUpperCase();
    if (clean.length == 12 && RegExp(r'^[A-Z0-9]{12}$').hasMatch(clean)) {
      return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}';
    }
    return null;
  }

  /// Resolves peer public keys via signaling probe with 6-digit passcode and adds the contact
  Future<ContactModel?> resolveAndAddContact(
    String rawDeviceId, {
    String? nickname,
    String? passcode,
  }) async {
    final normalized = normalizeDeviceId(rawDeviceId);
    if (normalized == null) return null;

    // 1. Check if contact already exists in local DB
    final existing = await contactRepository.findByPeerDeviceId(normalized);
    if (existing != null) {
      if (nickname != null && nickname.trim().isNotEmpty && nickname.trim() != existing.nickname) {
        await contactRepository.updateNickname(contactId: existing.id, newNickname: nickname.trim());
      }
      await chatRepository.getOrCreateConversation(existing.id);
      notifyListeners();
      return existing;
    }

    // 2. Query signaling directory / probe for keys with passcode verification
    final keys = await signalingClient.resolvePeerKeys(normalized, passcode: passcode);
    if (keys == null || keys['ik'] == null || keys['dh'] == null) {
      return null;
    }

    // 3. Save contact
    final nick = (nickname != null && nickname.trim().isNotEmpty)
        ? nickname.trim()
        : 'User ${normalized.substring(0, 4)}';

    final contact = await contactRepository.addContact(
      peerDeviceId: normalized,
      peerIdentityPublicKey: keys['ik']!,
      peerDhPublicKey: keys['dh']!,
      nickname: nick,
    );

    // 4. Create conversation entry
    await chatRepository.getOrCreateConversation(contact.id);
    notifyListeners();
    return contact;
  }

  @override
  void dispose() {
    _envelopeSub?.cancel();
    _signalingStateSub?.cancel();
    _peerStatusSub?.cancel();
    _outboxPollTimer?.cancel();
    _messageStreamController.close();
    _receiptStreamController.close();
    _readReceiptStreamController.close();
    super.dispose();
  }
}
