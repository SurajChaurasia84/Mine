import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'app/app.dart';
import 'core/crypto/crypto_service.dart';
import 'core/storage/app_database.dart';
import 'core/storage/secure_key_store.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/contact_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop or test runner SQLite fallback
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Core Services
  final secureKeyStore = SecureKeyStore();
  final cryptoService = CryptoService();
  final appDatabase = AppDatabase();
  final contactRepository = ContactRepository(appDatabase: appDatabase);
  final chatRepository = ChatRepository(appDatabase: appDatabase);

  runApp(
    MineApp(
      secureKeyStore: secureKeyStore,
      cryptoService: cryptoService,
      appDatabase: appDatabase,
      contactRepository: contactRepository,
      chatRepository: chatRepository,
    ),
  );
}
