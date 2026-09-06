import 'contact_model.dart';
import 'message_model.dart';

/// Represents a conversation thread linked to a specific contact.
class ConversationModel {
  final String id;
  final String contactId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;

  // Joined/transient fields for UI rendering
  ContactModel? contact;
  String? lastMessageSnippet;
  int unreadCount;
  MessageStatus? lastMessageStatus;
  bool lastMessageIsMe;

  ConversationModel({
    required this.id,
    required this.contactId,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.contact,
    this.lastMessageSnippet,
    this.unreadCount = 0,
    this.lastMessageStatus,
    this.lastMessageIsMe = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contact_id': contactId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_at': lastMessageAt?.toIso8601String(),
    };
  }

  factory ConversationModel.fromMap(Map<String, dynamic> map) {
    return ConversationModel(
      id: map['id'] as String,
      contactId: map['contact_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.parse(map['last_message_at'] as String)
          : null,
    );
  }
}
