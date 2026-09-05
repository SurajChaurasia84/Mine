import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/key_pair_bundle.dart';
import '../core/storage/app_database.dart';
import '../core/storage/secure_key_store.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/media/encrypted_media_service.dart';
import '../features/onboarding/identity_setup_screen.dart';
import '../services/connection_manager/connection_manager.dart';
import '../services/notification/privacy_notification_service.dart';
import '../services/signaling/signaling_client.dart';
import 'theme.dart';

class MineApp extends StatefulWidget {
  final SecureKeyStore secureKeyStore;
  final CryptoService cryptoService;
  final AppDatabase appDatabase;
  final ContactRepository contactRepository;
  final ChatRepository chatRepository;

  const MineApp({
    super.key,
    required this.secureKeyStore,
    required this.cryptoService,
    required this.appDatabase,
    required this.contactRepository,
    required this.chatRepository,
  });

  @override
  State<MineApp> createState() => _MineAppState();
}

class _MineAppState extends State<MineApp> {
  KeyPairBundle? _identity;
  bool _isCheckingIdentity = true;

  SignalingClient? _signalingClient;
  ConnectionManager? _connectionManager;

  @override
  void initState() {
    super.initState();
    _checkExistingIdentity();
  }

  Future<void> _checkExistingIdentity() async {
    KeyPairBundle? identity;
    try {
      identity = await widget.secureKeyStore.getIdentity();
      if (identity != null) {
        _setupServices(identity);
      }
    } catch (e) {
      debugPrint('[MineApp] Error checking identity: $e');
    } finally {
      if (mounted) {
        setState(() {
          _identity = identity;
          _isCheckingIdentity = false;
        });
      }
    }
  }

  void _setupServices(KeyPairBundle identity) {
    try {
      _signalingClient?.dispose();
      _connectionManager?.dispose();

      _signalingClient = SignalingClient(deviceId: identity.deviceId);
      _connectionManager = ConnectionManager(
        myIdentity: identity,
        cryptoService: widget.cryptoService,
        contactRepository: widget.contactRepository,
        chatRepository: widget.chatRepository,
        signalingClient: _signalingClient!,
      );
    } catch (e) {
      debugPrint('[MineApp] Error setting up services: $e');
    }
  }

  void _handleSetupComplete() async {
    try {
      final identity = await widget.secureKeyStore.getIdentity();
      if (identity != null) {
        _setupServices(identity);
        if (mounted) {
          setState(() {
            _identity = identity;
          });
        }
      }
    } catch (e) {
      debugPrint('[MineApp] Error completing setup: $e');
    }
  }

  @override
  void dispose() {
    _signalingClient?.dispose();
    _connectionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SecureKeyStore>.value(value: widget.secureKeyStore),
        Provider<CryptoService>.value(value: widget.cryptoService),
        Provider<AppDatabase>.value(value: widget.appDatabase),
        Provider<ContactRepository>.value(value: widget.contactRepository),
        Provider<ChatRepository>.value(value: widget.chatRepository),
        Provider<PrivacyNotificationService>(create: (_) => PrivacyNotificationService()),
        Provider<EncryptedMediaService>(
          create: (_) => EncryptedMediaService(cryptoService: widget.cryptoService),
        ),
        if (_signalingClient != null)
          Provider<SignalingClient>.value(value: _signalingClient!),
        if (_connectionManager != null)
          ChangeNotifierProvider<ConnectionManager>.value(value: _connectionManager!),
      ],
      child: MaterialApp(
        title: 'Mine',
        debugShowCheckedModeBanner: false,
        theme: MineTheme.darkTheme,
        home: _isCheckingIdentity
            ? const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: MineTheme.primaryTeal),
                ),
              )
            : _identity == null
                ? IdentitySetupScreen(
                    secureKeyStore: widget.secureKeyStore,
                    cryptoService: widget.cryptoService,
                    onSetupComplete: _handleSetupComplete,
                  )
                : ChatListScreen(identity: _identity!),
      ),
    );
  }
}
