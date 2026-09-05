import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/storage/app_database.dart';
import '../models/contact_model.dart';

class ContactRepository {
  final AppDatabase appDatabase;
  final Uuid _uuid = const Uuid();

  ContactRepository({required this.appDatabase});

  /// Creates and persists a newly paired contact.
  /// Generates a local record linking the peer's public identity and DH keys with a local nickname.
  Future<ContactModel> addContact({
    required String peerDeviceId,
    required String peerIdentityPublicKey,
    required String peerDhPublicKey,
    required String nickname,
  }) async {
    final db = await appDatabase.database;
    final now = DateTime.now();
    final contact = ContactModel(
      id: _uuid.v4(),
      peerDeviceId: peerDeviceId,
      peerIdentityPublicKey: peerIdentityPublicKey,
      peerDhPublicKey: peerDhPublicKey,
      nickname: nickname.trim().isEmpty ? 'Contact ($peerDeviceId)' : nickname.trim(),
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return contact;
  }

  /// Updates only the local human-readable nickname for a contact.
  /// CRUCIAL: The cryptographic identity remains completely untouched.
  Future<void> updateNickname({
    required String contactId,
    required String newNickname,
  }) async {
    final db = await appDatabase.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'contacts',
      {
        'nickname': newNickname.trim(),
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  /// Retrieves all contacts sorted by nickname
  Future<List<ContactModel>> getContacts() async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'contacts',
      orderBy: 'nickname COLLATE NOCASE ASC',
    );
    return maps.map((m) => ContactModel.fromMap(m)).toList();
  }

  /// Retrieves a contact by ID
  Future<ContactModel?> getContactById(String id) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ContactModel.fromMap(maps.first);
  }

  /// Finds an existing contact by peer device ID
  Future<ContactModel?> findByPeerDeviceId(String peerDeviceId) async {
    final db = await appDatabase.database;
    final maps = await db.query(
      'contacts',
      where: 'peer_device_id = ?',
      whereArgs: [peerDeviceId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ContactModel.fromMap(maps.first);
  }

  /// Deletes a contact and cascades to all its conversations and messages
  Future<void> deleteContact(String contactId) async {
    final db = await appDatabase.database;
    await db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }
}
