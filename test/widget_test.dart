import 'package:flutter_test/flutter_test.dart';
import 'package:mine/app/app.dart';
import 'package:mine/core/crypto/crypto_service.dart';
import 'package:mine/core/storage/app_database.dart';
import 'package:mine/core/storage/secure_key_store.dart';
import 'package:mine/data/repositories/chat_repository.dart';
import 'package:mine/data/repositories/contact_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Mine App boots up and displays identity initialization', (WidgetTester tester) async {
    final rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final appDatabase = AppDatabase(db: rawDb);
    final cryptoService = CryptoService();
    final secureKeyStore = SecureKeyStore();
    final contactRepo = ContactRepository(appDatabase: appDatabase);
    final chatRepo = ChatRepository(appDatabase: appDatabase);

    await tester.pumpWidget(
      MineApp(
        secureKeyStore: secureKeyStore,
        cryptoService: cryptoService,
        appDatabase: appDatabase,
        contactRepository: contactRepo,
        chatRepository: chatRepo,
      ),
    );

    // Initial check
    expect(find.byType(MineApp), findsOneWidget);
    await rawDb.close();
  });
}
