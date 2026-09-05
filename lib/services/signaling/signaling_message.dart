import 'dart:convert';

/// Envelope for sending encrypted packets over zero-knowledge transport.
/// The transport layer/server sees only:
/// - to (peer's ephemeral/device ID)
/// - from (sender's ephemeral/device ID)
/// - type
/// - opaque ciphertext payload (AES-GCM encrypted)
class SignalingEnvelope {
  final String to;
  final String from;
  final String type; // 'message', 'delivery_receipt', 'ping'
  final String payload; // Ciphertext
  final String? messageId;
  final DateTime timestamp;

  SignalingEnvelope({
    required this.to,
    required this.from,
    required this.type,
    required this.payload,
    this.messageId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String toJsonString() {
    return jsonEncode({
      'type': 'envelope',
      'to': to,
      'from': from,
      'subType': type,
      'payload': payload,
      'messageId': messageId,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  factory SignalingEnvelope.fromJson(Map<String, dynamic> map) {
    return SignalingEnvelope(
      to: map['to'] as String,
      from: map['from'] as String,
      type: (map['subType'] ?? map['type']) as String,
      payload: (map['payload'] ?? '') as String,
      messageId: map['messageId'] as String?,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'] as String)
          : DateTime.now(),
    );
  }
}
