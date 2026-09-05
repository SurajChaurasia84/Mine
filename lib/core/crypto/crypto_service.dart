import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../utils/id_generator.dart';
import 'key_pair_bundle.dart';

/// Cryptographic service providing End-to-End Encryption (E2EE)
/// using vetted standard algorithms:
/// - Ed25519: Identity signatures and peer authentication
/// - X25519: Diffie-Hellman key exchange
/// - HKDF (SHA-256): Session key derivation
/// - AES-256-GCM: Symmetric message and media encryption with 96-bit nonce and 128-bit auth tag
class CryptoService {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  /// Generates a new cryptographic identity bundle for first launch
  Future<KeyPairBundle> generateIdentity() async {
    final deviceId = IdGenerator.generateDeviceId();

    // 1. Generate Ed25519 identity keypair
    final identityKeyPair = await _ed25519.newKeyPair();
    final identityPublicKey = await identityKeyPair.extractPublicKey();
    final identityPrivateKeyBytes = await identityKeyPair.extractPrivateKeyBytes();

    // 2. Generate X25519 Diffie-Hellman keypair
    final dhKeyPair = await _x25519.newKeyPair();
    final dhPublicKey = await dhKeyPair.extractPublicKey();
    final dhPrivateKeyBytes = await dhKeyPair.extractPrivateKeyBytes();

    return KeyPairBundle(
      deviceId: deviceId,
      identityPublicKeyHex: _bytesToHex(Uint8List.fromList(identityPublicKey.bytes)),
      identityPrivateKeyHex: _bytesToHex(Uint8List.fromList(identityPrivateKeyBytes)),
      dhPublicKeyHex: _bytesToHex(Uint8List.fromList(dhPublicKey.bytes)),
      dhPrivateKeyHex: _bytesToHex(Uint8List.fromList(dhPrivateKeyBytes)),
    );
  }

  /// Derives an end-to-end symmetric session key (AES-256) between my DH private key
  /// and the peer's DH public key using X25519 + HKDF-SHA256.
  Future<List<int>> deriveSessionKey({
    required String myDhPrivateKeyHex,
    required String peerDhPublicKeyHex,
    String contextInfo = 'Mine_Messenger_Session_v1',
  }) async {
    final myPrivBytes = _hexToBytes(myDhPrivateKeyHex);
    final peerPubBytes = _hexToBytes(peerDhPublicKeyHex);

    final myKeyPair = await _x25519.newKeyPairFromSeed(myPrivBytes);
    final peerPublicKey = SimplePublicKey(peerPubBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    // Run HKDF to derive a 256-bit symmetric session key
    final derivedSecret = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode(contextInfo),
    );

    return await derivedSecret.extractBytes();
  }

  /// Encrypts plaintext using AES-256-GCM.
  /// Returns a JSON string containing base64url encoded:
  /// - nonce (12 bytes)
  /// - ciphertext
  /// - mac (16 bytes auth tag)
  Future<String> encryptMessage({
    required String plaintext,
    required List<int> sessionKeyBytes,
  }) async {
    final secretKey = SecretKey(sessionKeyBytes);
    final plaintextBytes = utf8.encode(plaintext);

    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
    );

    final payload = {
      'n': base64Url.encode(secretBox.nonce),
      'c': base64Url.encode(secretBox.cipherText),
      'm': base64Url.encode(secretBox.mac.bytes),
    };

    return jsonEncode(payload);
  }

  /// Decrypts AES-256-GCM payload and validates authentication tag.
  /// Throws an exception if the message was tampered with or if the key is incorrect.
  Future<String> decryptMessage({
    required String encryptedJson,
    required List<int> sessionKeyBytes,
  }) async {
    final map = jsonDecode(encryptedJson) as Map<String, dynamic>;
    final nonce = base64Url.decode(map['n'] as String);
    final cipherText = base64Url.decode(map['c'] as String);
    final macBytes = base64Url.decode(map['m'] as String);

    final secretKey = SecretKey(sessionKeyBytes);
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decryptedBytes);
  }

  /// Encrypts raw binary media (images, files) using AES-256-GCM
  Future<Uint8List> encryptBytes({
    required Uint8List rawBytes,
    required List<int> sessionKeyBytes,
  }) async {
    final secretKey = SecretKey(sessionKeyBytes);
    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: secretKey,
    );

    // Pack into binary: [1 byte nonce length][nonce][2 bytes mac length][mac][ciphertext]
    final builder = BytesBuilder();
    builder.addByte(secretBox.nonce.length);
    builder.add(secretBox.nonce);
    builder.addByte(secretBox.mac.bytes.length);
    builder.add(secretBox.mac.bytes);
    builder.add(secretBox.cipherText);

    return builder.toBytes();
  }

  /// Decrypts raw binary media
  Future<Uint8List> decryptBytes({
    required Uint8List encryptedData,
    required List<int> sessionKeyBytes,
  }) async {
    int offset = 0;
    final nonceLength = encryptedData[offset++];
    final nonce = encryptedData.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    final macLength = encryptedData[offset++];
    final macBytes = encryptedData.sublist(offset, offset + macLength);
    offset += macLength;

    final cipherText = encryptedData.sublist(offset);

    final secretKey = SecretKey(sessionKeyBytes);
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decrypted = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }

  // --- Utilities ---
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
