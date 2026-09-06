import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_pair_bundle.dart';
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

  // Track real-time connectivity status per peer device ID
  final Map<String, PeerConnectionState> _peerStates = {};

  // Cache derived session keys: peerDeviceId -> List<int>
  final Map<String, List<int>> _sessionKeys = {};

  StreamSubscription? _envelopeSub;
  StreamSubscription? _signalingStateSub;
  StreamSubscription? _peerStatusSub;
  final bool enablePeriodicFlush;
  Timer? _outboxPollTimer;

  final _messageStreamController = StreamController<MessageModel>.broadcast();
  final _receiptStreamController = StreamController<String>.broadcast();

  Stream<MessageModel> get onMessageReceived => _messageStreamController.stream;
  Stream<String> get onDeliveryReceipt => _receiptStreamController.stream;

  ConnectionManager({
    required this.myIdentity,
    required this.cryptoService,
    required this.contactRepository,
    required this.chatRepository,
    required this.signalingClient,
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
        final isOnline = status == 'online';
        final newState = isOnline ? PeerConnectionState.online : PeerConnectionState.offline;
        if (_peerStates[peerId] != newState) {
          _peerStates[peerId] = newState;
          notifyListeners();
          if (isOnline) {
            _deliverPendingForPeer(peerId);
          }
        }
      }
    });

    if (enablePeriodicFlush) {
      // 4. Start periodic outbox flush timer (every 10s)
      _outboxPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        flushOutbox();
      });

      // Connect to signaling gateway
      signalingClient.connect();
    }
  }

  /// Returns current connectivity state for a given peer device ID
  PeerConnectionState getPeerState(String peerDeviceId) {
    return _peerStates[peerDeviceId] ?? PeerConnectionState.offline;
  }

  /// Actively checks status of a peer
  void checkPeer(String peerDeviceId) {
    signalingClient.checkPeerStatus(peerDeviceId);
  }

  void _checkAllPeersStatus() async {
    final contacts = await contactRepository.getContacts();
    for (final contact in contacts) {
      signalingClient.checkPeerStatus(contact.peerDeviceId);
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

        final isPeerOnline = getPeerState(contact.peerDeviceId) == PeerConnectionState.online;
        if (isPeerOnline) {
          // Update to sent
          await chatRepository.updateMessageStatus(messageId, MessageStatus.sent);
          final sentMessage = message.copyWith(status: MessageStatus.sent);
          notifyListeners();
          return sentMessage;
        }
      } catch (_) {
        // Remains pending in outbox
      }
    }

    return message;
  }

  /// Delivers pending outbox messages for all online peers
  Future<void> flushOutbox() async {
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
    _peerStates[senderDeviceId] = PeerConnectionState.online;

    if (envelope.type == 'delivery_receipt') {
      final msgId = envelope.messageId;
      if (msgId != null) {
        await chatRepository.updateMessageStatus(msgId, MessageStatus.delivered);
        _receiptStreamController.add(msgId);
        notifyListeners();
      }
      return;
    }

    if (envelope.type == 'message') {
      // Find or verify contact
      var contact = await contactRepository.findByPeerDeviceId(senderDeviceId);
      if (contact == null) {
        // Auto-register peer contact if public keys are provided in envelope
        if (envelope.senderDhPublicKey != null && envelope.senderIdentityPublicKey != null) {
          final prefix = senderDeviceId.length >= 4 ? senderDeviceId.substring(0, 4) : senderDeviceId;
          contact = await contactRepository.addContact(
            peerDeviceId: senderDeviceId,
            peerIdentityPublicKey: envelope.senderIdentityPublicKey!,
            peerDhPublicKey: envelope.senderDhPublicKey!,
            nickname: 'Contact $prefix',
          );
        } else {
          // Unknown sender without public keys - cannot decrypt
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

  @override
  void dispose() {
    _envelopeSub?.cancel();
    _signalingStateSub?.cancel();
    _peerStatusSub?.cancel();
    _outboxPollTimer?.cancel();
    _messageStreamController.close();
    _receiptStreamController.close();
    super.dispose();
  }
}
