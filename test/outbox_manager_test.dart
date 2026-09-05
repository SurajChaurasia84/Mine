import 'package:flutter_test/flutter_test.dart';
import 'package:mine/core/crypto/crypto_service.dart';
import 'package:mine/core/storage/app_database.dart';
import 'package:mine/data/models/message_model.dart';
import 'package:mine/data/repositories/chat_repository.dart';
import 'package:mine/data/repositories/contact_repository.dart';
import 'package:mine/services/connection_manager/connection_manager.dart';
import 'package:mine/services/signaling/signaling_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ConnectionManager & Outbox Tests', () {
    late Database rawDb;
    late AppDatabase appDatabase;
    late ContactRepository contactRepo;
    late ChatRepository chatRepo;
    late CryptoService cryptoService;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await rawDb.execute('PRAGMA foreign_keys = ON');

      // Setup tables
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
      cryptoService = CryptoService();
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('Queues message locally in outbox with pending status when peer is offline', () async {
      final alice = await cryptoService.generateIdentity();
      final bob = await cryptoService.generateIdentity();

      // Alice adds Bob as contact
      final bobContact = await contactRepo.addContact(
        peerDeviceId: bob.deviceId,
        peerIdentityPublicKey: bob.identityPublicKeyHex,
        peerDhPublicKey: bob.dhPublicKeyHex,
        nickname: 'Bob',
      );
      final conversation = await chatRepo.getOrCreateConversation(bobContact.id);

      final signalingClient = SignalingClient(deviceId: alice.deviceId, initialServerUrl: 'ws://127.0.0.1:9999');

      final connManager = ConnectionManager(
        myIdentity: alice,
        cryptoService: cryptoService,
        contactRepository: contactRepo,
        chatRepository: chatRepo,
        signalingClient: signalingClient,
      );

      // Send message while peer is offline
      final sentMsg = await connManager.sendMessage(
        contact: bobContact,
        conversation: conversation,
        text: 'Offline message for Bob',
      );

      expect(sentMsg.status, equals(MessageStatus.pending));

      // Verify message is saved strictly as ciphertext in DB
      final savedMessages = await chatRepo.getMessages(conversation.id);
      expect(savedMessages.length, equals(1));
      expect(savedMessages.first.ciphertext, isNot(contains('Offline message for Bob')));
      expect(savedMessages.first.status, equals(MessageStatus.pending));

      // Verify pending outbox returns this message
      final pendingList = await chatRepo.getPendingOutgoingMessages();
      expect(pendingList.length, equals(1));
      expect(pendingList.first.id, equals(sentMsg.id));

      connManager.dispose();
      signalingClient.dispose();
    });
  });
}
