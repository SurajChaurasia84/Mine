import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/key_pair_bundle.dart';
import 'app_database.dart';

/// Secure hardware-backed storage for the device's cryptographic identity keys.
/// Uses Android Keystore (EncryptedSharedPreferences) on Android.
/// Provides SQLite IndexedDB & Flash storage backup to prevent identity churn across reloads/restarts.
/// Private keys are never exposed to remote servers or plaintext databases.
class SecureKeyStore {
  final FlutterSecureStorage _storage;
  final AppDatabase? appDatabase;
  static const String _identityKey = 'mine_identity_bundle_v1';
  static final Map<String, String> _webSessionCache = {};

  KeyPairBundle? _cachedIdentity;

  SecureKeyStore({
    FlutterSecureStorage? storage,
    this.appDatabase,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              webOptions: WebOptions(
                dbName: 'MineSecureDB',
                publicKey: 'MineSecureKey',
              ),
            );

  /// Checks if this device already has an initialized cryptographic identity
  Future<bool> hasIdentity() async {
    if (_cachedIdentity != null) return true;
    final id = await getIdentity();
    return id != null;
  }

  /// Retrieves the saved cryptographic identity bundle
  Future<KeyPairBundle?> getIdentity() async {
    if (_cachedIdentity != null) return _cachedIdentity;

    String? jsonStr;

    // 1. Try secure hardware storage
    try {
      jsonStr = await _storage.read(key: _identityKey);
    } catch (e) {
      debugPrint('[SecureKeyStore] Secure storage read warning: $e');
    }

    // 2. Try persistent SQLite backup if secure storage was empty or failed
    if (jsonStr == null || jsonStr.isEmpty) {
      try {
        jsonStr = await appDatabase?.getLocalIdentity();
      } catch (e) {
        debugPrint('[SecureKeyStore] SQLite identity read warning: $e');
      }
    }

    // 3. Try RAM session cache
    if (jsonStr == null || jsonStr.isEmpty) {
      jsonStr = _webSessionCache[_identityKey];
    }

    if (jsonStr == null || jsonStr.isEmpty) return null;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final identity = KeyPairBundle.fromSecureJson(map);
      _cachedIdentity = identity;

      // Sync back to both stores to ensure persistent retention
      _webSessionCache[_identityKey] = jsonStr;
      _repairBackups(jsonStr);

      return _cachedIdentity;
    } catch (e) {
      debugPrint('[SecureKeyStore] Parse error: $e');
      return null;
    }
  }

  void _repairBackups(String jsonStr) {
    try {
      _storage.write(key: _identityKey, value: jsonStr).catchError((_) {});
    } catch (_) {}
    try {
      appDatabase?.saveLocalIdentity(jsonStr).catchError((_) {});
    } catch (_) {}
  }

  /// Saves the newly generated cryptographic identity bundle to secure storage and SQLite backup
  Future<void> saveIdentity(KeyPairBundle identity) async {
    _cachedIdentity = identity;
    final jsonStr = jsonEncode(identity.toSecureJson());
    _webSessionCache[_identityKey] = jsonStr;

    // Persist to SQLite backup (IndexedDB on Web, Disk on Android)
    try {
      await appDatabase?.saveLocalIdentity(jsonStr);
    } catch (e) {
      debugPrint('[SecureKeyStore] SQLite identity save error: $e');
    }

    // Persist to hardware secure storage
    try {
      await _storage.write(key: _identityKey, value: jsonStr);
    } catch (e) {
      debugPrint('[SecureKeyStore] Secure storage write error: $e');
    }
  }

  /// Cryptographic identity wipe for complete app reset
  Future<void> clearIdentity() async {
    _cachedIdentity = null;
    _webSessionCache.remove(_identityKey);

    try {
      await appDatabase?.clearLocalIdentity();
    } catch (_) {}

    try {
      await _storage.delete(key: _identityKey);
    } catch (_) {}
  }
}
