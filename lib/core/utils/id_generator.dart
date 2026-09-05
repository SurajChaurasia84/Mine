import 'dart:math';

/// Generates non-personal random identifiers and cryptographic fingerprints.
class IdGenerator {
  static final Random _random = Random.secure();
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude ambiguous chars 0, O, 1, I

  /// Generates a human-friendly random device ID like: X7K4-P9QM-82LA
  static String generateDeviceId() {
    return '${_randomChunk(4)}-${_randomChunk(4)}-${_randomChunk(4)}';
  }

  static String _randomChunk(int length) {
    return List.generate(length, (_) => _chars[_random.nextInt(_chars.length)]).join();
  }

  /// Truncates or formats a public key fingerprint for subtle display
  static String formatFingerprint(String keyHex) {
    if (keyHex.length <= 16) return keyHex;
    final start = keyHex.substring(0, 4);
    final mid = keyHex.substring(keyHex.length ~/ 2 - 2, keyHex.length ~/ 2 + 2);
    final end = keyHex.substring(keyHex.length - 4);
    return '$start-$mid-$end'.toUpperCase();
  }
}
