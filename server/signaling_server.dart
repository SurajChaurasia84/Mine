import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal Zero-Knowledge Signaling & Blind Rendezvous Server for "Mine".
///
/// Principles:
/// - ZERO persistence: No database, no chat storage, no message logs.
/// - ZERO knowledge: Server sees only opaque encrypted bytes and ephemeral routing IDs.
/// - Transient routing: Forwards encrypted packets between active peers; dropped if recipient is offline.
/// - Clean teardown: State disappears the moment sockets close.
void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('=== Mine Zero-Knowledge Signaling Server ===');
  print('Listening on ws://0.0.0.0:$port');

  // Ephemeral map: deviceId -> WebSocket
  final Map<String, WebSocket> activePeers = {};

  server.listen((HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      String? peerDeviceId;

      socket.listen(
        (data) {
          try {
            final raw = data.toString();
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'register') {
              // Peer registers ephemeral presence
              peerDeviceId = json['deviceId'] as String?;
              if (peerDeviceId != null) {
                activePeers[peerDeviceId!] = socket;
                print('[Presence] Peer registered: $peerDeviceId');
                // Acknowledge registration
                socket.add(jsonEncode({'type': 'registered', 'deviceId': peerDeviceId}));
              }
            } else if (type == 'ping') {
              socket.add(jsonEncode({'type': 'pong'}));
            } else if (type == 'envelope') {
              // Blind forwarding of encrypted envelope
              final to = json['to'] as String?;
              if (to != null && activePeers.containsKey(to)) {
                final targetSocket = activePeers[to];
                targetSocket?.add(raw);
              } else {
                // Peer is offline - notify sender so outbox can hold message locally
                socket.add(jsonEncode({
                  'type': 'peer_status',
                  'targetId': to,
                  'status': 'offline',
                }));
              }
            } else if (type == 'check_status') {
              final target = json['targetId'] as String?;
              final isOnline = target != null && activePeers.containsKey(target);
              socket.add(jsonEncode({
                'type': 'peer_status',
                'targetId': target,
                'status': isOnline ? 'online' : 'offline',
              }));
            }
          } catch (e) {
            print('[Error] Processing frame: $e');
          }
        },
        onDone: () {
          if (peerDeviceId != null) {
            activePeers.remove(peerDeviceId);
            print('[Presence] Peer disconnected: $peerDeviceId');
          }
        },
        onError: (err) {
          if (peerDeviceId != null) {
            activePeers.remove(peerDeviceId);
          }
        },
      );
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('Mine Zero-Knowledge Signaling Gateway Running')
        ..close();
    }
  });
}
