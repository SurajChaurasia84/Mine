import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/crypto/crypto_service.dart';

class EncryptedMediaService {
  final CryptoService _cryptoService;

  EncryptedMediaService({required CryptoService cryptoService})
      : _cryptoService = cryptoService;

  /// Encrypts media bytes and saves ciphertext directly to local app storage
  Future<String> saveAndEncryptMedia({
    required Uint8List rawBytes,
    required List<int> sessionKeyBytes,
    required String fileExtension,
  }) async {
    final encryptedData = await _cryptoService.encryptBytes(
      rawBytes: rawBytes,
      sessionKeyBytes: sessionKeyBytes,
    );

    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'encrypted_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final filename = 'enc_${DateTime.now().millisecondsSinceEpoch}.$fileExtension.bin';
    final filePath = p.join(mediaDir.path, filename);
    final file = File(filePath);
    await file.writeAsBytes(encryptedData);

    return filePath;
  }

  /// Decrypts locally stored encrypted media bytes into memory for display
  Future<Uint8List> loadAndDecryptMedia({
    required String encryptedFilePath,
    required List<int> sessionKeyBytes,
  }) async {
    final file = File(encryptedFilePath);
    if (!await file.exists()) {
      throw FileSystemException('Encrypted media file not found', encryptedFilePath);
    }

    final encryptedBytes = await file.readAsBytes();
    return await _cryptoService.decryptBytes(
      encryptedData: encryptedBytes,
      sessionKeyBytes: sessionKeyBytes,
    );
  }

  /// Cryptographic deletion: securely deletes local encrypted media file
  Future<void> deleteMediaFile(String encryptedFilePath) async {
    final file = File(encryptedFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
