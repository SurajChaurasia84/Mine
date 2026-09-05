import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mine/core/storage/app_database.dart';
import 'package:mine/data/models/message_model.dart';
import 'package:mine/data/repositories/contact_repository.dart';
import 'package:mine/data/repositories/chat_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database & Repository Tests', () {
    late Database rawDb;
    late AppDatabase appDatabase;
    late ContactRepository contactRepo;
    late ChatRepository chatRepo;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await rawDb.execute('PRAGMA foreign_keys = ON');

      // Create schema
      await rawDb.execute('''
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
      await rawDb.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          contact_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_message_at TEXT,
          FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
        )
      ''');
      await rawDb.execute('''
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
      await rawDb.execute('''
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

      appDatabase = AppDatabase(db: rawDb);
      contactRepo = ContactRepository(appDatabase: appDatabase);
      chatRepo = ChatRepository(appDatabase: appDatabase);
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('Nickname change alters ONLY local display name without affecting cryptographic identity', () async {
      const deviceId = 'X7K4-P9QM-82LA';
      const identityPub = 'aabbcc112233';
      const dhPub = 'ddeeff445566';

      // 1. Add contact "Rahul"
      final contact = await contactRepo.addContact(
        peerDeviceId: deviceId,
        peerIdentityPublicKey: identityPub,
        peerDhPublicKey: dhPub,
        nickname: 'Rahul',
      );

      expect(contact.nickname, equals('Rahul'));
      expect(contact.peerDeviceId, equals(deviceId));
      expect(contact.peerIdentityPublicKey, equals(identityPub));
      expect(contact.peerDhPublicKey, equals(dhPub));

      // 2. Rename contact to "Rohit"
      await contactRepo.updateNickname(contactId: contact.id, newNickname: 'Rohit');

      final updated = await contactRepo.getContactById(contact.id);
      expect(updated, isNotNull);
      expect(updated!.nickname, equals('Rohit'));
      // Cryptographic identity must remain 100% identical!
      expect(updated.peerDeviceId, equals(deviceId));
      expect(updated.peerIdentityPublicKey, equals(identityPub));
      expect(updated.peerDhPublicKey, equals(dhPub));
    });

    test('Encrypted message outbox management and cascade deletion', () async {
      final contact = await contactRepo.addContact(
        peerDeviceId: 'PEER-001',
        peerIdentityPublicKey: 'key1',
        peerDhPublicKey: 'dh1',
        nickname: 'Amit',
      );

      final conversation = await chatRepo.getOrCreateConversation(contact.id);
      expect(conversation.id, isNotEmpty);

      // Save pending ciphertext message
      final msg = MessageModel(
        id: 'msg-001',
        conversationId: conversation.id,
        senderId: 'my-device-id',
        ciphertext: '{"n":"nonce","c":"ciphertext","m":"tag"}',
        timestamp: DateTime.now(),
        status: MessageStatus.pending,
        messageType: MessageType.text,
      );
      await chatRepo.saveMessage(msg);

      // Verify outbox returns pending message
      final pendingList = await chatRepo.getPendingOutgoingMessages();
      expect(pendingList.length, equals(1));
      expect(pendingList.first.id, equals('msg-001'));
      expect(pendingList.first.status, equals(MessageStatus.pending));

      // Update status to delivered
      await chatRepo.updateMessageStatus('msg-001', MessageStatus.delivered);
      final deliveredList = await chatRepo.getPendingOutgoingMessages();
      expect(deliveredList.isEmpty, isTrue);

      final messages = await chatRepo.getMessages(conversation.id);
      expect(messages.first.status, equals(MessageStatus.delivered));

      // Delete contact -> verify cascade deletes conversation and messages
      await contactRepo.deleteContact(contact.id);
      final remainingMsgs = await chatRepo.getMessages(conversation.id);
      expect(remainingMsgs.isEmpty, isTrue);
    });
  });
}
