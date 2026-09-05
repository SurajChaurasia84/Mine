import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine/core/crypto/crypto_service.dart';
import 'package:mine/core/crypto/key_pair_bundle.dart';

void main() {
  group('CryptoService E2EE Tests', () {
    late CryptoService crypto;

    setUp(() {
      crypto = CryptoService();
    });

    test('Generates valid cryptographic identity bundle', () async {
      final identity = await crypto.generateIdentity();
      expect(identity.deviceId, isNotEmpty);
      expect(identity.identityPublicKeyHex, isNotEmpty);
      expect(identity.identityPrivateKeyHex, isNotEmpty);
      expect(identity.dhPublicKeyHex, isNotEmpty);
      expect(identity.dhPrivateKeyHex, isNotEmpty);
    });

    test('Performs X25519 ECDH key agreement and AES-256-GCM encryption/decryption between Alice and Bob', () async {
      // 1. Generate identity for Alice and Bob
      final alice = await crypto.generateIdentity();
      final bob = await crypto.generateIdentity();

      // 2. Alice computes shared session key with Bob's public DH key
      final aliceSessionKey = await crypto.deriveSessionKey(
        myDhPrivateKeyHex: alice.dhPrivateKeyHex,
        peerDhPublicKeyHex: bob.dhPublicKeyHex,
      );

      // 3. Bob computes shared session key with Alice's public DH key
      final bobSessionKey = await crypto.deriveSessionKey(
        myDhPrivateKeyHex: bob.dhPrivateKeyHex,
        peerDhPublicKeyHex: alice.dhPublicKeyHex,
      );

      // Both derived session keys must be identical
      expect(aliceSessionKey, equals(bobSessionKey));

      // 4. Alice encrypts message for Bob
      const originalMessage = "Hello Bob, this is private end-to-end encrypted!";
      final ciphertext = await crypto.encryptMessage(
        plaintext: originalMessage,
        sessionKeyBytes: aliceSessionKey,
      );

      expect(ciphertext, isNot(contains(originalMessage)));

      // 5. Bob decrypts message using his session key
      final decrypted = await crypto.decryptMessage(
        encryptedJson: ciphertext,
        sessionKeyBytes: bobSessionKey,
      );

      expect(decrypted, equals(originalMessage));
    });

    test('Detects ciphertext tampering and fails decryption', () async {
      final alice = await crypto.generateIdentity();
      final bob = await crypto.generateIdentity();

      final sessionKey = await crypto.deriveSessionKey(
        myDhPrivateKeyHex: alice.dhPrivateKeyHex,
        peerDhPublicKeyHex: bob.dhPublicKeyHex,
      );

      final ciphertext = await crypto.encryptMessage(
        plaintext: "Secret message",
        sessionKeyBytes: sessionKey,
      );

      // Tamper directly with the ciphertext bytes
      final map = jsonDecode(ciphertext) as Map<String, dynamic>;
      final rawC = base64Url.decode(map['c'] as String);
      rawC[0] ^= 0xFF;
      map['c'] = base64Url.encode(rawC);
      final tampered = jsonEncode(map);

      expect(
        () => crypto.decryptMessage(
          encryptedJson: tampered,
          sessionKeyBytes: sessionKey,
        ),
        throwsA(anything),
      );
    });

    test('Public invite payload parses accurately and protects private keys', () async {
      final alice = await crypto.generateIdentity();
      final invitePayload = alice.toPublicInvitePayload();

      final parsed = KeyPairBundle.parseInvitePayload(invitePayload);
      expect(parsed, isNotNull);
      expect(parsed!['deviceId'], equals(alice.deviceId));
      expect(parsed['identityPublicKey'], equals(alice.identityPublicKeyHex));
      expect(parsed['dhPublicKey'], equals(alice.dhPublicKeyHex));

      // Verify payload DOES NOT contain private keys
      expect(invitePayload, isNot(contains(alice.identityPrivateKeyHex)));
      expect(invitePayload, isNot(contains(alice.dhPrivateKeyHex)));
    });
  });
}
