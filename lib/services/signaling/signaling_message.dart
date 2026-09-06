import 'dart:convert';

/// Envelope for sending encrypted packets over zero-knowledge transport.
/// The transport layer/server sees only:
/// - to (peer's normalized device ID)
/// - from (sender's normalized device ID)
/// - type ('message', 'delivery_receipt')
/// - opaque ciphertext payload (AES-256-GCM encrypted)
/// - public keys for zero-configuration handshake
class SignalingEnvelope {
  final String to;
  final String from;
  final String type; // 'message', 'delivery_receipt', 'ping'
  final String payload; // Ciphertext
  final String? messageId;
  final String? senderDhPublicKey;
  final String? senderIdentityPublicKey;
  final DateTime timestamp;

  SignalingEnvelope({
    required String to,
    required String from,
    required this.type,
    required this.payload,
    this.messageId,
    this.senderDhPublicKey,
    this.senderIdentityPublicKey,
    DateTime? timestamp,
  })  : to = to.trim().toUpperCase(),
        from = from.trim().toUpperCase(),
        timestamp = timestamp ?? DateTime.now();

  String toJsonString() {
    return jsonEncode({
      'type': 'envelope',
      'to': to,
      'from': from,
      'subType': type,
      'payload': payload,
      'messageId': messageId,
      'senderDhPublicKey': senderDhPublicKey,
      'senderIdentityPublicKey': senderIdentityPublicKey,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  factory SignalingEnvelope.fromJson(Map<String, dynamic> map) {
    return SignalingEnvelope(
      to: (map['to'] ?? '') as String,
      from: (map['from'] ?? '') as String,
      type: (map['subType'] ?? map['type'] ?? 'message') as String,
      payload: (map['payload'] ?? '') as String,
      messageId: map['messageId'] as String?,
      senderDhPublicKey: map['senderDhPublicKey'] as String?,
      senderIdentityPublicKey: map['senderIdentityPublicKey'] as String?,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
    );
  }
}
