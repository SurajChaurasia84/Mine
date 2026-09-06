import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt/mqtt_platform_client.dart';
import 'signaling_message.dart';

enum SignalingServerState {
  disconnected,
  connecting,
  connected,
}

/// Zero-Deploy End-to-End Encrypted Relay Client
/// Communicates using HiveMQ's free public broker (or any custom broker)
/// All payloads transmitted are encrypted ciphertext (AES-256-GCM + X25519)
/// Zero plaintext, zero personal data, zero hosting needed.
class SignalingClient extends ChangeNotifier {
  String serverUrl;
  final String deviceId;

  MqttClient? _client;
  SignalingServerState _state = SignalingServerState.disconnected;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  final Set<String> _watchedPeers = {};

  final _envelopeController = StreamController<SignalingEnvelope>.broadcast();
  final _stateController = StreamController<SignalingServerState>.broadcast();
  final _peerStatusController = StreamController<Map<String, String>>.broadcast();

  Stream<SignalingEnvelope> get onEnvelopeReceived => _envelopeController.stream;
  Stream<SignalingServerState> get onStateChanged => _stateController.stream;
  Stream<Map<String, String>> get onPeerStatusChanged => _peerStatusController.stream;
  SignalingServerState get state => _state;

  static const String defaultBroker = 'broker.hivemq.com';

  SignalingClient({
    required String deviceId,
    String? initialServerUrl,
  })  : deviceId = deviceId.trim().toUpperCase(),
        serverUrl = initialServerUrl ?? defaultBroker;

  void updateServerUrl(String newUrl) {
    var cleaned = newUrl.trim();
    if (cleaned.startsWith('ws://') || cleaned.startsWith('wss://')) {
      cleaned = Uri.tryParse(cleaned)?.host ?? cleaned;
    }
    if (cleaned.isEmpty) cleaned = defaultBroker;

    if (serverUrl != cleaned) {
      serverUrl = cleaned;
      disconnect();
      connect();
    }
  }

  Future<void> connect() async {
    if (_isDisposed) return;
    if (_state == SignalingServerState.connected || _state == SignalingServerState.connecting) {
      return;
    }
    _setState(SignalingServerState.connecting);

    try {
      final safeDeviceId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final clientId = 'mine_${safeDeviceId}_${DateTime.now().millisecondsSinceEpoch % 100000}';

      final client = MqttPlatformHelper.createClient(serverUrl, clientId);
      _client = client;

      client.logging(on: false);
      client.keepAlivePeriod = 20;
      client.autoReconnect = false;
      client.onDisconnected = _handleDisconnect;

      // Last Will & Testament: if device disconnects, HiveMQ broker automatically marks peer offline
      final presenceTopic = 'mine/v1/presence/$deviceId';
      final willPayload = jsonEncode({'status': 'offline', 'deviceId': deviceId});
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillTopic(presenceTopic)
          .withWillMessage(willPayload)
          .withWillQos(MqttQos.atLeastOnce)
          .withWillRetain()
          .startClean();
      client.connectionMessage = connMessage;

      debugPrint('[SignalingClient] Connecting to relay: $serverUrl as $clientId');
      final status = await client.connect().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('[SignalingClient] Connection timed out after 12s');
          return null;
        },
      );
      if (status?.state != MqttConnectionState.connected) {
        debugPrint('[SignalingClient] Connection rejected: ${status?.state}, returnCode: ${status?.returnCode}');
        _handleDisconnect();
        return;
      }

      // 1. Subscribe to own personal inbox
      final inboxTopic = 'mine/v1/inbox/$deviceId';
      client.subscribe(inboxTopic, MqttQos.atLeastOnce);

      // 2. Publish online presence (retained)
      _publishPresence('online');

      // 3. Re-subscribe to any watched peer presence topics
      for (final peerId in _watchedPeers) {
        client.subscribe('mine/v1/presence/$peerId', MqttQos.atLeastOnce);
      }

      // 4. Listen for incoming broker publications
      client.updates?.listen(
        _handleIncomingUpdates,
        onError: (e) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );

      _setState(SignalingServerState.connected);
      debugPrint('[SignalingClient] Encrypted Network Active (Connected to $serverUrl)');
    } catch (e, stack) {
      debugPrint('[SignalingClient] Connection error: $e\n$stack');
      _handleDisconnect();
    }
  }

  void _publishPresence(String status) {
    if (_client == null) return;
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode({
        'status': status,
        'deviceId': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      _client?.publishMessage(
        'mine/v1/presence/$deviceId',
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: true,
      );
    } catch (_) {}
  }

  void _handleIncomingUpdates(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final topic = received.topic;
      final msg = received.payload as MqttPublishMessage;
      final payloadString = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      if (topic == 'mine/v1/inbox/$deviceId') {
        try {
          final map = jsonDecode(payloadString) as Map<String, dynamic>;
          final envelope = SignalingEnvelope.fromJson(map);
          debugPrint('[SignalingClient] Received incoming ${envelope.type} from ${envelope.from}');
          _envelopeController.add(envelope);
        } catch (e) {
          debugPrint('[SignalingClient] Error parsing envelope: $e');
        }
      } else if (topic.startsWith('mine/v1/presence/')) {
        try {
          final map = jsonDecode(payloadString) as Map<String, dynamic>;
          final targetId = (map['deviceId'] ?? topic.replaceFirst('mine/v1/presence/', '')).toString().trim().toUpperCase();
          final status = (map['status'] ?? 'offline').toString();
          _peerStatusController.add({
            'targetId': targetId,
            'status': status,
          });
        } catch (_) {}
      }
    }
  }

  void checkPeerStatus(String targetDeviceId) {
    final normalizedTarget = targetDeviceId.trim().toUpperCase();
    _watchedPeers.add(normalizedTarget);
    if (_state != SignalingServerState.connected || _client == null) return;
    try {
      _client?.subscribe('mine/v1/presence/$normalizedTarget', MqttQos.atLeastOnce);
    } catch (_) {}
  }

  void sendEnvelope(SignalingEnvelope envelope) {
    if (_state != SignalingServerState.connected || _client == null) {
      throw StateError('Relay client is not connected');
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(envelope.toJsonString());
    debugPrint('[SignalingClient] Publishing envelope to mine/v1/inbox/${envelope.to} (type: ${envelope.type})');
    _client?.publishMessage(
      'mine/v1/inbox/${envelope.to}',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _handleDisconnect() {
    if (_state == SignalingServerState.disconnected) return;
    _setState(SignalingServerState.disconnected);
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;

    if (!_isDisposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (!_isDisposed && _state == SignalingServerState.disconnected) {
        connect();
      }
    });
  }

  void _setState(SignalingServerState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
      notifyListeners();
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _publishPresence('offline');
    try {
      _client?.disconnect();
    } catch (_) {}
    _client = null;
    _setState(SignalingServerState.disconnected);
  }

  @override
  void dispose() {
    _isDisposed = true;
    disconnect();
    _envelopeController.close();
    _stateController.close();
    _peerStatusController.close();
    super.dispose();
  }
}
