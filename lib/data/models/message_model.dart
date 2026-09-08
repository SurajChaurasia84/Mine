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
  video,
  file,
  system,
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
  final int viewCount; // For ephemeral media (0 = unopened, 1 = viewed once / replay left, 2+ = expired)
  final bool isExpired;

  // Transient memory-only fields (decrypted in memory, never written to disk in plaintext)
  String? decryptedContent;
  String? localAttachmentPath;
  String? replyToMessageId;
  String? replySenderName;
  String? replyText;
  String? replyMediaType;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.ciphertext,
    required this.timestamp,
    required this.status,
    required this.messageType,
    this.viewCount = 0,
    this.isExpired = false,
    this.decryptedContent,
    this.localAttachmentPath,
    this.replyToMessageId,
    this.replySenderName,
    this.replyText,
    this.replyMediaType,
  });

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? ciphertext,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? messageType,
    int? viewCount,
    bool? isExpired,
    String? decryptedContent,
    String? localAttachmentPath,
    String? replyToMessageId,
    String? replySenderName,
    String? replyText,
    String? replyMediaType,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      ciphertext: ciphertext ?? this.ciphertext,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      messageType: messageType ?? this.messageType,
      viewCount: viewCount ?? this.viewCount,
      isExpired: isExpired ?? this.isExpired,
      decryptedContent: decryptedContent ?? this.decryptedContent,
      localAttachmentPath: localAttachmentPath ?? this.localAttachmentPath,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replySenderName: replySenderName ?? this.replySenderName,
      replyText: replyText ?? this.replyText,
      replyMediaType: replyMediaType ?? this.replyMediaType,
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
      'view_count': viewCount,
      'is_expired': isExpired ? 1 : 0,
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
      viewCount: (map['view_count'] as num?)?.toInt() ?? 0,
      isExpired: ((map['is_expired'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
