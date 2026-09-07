import 'dart:io';
import 'package:path_provider/path_provider.dart';
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

  /// Offloads ciphertext exceeding 30KB to local app storage file to prevent SQLite CursorWindow (2MB) overflow
  Future<String> _offloadCiphertextIfNeeded(String messageId, String ciphertext) async {
    if (ciphertext.length <= 30000) {
      return ciphertext;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${appDir.path}/media_blobs');
      if (!mediaDir.existsSync()) {
        mediaDir.createSync(recursive: true);
      }
      final file = File('${mediaDir.path}/$messageId.enc');
      await file.writeAsString(ciphertext, flush: true);
      return 'FILE_REF:${file.path}';
    } catch (_) {
      return ciphertext;
    }
  }

  /// Resolves ciphertext from local file if stored as FILE_REF:
  Future<String> _resolveCiphertext(String storedCiphertext) async {
    if (storedCiphertext.startsWith('FILE_REF:')) {
      final path = storedCiphertext.substring('FILE_REF:'.length);
      try {
        final file = File(path);
        if (file.existsSync()) {
          return await file.readAsString();
        }
      } catch (_) {}
    }
    return storedCiphertext;
  }

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

  /// Saves an end-to-end encrypted message (strictly ciphertext, offloading large blobs to disk)
  Future<void> saveMessage(MessageModel message) async {
    final db = await appDatabase.database;
    final safeCiphertext = await _offloadCiphertextIfNeeded(message.id, message.ciphertext);
    final messageToSave = message.copyWith(ciphertext: safeCiphertext);

    await db.transaction((txn) async {
      await txn.insert(
        'messages',
        messageToSave.toMap(),
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

  /// Updates status of a message (e.g., pending -> sent -> delivered -> read)
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final db = await appDatabase.database;
    final existing = await db.query(
      'messages',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final currentName = existing.first['status'] as String?;
      final currentStatus = MessageStatus.values.firstWhere(
        (e) => e.name == currentName,
        orElse: () => MessageStatus.pending,
      );
      if (currentStatus.index >= status.index && currentStatus != MessageStatus.failed) {
        return;
      }
    }
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Updates ephemeral view count and expired status of a message
  Future<void> updateMessageViewCount(String messageId, int viewCount) async {
    final db = await appDatabase.database;
    final isExpired = viewCount >= 2 ? 1 : 0;
    await db.update(
      'messages',
      {
        'view_count': viewCount,
        'is_expired': isExpired,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Retrieves messages for a conversation ordered chronologically
  Future<List<MessageModel>> getMessages(String conversationId) async {
    final db = await appDatabase.database;
    try {
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
      );
      final list = <MessageModel>[];
      for (final m in maps) {
        var model = MessageModel.fromMap(m);
        if (model.ciphertext.startsWith('FILE_REF:')) {
          final resolved = await _resolveCiphertext(model.ciphertext);
          model = model.copyWith(ciphertext: resolved);
        }
        list.add(model);
      }
      return list;
    } catch (e) {
      if (e.toString().contains('CursorWindow') || e.toString().contains('Row too big')) {
        // Auto-recover from oversized rows in DB by sanitizing overgrown legacy rows
        try {
          await db.rawUpdate(
            "UPDATE messages SET ciphertext = '{\"type\":\"ephemeral_media\",\"mediaType\":\"photo\",\"caption\":\"\",\"isDirect\":false,\"expired\":true}' WHERE conversation_id = ? AND length(ciphertext) > 50000",
            [conversationId],
          );
          final retryMaps = await db.query(
            'messages',
            where: 'conversation_id = ?',
            whereArgs: [conversationId],
            orderBy: 'timestamp ASC',
          );
          return retryMaps.map((m) => MessageModel.fromMap(m)).toList();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Retrieves the latest message for a conversation
  Future<MessageModel?> getLastMessage(String conversationId) async {
    final db = await appDatabase.database;
    try {
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (maps.isEmpty) return null;
      var model = MessageModel.fromMap(maps.first);
      if (model.ciphertext.startsWith('FILE_REF:')) {
        final resolved = await _resolveCiphertext(model.ciphertext);
        model = model.copyWith(ciphertext: resolved);
      }
      return model;
    } catch (e) {
      if (e.toString().contains('CursorWindow') || e.toString().contains('Row too big')) {
        try {
          await db.rawUpdate(
            "UPDATE messages SET ciphertext = '{\"type\":\"ephemeral_media\",\"mediaType\":\"photo\",\"caption\":\"\",\"isDirect\":false,\"expired\":true}' WHERE conversation_id = ? AND length(ciphertext) > 50000",
            [conversationId],
          );
          final retryMaps = await db.query(
            'messages',
            where: 'conversation_id = ?',
            whereArgs: [conversationId],
            orderBy: 'timestamp DESC',
            limit: 1,
          );
          if (retryMaps.isNotEmpty) return MessageModel.fromMap(retryMaps.first);
        } catch (_) {}
      }
      return null;
    }
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

  /// Returns count of unread incoming messages for a conversation
  Future<int> getUnreadCount(String conversationId, String myDeviceId) async {
    final db = await appDatabase.database;
    final normalizedMyId = myDeviceId.trim().toUpperCase();
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM messages
      WHERE conversation_id = ? 
        AND UPPER(TRIM(sender_id)) != ? 
        AND status != ?
    ''', [conversationId, normalizedMyId, MessageStatus.read.name]);
    if (result.isNotEmpty) {
      return (result.first['cnt'] as int?) ?? 0;
    }
    return 0;
  }
}
