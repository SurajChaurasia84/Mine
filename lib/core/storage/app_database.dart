import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Manages local SQLite storage for contacts, conversations, messages, and attachments.
/// All message contents are stored strictly as ciphertext.
class AppDatabase {
  static const String _dbName = 'mine_secure_messenger.db';
  static const int _dbVersion = 1;

  final Database? db;
  Database? _internalDb;

  AppDatabase({this.db});

  Future<Database> get database async {
    if (db != null) return db!;
    if (_internalDb != null) return _internalDb!;
    _internalDb = await _initDatabase();
    return _internalDb!;
  }

  Future<Database> _initDatabase() async {
    if (kIsWeb) {
      return await databaseFactory.openDatabase(
        _dbName,
        options: OpenDatabaseOptions(
          version: _dbVersion,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await _createTables(db);
          },
        ),
      );
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  static Future<void> _createTables(DatabaseExecutor db) async {
    // 1. Contacts table
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        peer_device_id TEXT NOT NULL,
        peer_identity_public_key TEXT NOT NULL,
        peer_dh_public_key TEXT NOT NULL,
        nickname TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 2. Conversations table
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_message_at TEXT,
        FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
      )
    ''');

    // 3. Messages table (storing strictly ciphertext)
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        ciphertext TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        message_type TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');

    // 4. Attachments table
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        encrypted_local_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        file_name TEXT,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');

    // Indices for high performance chat queries
    await db.execute('CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp DESC)');
    await db.execute('CREATE INDEX idx_conversations_contact ON conversations(contact_id)');
  }

  /// Complete local data purge
  Future<void> wipeDatabase() async {
    final db = await database;
    await db.delete('attachments');
    await db.delete('messages');
    await db.delete('conversations');
    await db.delete('contacts');
  }

  Future<void> close() async {
    if (_internalDb != null && _internalDb!.isOpen) {
      await _internalDb!.close();
      _internalDb = null;
    }
  }
}
