enum MessageStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
}

enum MessageType {
  text,
  image,
  file,
}

/// Represents an end-to-end encrypted message record.
/// Plaintext content is NEVER stored in the database.
class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String ciphertext;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType messageType;

  // Transient memory-only fields (decrypted in memory, never written to disk in plaintext)
  String? decryptedContent;
  String? localAttachmentPath;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.ciphertext,
    required this.timestamp,
    required this.status,
    required this.messageType,
    this.decryptedContent,
    this.localAttachmentPath,
  });

  MessageModel copyWith({
    MessageStatus? status,
    String? decryptedContent,
    String? localAttachmentPath,
  }) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      ciphertext: ciphertext,
      timestamp: timestamp,
      status: status ?? this.status,
      messageType: messageType,
      decryptedContent: decryptedContent ?? this.decryptedContent,
      localAttachmentPath: localAttachmentPath ?? this.localAttachmentPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'ciphertext': ciphertext,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'message_type': messageType.name,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      ciphertext: map['ciphertext'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.pending,
      ),
      messageType: MessageType.values.firstWhere(
        (e) => e.name == map['message_type'],
        orElse: () => MessageType.text,
      ),
    );
  }
}
