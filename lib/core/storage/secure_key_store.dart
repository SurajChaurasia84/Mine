import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/key_pair_bundle.dart';

/// Secure hardware-backed storage for the device's cryptographic identity keys.
/// Uses Android Keystore (EncryptedSharedPreferences) on Android.
/// Private keys are never exposed to remote servers or plaintext databases.
class SecureKeyStore {
  final FlutterSecureStorage _storage;
  static const String _identityKey = 'mine_identity_bundle_v1';

  KeyPairBundle? _cachedIdentity;

  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  /// Checks if this device already has an initialized cryptographic identity
  Future<bool> hasIdentity() async {
    if (_cachedIdentity != null) return true;
    final jsonStr = await _storage.read(key: _identityKey);
    return jsonStr != null && jsonStr.isNotEmpty;
  }

  /// Retrieves the saved cryptographic identity bundle
  Future<KeyPairBundle?> getIdentity() async {
    if (_cachedIdentity != null) return _cachedIdentity;
    final jsonStr = await _storage.read(key: _identityKey);
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
    await _storage.write(key: _identityKey, value: jsonStr);
  }

  /// Cryptographic identity wipe for complete app reset
  Future<void> clearIdentity() async {
    _cachedIdentity = null;
    await _storage.delete(key: _identityKey);
  }
}
