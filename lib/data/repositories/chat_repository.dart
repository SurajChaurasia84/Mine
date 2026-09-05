import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/storage/app_database.dart';
import '../models/attachment_model.dart';
import '../models/contact_model.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ChatRepository {
  final AppDatabase appDatabase;
  final Uuid _uuid = const Uuid();

  ChatRepository({required this.appDatabase});

  /// Gets existing conversation for a contact or creates a new one
  Future<ConversationModel> getOrCreateConversation(String contactId) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'conversations',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return ConversationModel.fromMap(maps.first);
    }

    final now = DateTime.now();
    final newConv = ConversationModel(
      id: _uuid.v4(),
      contactId: contactId,
      createdAt: now,
      updatedAt: now,
      lastMessageAt: null,
    );

    await db.insert('conversations', newConv.toMap());
    return newConv;
  }

  /// Retrieves all conversations joined with contact details for the chat list
  Future<List<ConversationModel>> getConversations() async {
    final db = await appDatabase.database;
    final results = await db.rawQuery('''
      SELECT 
        c.id AS conv_id,
        c.contact_id,
        c.created_at AS conv_created_at,
        c.updated_at AS conv_updated_at,
        c.last_message_at,
        ct.peer_device_id,
        ct.peer_identity_public_key,
        ct.peer_dh_public_key,
        ct.nickname,
        ct.created_at AS contact_created_at,
        ct.updated_at AS contact_updated_at
      FROM conversations c
      INNER JOIN contacts ct ON c.contact_id = ct.id
      ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
    ''');

    return results.map((row) {
      final contact = ContactModel(
        id: row['contact_id'] as String,
        peerDeviceId: row['peer_device_id'] as String,
        peerIdentityPublicKey: row['peer_identity_public_key'] as String,
        peerDhPublicKey: row['peer_dh_public_key'] as String,
        nickname: row['nickname'] as String,
        createdAt: DateTime.parse(row['contact_created_at'] as String),
        updatedAt: DateTime.parse(row['contact_updated_at'] as String),
      );

      final conv = ConversationModel(
        id: row['conv_id'] as String,
        contactId: row['contact_id'] as String,
        createdAt: DateTime.parse(row['conv_created_at'] as String),
        updatedAt: DateTime.parse(row['conv_updated_at'] as String),
        lastMessageAt: row['last_message_at'] != null
            ? DateTime.parse(row['last_message_at'] as String)
            : null,
        contact: contact,
      );

      return conv;
    }).toList();
  }

  /// Saves an end-to-end encrypted message (strictly ciphertext)
  Future<void> saveMessage(MessageModel message) async {
    final db = await appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update conversation's last_message_at and updated_at
      await txn.update(
        'conversations',
        {
          'last_message_at': message.timestamp.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [message.conversationId],
      );
    });
  }

  /// Updates status of a message (e.g., pending -> sent -> delivered)
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final db = await appDatabase.database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Retrieves messages for a conversation ordered chronologically
  Future<List<MessageModel>> getMessages(String conversationId) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  /// Retrieves the latest message for a conversation
  Future<MessageModel?> getLastMessage(String conversationId) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return MessageModel.fromMap(maps.first);
  }

  /// Offline local outbox: queries all messages with status == 'pending'
  Future<List<MessageModel>> getPendingOutgoingMessages() async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'messages',
      where: 'status = ?',
      whereArgs: [MessageStatus.pending.name],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  /// Saves local attachment reference
  Future<void> saveAttachment(AttachmentModel attachment) async {
    final db = await appDatabase.database;
    await db.insert(
      'attachments',
      attachment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a single message
  Future<void> deleteMessage(String messageId) async {
    final db = await appDatabase.database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Deletes an entire conversation and associated records
  Future<void> deleteConversation(String conversationId) async {
    final db = await appDatabase.database;
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }
}
