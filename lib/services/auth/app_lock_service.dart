import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class AppLockService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if the device has biometric or screen lock hardware/support available
  static Future<bool> isDeviceSupported() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] isDeviceSupported error: $e');
      return false;
    }
  }

  /// Check specifically for registered biometrics (Fingerprint / Face)
  static Future<bool> hasBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final List<BiometricType> available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] hasBiometrics error: $e');
      return false;
    }
  }

  /// Authenticate using registered Fingerprint/Biometrics, Device PIN/Pattern, or both.
  static Future<bool> authenticate({
    bool allowBiometrics = true,
    bool allowDeviceCredentials = true,
    String reason = 'Unlock Mine',
  }) async {
    try {
      final bool supported = await isDeviceSupported();
      if (!supported) {
        // If device has no screen lock or hardware at all, allow passage
        return true;
      }

      // If user turned off device credentials, restrict to biometrics only
      final bool biometricOnly = !allowDeviceCredentials;
      final String headerTitle = reason.isNotEmpty ? reason : 'Unlock Mine';

      return await _auth.authenticate(
        localizedReason: headerTitle,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: headerTitle,
            signInHint: '',
            cancelButton: 'Cancel',
          ),
        ],
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: false,
      );
    } on PlatformException catch (e) {
      debugPrint('[AppLockService] authenticate error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[AppLockService] unexpected error: $e');
      return false;
    }
  }

  /// Cancels any active authentication dialog
  static Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
