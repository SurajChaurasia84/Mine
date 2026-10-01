import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/key_pair_bundle.dart';
import '../core/storage/app_database.dart';
import '../core/storage/secure_key_store.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../features/auth/app_lock_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/media/encrypted_media_service.dart';
import '../features/onboarding/identity_setup_screen.dart';
import '../features/chat/share_target_select_screen.dart';
import '../services/connection_manager/connection_manager.dart';
import '../services/media/incoming_share_service.dart';
import '../services/media/media_picker_helper.dart';
import '../services/notification/privacy_notification_service.dart';
import '../services/signaling/signaling_client.dart';
import 'theme.dart';

class MineApp extends StatefulWidget {
  final SecureKeyStore secureKeyStore;
  final CryptoService cryptoService;
  final AppDatabase appDatabase;
  final ContactRepository contactRepository;
  final ChatRepository chatRepository;
  final KeyPairBundle? initialIdentity;
  final String? initialDisplayName;
  final bool initialAppLockEnabled;
  final bool initialBiometricsEnabled;
  final bool initialDevicePinEnabled;

  const MineApp({
    super.key,
    required this.secureKeyStore,
    required this.cryptoService,
    required this.appDatabase,
    required this.contactRepository,
    required this.chatRepository,
    this.initialIdentity,
    this.initialDisplayName,
    this.initialAppLockEnabled = false,
    this.initialBiometricsEnabled = true,
    this.initialDevicePinEnabled = true,
  });

  @override
  State<MineApp> createState() => _MineAppState();
}

class _MineAppState extends State<MineApp> with WidgetsBindingObserver {
  KeyPairBundle? _identity;
  String? _displayName;
  bool _isCheckingIdentity = false;

  late bool _isAppLockEnabled;
  late bool _isLocked;
  late bool _allowBiometrics;
  late bool _allowDevicePin;
  List<MediaPreviewItem>? _pendingSharedMedia;

  SignalingClient? _signalingClient;
  ConnectionManager? _connectionManager;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAppLockEnabled = widget.initialAppLockEnabled;
    _isLocked = widget.initialAppLockEnabled;
    _allowBiometrics = widget.initialBiometricsEnabled;
    _allowDevicePin = widget.initialDevicePinEnabled;
    _checkAppLock();
    _displayName = widget.initialDisplayName;
    if (widget.initialIdentity != null) {
      _identity = widget.initialIdentity;
      _isCheckingIdentity = false;
      _setupServices(widget.initialIdentity!);
    } else {
      _isCheckingIdentity = true;
      _checkExistingIdentity();
    }

    IncomingShareService.listen(
      onMediaReceived: _handleIncomingSharedMedia,
    );
  }

  Future<void> _checkAppLock() async {
    final enabled = await widget.secureKeyStore.isAppLockEnabled();
    final bio = await widget.secureKeyStore.isBiometricsEnabled();
    final pin = await widget.secureKeyStore.isDevicePinEnabled();
    if (mounted) {
      setState(() {
        _isAppLockEnabled = enabled;
        _allowBiometrics = bio;
        _allowDevicePin = pin;
        // Keep locked if enabled
        if (enabled && widget.initialAppLockEnabled) {
          _isLocked = true;
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      final enabled = await widget.secureKeyStore.isAppLockEnabled();
      if (enabled && mounted) {
        setState(() {
          _isAppLockEnabled = true;
          _isLocked = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      final enabled = await widget.secureKeyStore.isAppLockEnabled();
      final bio = await widget.secureKeyStore.isBiometricsEnabled();
      final pin = await widget.secureKeyStore.isDevicePinEnabled();
      if (mounted) {
        setState(() {
          _isAppLockEnabled = enabled;
          _allowBiometrics = bio;
          _allowDevicePin = pin;
        });
      }
    }
  }

  void _handleIncomingSharedMedia(List<MediaPreviewItem> items) async {
    if (items.isEmpty) return;
    if (_identity == null) {
      debugPrint('[MineApp] User has not set up identity yet, ignoring shared media.');
      return;
    }

    final isLockEnabled = _isAppLockEnabled || await widget.secureKeyStore.isAppLockEnabled();
    if (isLockEnabled && _isLocked) {
      // Store pending items so they open upon unlock from AppLockScreen
      _pendingSharedMedia = items;
      return;
    }

    _openShareTargetScreen(items);
  }

  void _openShareTargetScreen(List<MediaPreviewItem> items) {
    void push() {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ShareTargetSelectScreen(
            sharedMediaItems: items,
          ),
        ),
      );
    }

    if (_navigatorKey.currentState != null) {
      push();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        push();
      });
    }
  }

  Future<void> _checkExistingIdentity() async {
    KeyPairBundle? identity;
    String? name;
    try {
      identity = await widget.secureKeyStore.getIdentity();
      name = await widget.secureKeyStore.getDisplayName();
      if (identity != null) {
        _displayName = name;
        _setupServices(identity);
      }
    } catch (e) {
      debugPrint('[MineApp] Error checking identity: $e');
    } finally {
      if (mounted) {
        setState(() {
          _identity = identity;
          _displayName = name;
          _isCheckingIdentity = false;
        });
      }
    }
  }

  void _setupServices(KeyPairBundle identity) {
    try {
      _signalingClient?.dispose();
      _connectionManager?.dispose();

      _signalingClient = SignalingClient(
        deviceId: identity.deviceId,
        identityPublicKeyHex: identity.identityPublicKeyHex,
        dhPublicKeyHex: identity.dhPublicKeyHex,
      );
      _connectionManager = ConnectionManager(
        myIdentity: identity,
        cryptoService: widget.cryptoService,
        contactRepository: widget.contactRepository,
        chatRepository: widget.chatRepository,
        signalingClient: _signalingClient!,
        secureKeyStore: widget.secureKeyStore,
        initialDisplayName: _displayName,
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
    WidgetsBinding.instance.removeObserver(this);
    IncomingShareService.dispose();
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
          ChangeNotifierProvider<SignalingClient>.value(value: _signalingClient!),
        if (_connectionManager != null)
          ChangeNotifierProvider<ConnectionManager>.value(value: _connectionManager!),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Mine',
        debugShowCheckedModeBanner: false,
        theme: MineTheme.darkTheme,
        builder: (context, child) {
          return Stack(
            children: [
              ?child,
              if (_isLocked && _isAppLockEnabled)
                Positioned.fill(
                  child: AppLockScreen(
                    allowBiometrics: _allowBiometrics,
                    allowDevicePin: _allowDevicePin,
                    onUnlocked: () {
                      setState(() {
                        _isLocked = false;
                      });
                      if (_pendingSharedMedia != null && _pendingSharedMedia!.isNotEmpty) {
                        final media = _pendingSharedMedia!;
                        _pendingSharedMedia = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _openShareTargetScreen(media);
                        });
                      }
                    },
                  ),
                ),
            ],
          );
        },
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
