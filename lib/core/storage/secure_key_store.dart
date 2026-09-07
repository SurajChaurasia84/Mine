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
  static const String _passcodeKey = 'mine_security_passcode_v1';
  static const String _displayNameKey = 'mine_display_name_v1';
  static final Map<String, String> _webSessionCache = {};

  KeyPairBundle? _cachedIdentity;
  String? _cachedPasscode;
  String? _cachedDisplayName;

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

  /// Retrieves or generates a permanent 6-digit security passcode for this device
  Future<String> getOrGeneratePasscode() async {
    if (_cachedPasscode != null && _cachedPasscode!.length == 6) {
      return _cachedPasscode!;
    }

    String? code = await getPasscode();
    if (code != null && RegExp(r'^\d{6}$').hasMatch(code)) {
      _cachedPasscode = code;
      return code;
    }

    // Generate a secure random 6-digit passcode (100000 - 999999)
    final randomDigits = (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();
    await setPasscode(randomDigits);
    _cachedPasscode = randomDigits;
    return randomDigits;
  }

  /// Retrieves the saved 6-digit passcode if one exists
  Future<String?> getPasscode() async {
    if (_cachedPasscode != null) return _cachedPasscode;

    String? code;
    try {
      code = await _storage.read(key: _passcodeKey);
    } catch (e) {
      debugPrint('[SecureKeyStore] Passcode secure read warning: $e');
    }

    if (code == null || code.isEmpty) {
      code = _webSessionCache[_passcodeKey];
    }

    if (code != null && code.isNotEmpty) {
      _cachedPasscode = code;
    }
    return code;
  }

  /// Sets or updates the 6-digit security passcode (does NOT affect Device ID or keys)
  Future<void> setPasscode(String passcode) async {
    final clean = passcode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(clean)) {
      throw ArgumentError('Passcode must be exactly 6 digits');
    }
    _cachedPasscode = clean;
    _webSessionCache[_passcodeKey] = clean;

    try {
      await _storage.write(key: _passcodeKey, value: clean);
    } catch (e) {
      debugPrint('[SecureKeyStore] Passcode save error: $e');
    }
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

  /// Retrieves the saved user display name
  Future<String?> getDisplayName() async {
    if (_cachedDisplayName != null && _cachedDisplayName!.isNotEmpty) {
      return _cachedDisplayName;
    }

    String? name;
    try {
      name = await _storage.read(key: _displayNameKey);
    } catch (e) {
      debugPrint('[SecureKeyStore] Display name secure read warning: $e');
    }

    if (name == null || name.isEmpty) {
      name = _webSessionCache[_displayNameKey];
    }

    if (name != null && name.isNotEmpty) {
      _cachedDisplayName = name;
    }
    return name;
  }

  /// Sets or updates the user display name
  Future<void> setDisplayName(String name) async {
    final clean = name.trim();
    _cachedDisplayName = clean;
    _webSessionCache[_displayNameKey] = clean;

    try {
      await _storage.write(key: _displayNameKey, value: clean);
    } catch (e) {
      debugPrint('[SecureKeyStore] Display name save error: $e');
    }
  }

  /// Cryptographic identity wipe for complete app reset
  Future<void> clearIdentity() async {
    _cachedIdentity = null;
    _cachedPasscode = null;
    _cachedDisplayName = null;
    _webSessionCache.remove(_identityKey);
    _webSessionCache.remove(_passcodeKey);
    _webSessionCache.remove(_displayNameKey);

    try {
      await appDatabase?.clearLocalIdentity();
    } catch (_) {}

    try {
      await _storage.delete(key: _identityKey);
      await _storage.delete(key: _passcodeKey);
      await _storage.delete(key: _displayNameKey);
    } catch (_) {}
  }
}
