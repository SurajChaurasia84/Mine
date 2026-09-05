import 'dart:convert';

/// Represents the cryptographic identity bundle of a user/device.
/// Includes:
/// - deviceId: Random non-personal ID (e.g. X7K4-P9QM-82LA)
/// - identityPublicKeyHex: Ed25519 public key (hex) for signing and authentication
/// - identityPrivateKeyHex: Ed25519 private key (hex) - NEVER transmitted
/// - dhPublicKeyHex: X25519 public key (hex) for Diffie-Hellman key exchange
/// - dhPrivateKeyHex: X25519 private key (hex) - NEVER transmitted
class KeyPairBundle {
  final String deviceId;
  final String identityPublicKeyHex;
  final String identityPrivateKeyHex;
  final String dhPublicKeyHex;
  final String dhPrivateKeyHex;

  KeyPairBundle({
    required this.deviceId,
    required this.identityPublicKeyHex,
    required this.identityPrivateKeyHex,
    required this.dhPublicKeyHex,
    required this.dhPrivateKeyHex,
  });

  Map<String, dynamic> toSecureJson() {
    return {
      'deviceId': deviceId,
      'identityPublicKeyHex': identityPublicKeyHex,
      'identityPrivateKeyHex': identityPrivateKeyHex,
      'dhPublicKeyHex': dhPublicKeyHex,
      'dhPrivateKeyHex': dhPrivateKeyHex,
    };
  }

  factory KeyPairBundle.fromSecureJson(Map<String, dynamic> json) {
    return KeyPairBundle(
      deviceId: json['deviceId'] as String,
      identityPublicKeyHex: json['identityPublicKeyHex'] as String,
      identityPrivateKeyHex: json['identityPrivateKeyHex'] as String,
      dhPublicKeyHex: json['dhPublicKeyHex'] as String,
      dhPrivateKeyHex: json['dhPrivateKeyHex'] as String,
    );
  }

  /// Encodes only the PUBLIC details for pairing (QR code / Invite Code)
  /// NEVER includes any private key.
  String toPublicInvitePayload() {
    final map = {
      'v': 1,
      'id': deviceId,
      'ik': identityPublicKeyHex,
      'dh': dhPublicKeyHex,
    };
    final jsonStr = jsonEncode(map);
    return base64Url.encode(utf8.encode(jsonStr));
  }

  /// Parses a public invite code or QR payload
  static Map<String, String>? parseInvitePayload(String rawCode) {
    try {
      String clean = rawCode.trim();
      if (clean.startsWith('mine://invite?p=')) {
        clean = clean.substring('mine://invite?p='.length);
      }
      // Add padding if missing
      clean = base64Url.normalize(clean);
      final decoded = utf8.decode(base64Url.decode(clean));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      if (map.containsKey('id') && map.containsKey('ik') && map.containsKey('dh')) {
        return {
          'deviceId': map['id'] as String,
          'identityPublicKey': map['ik'] as String,
          'dhPublicKey': map['dh'] as String,
        };
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
