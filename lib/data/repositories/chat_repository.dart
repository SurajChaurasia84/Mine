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

  // In-memory transient message store for temporary chats (Save History = false)
  final Map<String, List<MessageModel>> _transientMessages = {};

  ChatRepository({required this.appDatabase});

  /// Adds a temporary / transient message to in-memory active session store
  void addTransientMessage(MessageModel message) {
    final list = _transientMessages.putIfAbsent(message.conversationId, () => []);
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx != -1) {
      list[idx] = message;
    } else {
      list.add(message);
    }
  }

  /// Clears transient/temporary in-memory messages for a specific conversation
  void clearTransientMessages(String conversationId) {
    _transientMessages.remove(conversationId);
  }

  /// Clears all transient/temporary in-memory messages across all conversations
  void clearAllTransientMessages() {
    _transientMessages.clear();
  }

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

    final convs = results.map((row) {
      final contact = ContactModel(
        id: row['contact_id'] as String,
        peerDeviceId: row['peer_device_id'] as String,
        peerIdentityPublicKey: row['peer_identity_public_key'] as String,
        peerDhPublicKey: row['peer_dh_public_key'] as String,
        nickname: row['nickname'] as String,
        createdAt: DateTime.parse(row['contact_created_at'] as String),
        updatedAt: DateTime.parse(row['contact_updated_at'] as String),
      );

      DateTime? lastAt = row['last_message_at'] != null
          ? DateTime.parse(row['last_message_at'] as String)
          : null;

      final convId = row['conv_id'] as String;
      final transientList = _transientMessages[convId];
      if (transientList != null && transientList.isNotEmpty) {
        final lastTransientAt = transientList.last.timestamp;
        if (lastAt == null || lastTransientAt.isAfter(lastAt)) {
          lastAt = lastTransientAt;
        }
      }

      return ConversationModel(
        id: convId,
        contactId: row['contact_id'] as String,
        createdAt: DateTime.parse(row['conv_created_at'] as String),
        updatedAt: DateTime.parse(row['conv_updated_at'] as String),
        lastMessageAt: lastAt,
        contact: contact,
      );
    }).toList();

    // Re-sort in case an in-memory transient message bumped a conversation
    convs.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.createdAt;
      final bTime = b.lastMessageAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    return convs;
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
    for (final list in _transientMessages.values) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final current = list[idx];
        if (current.status.index < status.index || current.status == MessageStatus.failed) {
          list[idx] = current.copyWith(status: status);
        }
      }
    }

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
    final isExpired = viewCount >= 2;
    for (final list in _transientMessages.values) {
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(viewCount: viewCount, isExpired: isExpired);
      }
    }

    final db = await appDatabase.database;
    await db.update(
      'messages',
      {
        'view_count': viewCount,
        'is_expired': isExpired ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Retrieves messages for a conversation ordered chronologically
  Future<List<MessageModel>> getMessages(String conversationId) async {
    final db = await appDatabase.database;
    final list = <MessageModel>[];
    try {
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
      );
      for (final m in maps) {
        var model = MessageModel.fromMap(m);
        if (model.ciphertext.startsWith('FILE_REF:')) {
          final resolved = await _resolveCiphertext(model.ciphertext);
          model = model.copyWith(ciphertext: resolved);
        }
        list.add(model);
      }
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
          list.addAll(retryMaps.map((m) => MessageModel.fromMap(m)));
        } catch (_) {}
      } else {
        rethrow;
      }
    }

    // Merge in-memory transient messages for temporary chats
    final transientList = _transientMessages[conversationId];
    if (transientList != null && transientList.isNotEmpty) {
      final existingIds = list.map((m) => m.id).toSet();
      for (final tm in transientList) {
        if (!existingIds.contains(tm.id)) {
          list.add(tm);
        }
      }
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return list;
  }

  /// Retrieves the latest message for a conversation
  Future<MessageModel?> getLastMessage(String conversationId) async {
    MessageModel? dbLast;
    final db = await appDatabase.database;
    try {
      final maps = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (maps.isNotEmpty) {
        var model = MessageModel.fromMap(maps.first);
        if (model.ciphertext.startsWith('FILE_REF:')) {
          final resolved = await _resolveCiphertext(model.ciphertext);
          model = model.copyWith(ciphertext: resolved);
        }
        dbLast = model;
      }
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
          if (retryMaps.isNotEmpty) dbLast = MessageModel.fromMap(retryMaps.first);
        } catch (_) {}
      }
    }

    final transientList = _transientMessages[conversationId];
    if (transientList != null && transientList.isNotEmpty) {
      final lastTransient = transientList.last;
      if (dbLast == null || lastTransient.timestamp.isAfter(dbLast.timestamp)) {
        return lastTransient;
      }
    }

    return dbLast;
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
    for (final list in _transientMessages.values) {
      list.removeWhere((m) => m.id == messageId);
    }
    final db = await appDatabase.database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Deletes an entire conversation and associated records
  Future<void> deleteConversation(String conversationId) async {
    _transientMessages.remove(conversationId);
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
    int dbCount = 0;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM messages
      WHERE conversation_id = ? 
        AND UPPER(TRIM(sender_id)) != ? 
        AND status != ?
    ''', [conversationId, normalizedMyId, MessageStatus.read.name]);
    if (result.isNotEmpty) {
      dbCount = (result.first['cnt'] as int?) ?? 0;
    }

    int transientCount = 0;
    final transientList = _transientMessages[conversationId];
    if (transientList != null && transientList.isNotEmpty) {
      for (final tm in transientList) {
        if (tm.senderId.trim().toUpperCase() != normalizedMyId &&
            tm.status != MessageStatus.read) {
          transientCount++;
        }
      }
    }

    return dbCount + transientCount;
  }
}
