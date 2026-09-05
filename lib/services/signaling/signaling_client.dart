import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'signaling_message.dart';

enum SignalingServerState {
  disconnected,
  connecting,
  connected,
}

class SignalingClient {
  String serverUrl;
  final String deviceId;

  WebSocketChannel? _channel;
  SignalingServerState _state = SignalingServerState.disconnected;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isDisposed = false;

  final _envelopeController = StreamController<SignalingEnvelope>.broadcast();
  final _stateController = StreamController<SignalingServerState>.broadcast();
  final _peerStatusController = StreamController<Map<String, String>>.broadcast();

  Stream<SignalingEnvelope> get onEnvelopeReceived => _envelopeController.stream;
  Stream<SignalingServerState> get onStateChanged => _stateController.stream;
  Stream<Map<String, String>> get onPeerStatusChanged => _peerStatusController.stream;
  SignalingServerState get state => _state;

  SignalingClient({
    required this.deviceId,
    String? initialServerUrl,
  }) : serverUrl = initialServerUrl ?? _defaultServerUrl();

  static String _defaultServerUrl() {
    // 10.0.2.2 points to host on Android Emulator; fallback to localhost
    if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8080';
    }
    return 'ws://127.0.0.1:8080';
  }

  void updateServerUrl(String newUrl) {
    if (serverUrl != newUrl) {
      serverUrl = newUrl;
      disconnect();
      connect();
    }
  }

  Future<void> connect() async {
    if (_state == SignalingServerState.connected || _state == SignalingServerState.connecting) {
      return;
    }
    _setState(SignalingServerState.connecting);

    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      // Register device identity
      final registerFrame = jsonEncode({
        'type': 'register',
        'deviceId': deviceId,
      });
      _channel?.sink.add(registerFrame);

      _channel?.stream.listen(
        (data) {
          _handleIncomingData(data.toString());
        },
        onDone: () {
          _handleDisconnect();
        },
        onError: (err) {
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      _setState(SignalingServerState.connected);
      _startHeartbeat();
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleIncomingData(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;

      if (type == 'registered') {
        _setState(SignalingServerState.connected);
      } else if (type == 'envelope') {
        final envelope = SignalingEnvelope.fromJson(map);
        _envelopeController.add(envelope);
      } else if (type == 'peer_status') {
        _peerStatusController.add({
          'targetId': (map['targetId'] ?? '') as String,
          'status': (map['status'] ?? 'offline') as String,
        });
      }
    } catch (_) {}
  }

  void checkPeerStatus(String targetDeviceId) {
    if (_state != SignalingServerState.connected) return;
    try {
      _channel?.sink.add(jsonEncode({
        'type': 'check_status',
        'targetId': targetDeviceId,
      }));
    } catch (_) {}
  }

  void sendEnvelope(SignalingEnvelope envelope) {
    if (_state != SignalingServerState.connected) {
      throw StateError('Signaling client is not connected');
    }
    _channel?.sink.add(envelope.toJsonString());
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_state == SignalingServerState.connected) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {
          _handleDisconnect();
        }
      }
    });
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _setState(SignalingServerState.disconnected);
    _channel?.sink.close();
    _channel = null;

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
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(SignalingServerState.disconnected);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _envelopeController.close();
    _stateController.close();
    _peerStatusController.close();
  }
}
