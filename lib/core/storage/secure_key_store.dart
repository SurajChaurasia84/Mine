import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/key_pair_bundle.dart';

/// Secure hardware-backed storage for the device's cryptographic identity keys.
/// Uses Android Keystore (EncryptedSharedPreferences) on Android.
/// Provides safe web fallback cache on Chrome/Desktop.
/// Private keys are never exposed to remote servers or plaintext databases.
class SecureKeyStore {
  final FlutterSecureStorage _storage;
  static const String _identityKey = 'mine_identity_bundle_v1';
  static final Map<String, String> _webSessionCache = {};

  KeyPairBundle? _cachedIdentity;

  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
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
    try {
      jsonStr = await _storage.read(key: _identityKey);
    } catch (_) {
      jsonStr = _webSessionCache[_identityKey];
    }

    if (jsonStr == null || jsonStr.isEmpty) {
      jsonStr = _webSessionCache[_identityKey];
    }

    if (jsonStr == null || jsonStr.isEmpty) return null;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      _cachedIdentity = KeyPairBundle.fromSecureJson(map);
      return _cachedIdentity;
    } catch (_) {
      return null;
    }
  }

  /// Saves the newly generated cryptographic identity bundle to secure storage
  Future<void> saveIdentity(KeyPairBundle identity) async {
    _cachedIdentity = identity;
    final jsonStr = jsonEncode(identity.toSecureJson());
    _webSessionCache[_identityKey] = jsonStr;
    try {
      await _storage.write(key: _identityKey, value: jsonStr);
    } catch (_) {}
  }

  /// Cryptographic identity wipe for complete app reset
  Future<void> clearIdentity() async {
    _cachedIdentity = null;
    _webSessionCache.remove(_identityKey);
    try {
      await _storage.delete(key: _identityKey);
    } catch (_) {}
  }
}
