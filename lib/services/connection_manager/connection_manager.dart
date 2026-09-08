import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_pair_bundle.dart';
import '../../core/storage/secure_key_store.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/conversation_model.dart';
import '../../data/models/message_model.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/contact_repository.dart';
import '../media/ephemeral_media_service.dart';
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
  final EphemeralMediaService ephemeralMediaService = EphemeralMediaService();

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
  final _historyToggleController = StreamController<({String peerDeviceId, bool saveHistory})>.broadcast();

  Stream<MessageModel> get onMessageReceived => _messageStreamController.stream;
  Stream<String> get onDeliveryReceipt => _receiptStreamController.stream;
  Stream<String> get onReadReceipt => _readReceiptStreamController.stream;
  Stream<({String peerDeviceId, bool saveHistory})> get onHistoryToggleReceived => _historyToggleController.stream;

  String? _myDisplayName;
  String? get myDisplayName => _myDisplayName;

  ConnectionManager({
    required this.myIdentity,
    required this.cryptoService,
    required this.contactRepository,
    required this.chatRepository,
    required this.signalingClient,
    this.secureKeyStore,
    String? initialDisplayName,
    this.enablePeriodicFlush = true,
  }) : _myDisplayName = initialDisplayName {
    _init();
  }

  void updateMyDisplayName(String name) {
    _myDisplayName = name.trim();
    secureKeyStore?.setDisplayName(name.trim());
    publishEncryptedDirectoryCard();
    notifyListeners();
  }

  /// Encrypts and publishes our contact directory card on the broker with retain=true
  Future<void> publishEncryptedDirectoryCard() async {
    try {
      final passcode = await secureKeyStore?.getOrGeneratePasscode();
      if (passcode == null || passcode.isEmpty) return;

      final cardPayload = jsonEncode({
        'deviceId': myIdentity.deviceId,
        'ik': myIdentity.identityPublicKeyHex,
        'dh': myIdentity.dhPublicKeyHex,
        'name': _myDisplayName ?? '',
      });

      final encrypted = await cryptoService.encryptWithPasscode(
        plaintext: cardPayload,
        deviceId: myIdentity.deviceId,
        passcode: passcode,
      );

      signalingClient.publishDirectoryCard(
        deviceId: myIdentity.deviceId,
        encryptedPayload: encrypted,
      );
      debugPrint('[ConnectionManager] Published encrypted directory card for ${myIdentity.deviceId}');
    } catch (e) {
      debugPrint('[ConnectionManager] Error publishing directory card: $e');
    }
  }

  /// Resolves peer keys with passcode using both retained encrypted directory card (instant) and live handshake
  Future<Map<String, String>?> resolvePeerKeysWithPasscode(
    String targetDeviceId, {
    required String passcode,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final normalized = targetDeviceId.trim().toUpperCase();
    final cleanPasscode = passcode.trim();

    // 1. Ensure signaling is connected
    if (signalingClient.state != SignalingServerState.connected) {
      signalingClient.connect();
      try {
        await signalingClient.onStateChanged
            .firstWhere((s) => s == SignalingServerState.connected)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    // 2. Subscribe to directory card & presence
    signalingClient.checkPeerStatus(normalized);
    signalingClient.subscribeToDirectory(normalized);

    // 3. Send live key_request
    try {
      signalingClient.sendEnvelope(SignalingEnvelope(
        to: normalized,
        from: myIdentity.deviceId,
        type: 'key_request',
        senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
        senderDhPublicKey: myIdentity.dhPublicKeyHex,
        timestamp: DateTime.now(),
        payload: cleanPasscode,
      ));
    } catch (_) {}

    final completer = Completer<Map<String, String>?>();
    StreamSubscription? rawDirSub;
    StreamSubscription? envSub;
    Timer? timeoutTimer;

    void finish(Map<String, String>? result, [Object? error]) {
      if (!completer.isCompleted) {
        timeoutTimer?.cancel();
        rawDirSub?.cancel();
        envSub?.cancel();
        if (error != null) {
          completer.completeError(error);
        } else {
          completer.complete(result);
        }
      }
    }

    // 4. Listen for retained/published directory card
    rawDirSub = signalingClient.onRawDirectoryReceived.listen((map) async {
      if (map['targetId'] == normalized) {
        final encPayload = map['encryptedPayload'];
        if (encPayload != null && encPayload.isNotEmpty) {
          try {
            final decryptedJson = await cryptoService.decryptWithPasscode(
              encryptedJson: encPayload,
              deviceId: normalized,
              passcode: cleanPasscode,
            );
            final cardMap = jsonDecode(decryptedJson) as Map<String, dynamic>;
            final ik = cardMap['ik']?.toString();
            final dh = cardMap['dh']?.toString();
            final name = cardMap['name']?.toString();
            if (ik != null && dh != null) {
              signalingClient.recordPeerKeys(
                peerDeviceId: normalized,
                ik: ik,
                dh: dh,
              );
              final res = <String, String>{
                'deviceId': normalized,
                'ik': ik,
                'dh': dh,
              };
              if (name != null && name.trim().isNotEmpty) {
                res['name'] = name.trim();
              }
              debugPrint('[ConnectionManager] Instantly resolved peer card for $normalized via directory');
              finish(res);
            }
          } catch (e) {
            debugPrint('[ConnectionManager] Directory card decryption failed: $e');
            finish(null, const FormatException('INCORRECT_PASSCODE'));
          }
        }
      }
    });

    // 5. Listen for live key_response / key_rejected
    envSub = signalingClient.onEnvelopeReceived.listen((env) {
      if (env.from.trim().toUpperCase() == normalized) {
        if (env.type == 'key_rejected') {
          finish(null, const FormatException('INCORRECT_PASSCODE'));
        } else if (env.type == 'key_response' &&
            env.senderIdentityPublicKey != null &&
            env.senderDhPublicKey != null) {
          signalingClient.recordPeerKeys(
            peerDeviceId: normalized,
            ik: env.senderIdentityPublicKey!,
            dh: env.senderDhPublicKey!,
          );
          final peerName = (env.payload.trim().isNotEmpty && env.payload.trim() != 'key_response')
              ? env.payload.trim()
              : null;
          final res = <String, String>{
            'deviceId': normalized,
            'ik': env.senderIdentityPublicKey!,
            'dh': env.senderDhPublicKey!,
          };
          if (peerName != null && peerName.isNotEmpty) {
            res['name'] = peerName;
          }
          finish(res);
        }
      }
    });

    timeoutTimer = Timer(timeout, () {
      finish(null);
    });

    return completer.future;
  }

  void _init() {
    secureKeyStore?.getDisplayName().then((name) {
      if (name != null && name.trim().isNotEmpty && name.trim() != _myDisplayName) {
        _myDisplayName = name.trim();
        notifyListeners();
      }
    });

    // 1. Listen for incoming zero-knowledge encrypted envelopes
    _envelopeSub = signalingClient.onEnvelopeReceived.listen(_handleIncomingEnvelope);

    // 2. Listen for signaling server connectivity changes
    _signalingStateSub = signalingClient.onStateChanged.listen((state) {
      if (state == SignalingServerState.connected) {
        publishEncryptedDirectoryCard();
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

  /// Sends a real-time history toggle sync packet to the peer
  Future<void> sendHistoryToggle({
    required ContactModel contact,
    required bool saveHistory,
  }) async {
    if (signalingClient.state == SignalingServerState.connected) {
      final envelope = SignalingEnvelope(
        to: contact.peerDeviceId,
        from: myIdentity.deviceId,
        type: 'history_toggle',
        payload: saveHistory ? 'true' : 'false',
        saveHistory: saveHistory,
        timestamp: DateTime.now(),
      );
      signalingClient.sendEnvelope(envelope);
    }
  }

  /// Sends a plaintext message to a contact:
  /// 1. Derives/reuses E2EE session key
  /// 2. Encrypts plaintext into AES-256-GCM ciphertext
  /// 3. Saves ciphertext to local database (ONLY if saveHistory == true)
  /// 4. If peer is online, delivers immediately; otherwise keeps in local outbox (if saved)
  Future<MessageModel> sendMessage({
    required ContactModel contact,
    required ConversationModel conversation,
    required String text,
    MessageType messageType = MessageType.text,
    bool saveHistory = false,
    MessageModel? replyTo,
    String? replySenderName,
  }) async {
    // Derive or retrieve shared session key
    final sessionKey = await _getOrDeriveSessionKey(contact);

    // Extract reply snippet & media type if replyTo is present
    Map<String, dynamic>? replyToMap;
    String? rText;
    String? rMediaType;
    if (replyTo != null) {
      final ep = EphemeralMediaPayload.tryParse(replyTo.decryptedContent ?? '');
      if (ep != null) {
        rMediaType = ep.mediaType;
        rText = (ep.caption != null && ep.caption!.trim().isNotEmpty)
            ? ep.caption!
            : (ep.mediaType == 'video' ? 'Video' : 'Photo');
      } else {
        rMediaType = replyTo.messageType == MessageType.video
            ? 'video'
            : (replyTo.messageType == MessageType.image ? 'photo' : 'text');
        rText = replyTo.decryptedContent ?? '';
      }
      replyToMap = {
        'id': replyTo.id,
        'sender_name': replySenderName ?? 'Message',
        'text': rText,
        'media_type': rMediaType,
      };
    }

    // Pack text, senderName, and reply_to inside AES-256-GCM encrypted payload
    final payloadMap = <String, dynamic>{
      'type': 'text_msg',
      'text': text,
      if (_myDisplayName != null && _myDisplayName!.isNotEmpty) 'sender_name': _myDisplayName,
      'reply_to': ?replyToMap,
    };
    final plaintextJson = jsonEncode(payloadMap);

    // Encrypt into ciphertext JSON (n, c, m)
    final ciphertext = await cryptoService.encryptMessage(
      plaintext: plaintextJson,
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
      replyToMessageId: replyTo?.id,
      replySenderName: replySenderName,
      replyText: rText,
      replyMediaType: rMediaType,
    );

    // Save strictly ciphertext in local database ONLY when saveHistory is true; otherwise keep in transient session memory
    if (saveHistory) {
      await chatRepository.saveMessage(message);
    } else {
      chatRepository.addTransientMessage(message);
    }
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
          saveHistory: saveHistory,
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

  /// Sends a zero-storage Snapchat-style ephemeral photo or video
  Future<MessageModel> sendEphemeralMedia({
    required ContactModel contact,
    required ConversationModel conversation,
    required Uint8List rawBytes,
    required String mediaType, // 'photo' | 'video'
    String? caption,
    bool saveHistory = false,
    MessageModel? replyTo,
    String? replySenderName,
  }) async {
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${myIdentity.deviceId.hashCode.abs()}';
    final now = DateTime.now();

    String? rText;
    String? rMediaType;
    if (replyTo != null) {
      final ep = EphemeralMediaPayload.tryParse(replyTo.decryptedContent ?? '');
      if (ep != null) {
        rMediaType = ep.mediaType;
        rText = (ep.caption != null && ep.caption!.trim().isNotEmpty)
            ? ep.caption!
            : (ep.mediaType == 'video' ? 'Video' : 'Photo');
      } else {
        rMediaType = replyTo.messageType == MessageType.video
            ? 'video'
            : (replyTo.messageType == MessageType.image ? 'photo' : 'text');
        rText = replyTo.decryptedContent ?? '';
      }
    }

    // 1. Encrypt and upload payload (senderName is encrypted inside media payload)
    final mediaPayload = await ephemeralMediaService.encryptAndUpload(
      rawBytes: rawBytes,
      mediaType: mediaType,
      caption: caption,
      senderName: _myDisplayName,
      messageId: messageId,
      replyToMessageId: replyTo?.id,
      replySenderName: replySenderName,
      replyText: rText,
      replyMediaType: rMediaType,
    );
    final payloadJson = mediaPayload.toJson();

    // 2. Encrypt metadata payload with Peer's E2EE session key
    final sessionKey = await _getOrDeriveSessionKey(contact);
    final ciphertext = await cryptoService.encryptMessage(
      plaintext: payloadJson,
      sessionKeyBytes: sessionKey,
    );

    final msgType = mediaType == 'video' ? MessageType.video : MessageType.image;

    final message = MessageModel(
      id: messageId,
      conversationId: conversation.id,
      senderId: myIdentity.deviceId,
      ciphertext: ciphertext,
      timestamp: now,
      status: MessageStatus.pending,
      messageType: msgType,
      viewCount: 0,
      isExpired: false,
      decryptedContent: payloadJson,
      replyToMessageId: replyTo?.id,
      replySenderName: replySenderName,
      replyText: rText,
      replyMediaType: rMediaType,
    );

    if (saveHistory) {
      await chatRepository.saveMessage(message);
    } else {
      chatRepository.addTransientMessage(message);
    }
    notifyListeners();

    // Attempt delivery via signaling
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
          saveHistory: saveHistory,
          timestamp: now,
        );
        signalingClient.sendEnvelope(envelope);

        await chatRepository.updateMessageStatus(messageId, MessageStatus.sent);
        final sentMessage = message.copyWith(status: MessageStatus.sent);
        notifyListeners();
        return sentMessage;
      } catch (_) {}
    }

    return message;
  }

  /// Marks an ephemeral media message as viewed, incrementing viewCount and updating expiry
  Future<void> markEphemeralMessageViewed(MessageModel message) async {
    final newCount = message.viewCount + 1;
    await chatRepository.updateMessageViewCount(message.id, newCount);
    notifyListeners();
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
                senderName: _myDisplayName,
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

        // Passcode valid -> Register verified peer contact and send public keys
        if (envelope.senderIdentityPublicKey != null && envelope.senderDhPublicKey != null) {
          final existingContact = await contactRepository.findByPeerDeviceId(senderDeviceId);
          if (existingContact == null) {
            final prefix = senderDeviceId.length >= 4 ? senderDeviceId.substring(0, 4) : senderDeviceId;
            final newContact = await contactRepository.addContact(
              peerDeviceId: senderDeviceId,
              peerIdentityPublicKey: envelope.senderIdentityPublicKey!,
              peerDhPublicKey: envelope.senderDhPublicKey!,
              nickname: 'User $prefix',
            );
            await chatRepository.getOrCreateConversation(newContact.id);
            notifyListeners();
          }
        }

        final replyEnvelope = SignalingEnvelope(
          to: senderDeviceId,
          from: myIdentity.deviceId,
          type: 'key_response',
          senderIdentityPublicKey: myIdentity.identityPublicKeyHex,
          senderDhPublicKey: myIdentity.dhPublicKeyHex,
          timestamp: DateTime.now(),
          payload: (_myDisplayName != null && _myDisplayName!.isNotEmpty) ? _myDisplayName! : 'key_response',
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
      final msgIds = envelope.payload.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      for (final id in msgIds) {
        await chatRepository.updateMessageStatus(id, MessageStatus.read);
        _readReceiptStreamController.add(id);
      }
      notifyListeners();
      return;
    }

    if (envelope.type == 'history_toggle') {
      final isSaveEnabled = envelope.saveHistory == true || envelope.payload.trim().toLowerCase() == 'true';
      _historyToggleController.add((peerDeviceId: senderDeviceId, saveHistory: isSaveEnabled));
      notifyListeners();
      return;
    }

    if (envelope.type == 'message') {
      // Find or verify contact
      var contact = await contactRepository.findByPeerDeviceId(senderDeviceId);
      if (contact == null) {
        if (envelope.senderIdentityPublicKey != null && envelope.senderDhPublicKey != null) {
          final prefix = senderDeviceId.length >= 4 ? senderDeviceId.substring(0, 4) : senderDeviceId;
          contact = await contactRepository.addContact(
            peerDeviceId: senderDeviceId,
            peerIdentityPublicKey: envelope.senderIdentityPublicKey!,
            peerDhPublicKey: envelope.senderDhPublicKey!,
            nickname: 'User $prefix',
          );
          await chatRepository.getOrCreateConversation(contact.id);
          notifyListeners();
        } else {
          debugPrint('[ConnectionManager] Dropping message from unknown/unauthorized sender $senderDeviceId');
          return;
        }
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

      MessageType msgType = MessageType.text;
      String? senderNameFromEncryptedPayload;
      String displayContent = decryptedText;
      String? replyToId;
      String? replySender;
      String? replyTxt;
      String? replyMedia;

      final ephemeralPayload = EphemeralMediaPayload.tryParse(decryptedText);
      if (ephemeralPayload != null) {
        msgType = ephemeralPayload.mediaType == 'video' ? MessageType.video : MessageType.image;
        senderNameFromEncryptedPayload = ephemeralPayload.senderName;
        replyToId = ephemeralPayload.replyToMessageId;
        replySender = ephemeralPayload.replySenderName;
        replyTxt = ephemeralPayload.replyText;
        replyMedia = ephemeralPayload.replyMediaType;
      } else {
        try {
          final map = jsonDecode(decryptedText);
          if (map is Map<String, dynamic> && map.containsKey('text')) {
            displayContent = map['text'] as String? ?? '';
            senderNameFromEncryptedPayload = (map['sender_name'] ?? map['senderName']) as String?;
            if (map['reply_to'] is Map) {
              final rMap = map['reply_to'] as Map;
              replyToId = rMap['id'] as String?;
              replySender = rMap['sender_name'] as String?;
              replyTxt = rMap['text'] as String?;
              replyMedia = rMap['media_type'] as String?;
            }
          }
        } catch (_) {
          // Plaintext string fallback
        }
      }

      // If sender included their name in the E2EE payload, assign/update placeholder nickname
      if (senderNameFromEncryptedPayload != null && senderNameFromEncryptedPayload.trim().isNotEmpty) {
        final newName = senderNameFromEncryptedPayload.trim();
        if (contact.nickname.startsWith('User ') || contact.nickname.startsWith('Contact (') || contact.nickname.toUpperCase() == contact.peerDeviceId.toUpperCase()) {
          await contactRepository.updateNickname(contactId: contact.id, newNickname: newName);
          contact = contact.copyWith(nickname: newName);
          notifyListeners();
        }
      }

      final incomingMessage = MessageModel(
        id: envelope.messageId ?? 'recv_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversation.id,
        senderId: senderDeviceId,
        ciphertext: envelope.payload,
        timestamp: envelope.timestamp,
        status: MessageStatus.delivered,
        messageType: msgType,
        viewCount: 0,
        isExpired: false,
        decryptedContent: displayContent,
        replyToMessageId: replyToId,
        replySenderName: replySender,
        replyText: replyTxt,
        replyMediaType: replyMedia,
      );

      final bool shouldSave = envelope.saveHistory == true;
      if (shouldSave) {
        await chatRepository.saveMessage(incomingMessage);
      } else {
        chatRepository.addTransientMessage(incomingMessage);
      }

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
      String actualText = decrypted;
      try {
        final ep = EphemeralMediaPayload.tryParse(decrypted);
        if (ep != null) {
          message.replyToMessageId = ep.replyToMessageId;
          message.replySenderName = ep.replySenderName;
          message.replyText = ep.replyText;
          message.replyMediaType = ep.replyMediaType;
        } else {
          final map = jsonDecode(decrypted);
          if (map is Map<String, dynamic> && map.containsKey('text')) {
            actualText = map['text'] as String? ?? '';
            if (map['reply_to'] is Map) {
              final rMap = map['reply_to'] as Map;
              message.replyToMessageId = rMap['id'] as String?;
              message.replySenderName = rMap['sender_name'] as String?;
              message.replyText = rMap['text'] as String?;
              message.replyMediaType = rMap['media_type'] as String?;
            }
          }
        }
      } catch (_) {}
      message.decryptedContent = actualText;
      return actualText;
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
    _historyToggleController.close();
    super.dispose();
  }
}
