import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

class EphemeralMediaPayload {
  final String mediaType; // 'photo' | 'video'
  final String url;
  final String mediaKeyBase64;
  final int size;
  final String? inlineCiphertext; // Optional fallback for fast local/offline delivery
  final String? caption;

  EphemeralMediaPayload({
    required this.mediaType,
    required this.url,
    required this.mediaKeyBase64,
    required this.size,
    this.inlineCiphertext,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': 'ephemeral_media',
      'media_type': mediaType,
      'url': url,
      'key': mediaKeyBase64,
      'size': size,
      if (inlineCiphertext != null) 'data': inlineCiphertext,
      if (caption != null && caption!.isNotEmpty) 'caption': caption,
    };
  }

  factory EphemeralMediaPayload.fromMap(Map<String, dynamic> map) {
    return EphemeralMediaPayload(
      mediaType: map['media_type'] as String? ?? 'photo',
      url: map['url'] as String? ?? '',
      mediaKeyBase64: map['key'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      inlineCiphertext: map['data'] as String?,
      caption: map['caption'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  static EphemeralMediaPayload? tryParse(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr);
      if (map is Map<String, dynamic> && map['type'] == 'ephemeral_media') {
        return EphemeralMediaPayload.fromMap(map);
      }
    } catch (_) {}
    return null;
  }
}

class EphemeralMediaService {
  final AesGcm _aesGcm = AesGcm.with256bits();

  /// Generates a cryptographically secure 256-bit symmetric media key
  List<int> generateMediaKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  /// Encrypts raw in-memory bytes with AES-256-GCM and uploads ciphertext blob
  Future<EphemeralMediaPayload> encryptAndUpload({
    required Uint8List rawBytes,
    required String mediaType, // 'photo' or 'video'
    String? caption,
  }) async {
    final keyBytes = generateMediaKey();
    final secretKey = SecretKey(keyBytes);

    // 1. Encrypt with AES-GCM
    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: secretKey,
    );

    // Pack into binary format: [1 byte nonce length][nonce][2 bytes mac length][mac][ciphertext]
    final builder = BytesBuilder();
    builder.addByte(secretBox.nonce.length);
    builder.add(secretBox.nonce);
    builder.addByte(secretBox.mac.bytes.length);
    builder.add(secretBox.mac.bytes);
    builder.add(secretBox.cipherText);
    final encryptedBlob = builder.toBytes();

    final keyBase64 = base64.encode(keyBytes);

    // For media <= 3.5 MB (standard photos and compressed videos), always embed inline
    // ciphertext directly in the E2EE envelope for 100% reliable zero-dependency delivery.
    String blobUrl = '';
    String? inlineData;

    if (encryptedBlob.length <= 3500000) {
      inlineData = base64.encode(encryptedBlob);
    } else {
      try {
        blobUrl = await _uploadToRelay(encryptedBlob);
      } catch (e) {
        inlineData = base64.encode(encryptedBlob);
      }
    }

    if (blobUrl.isEmpty && inlineData == null) {
      inlineData = base64.encode(encryptedBlob);
    }

    return EphemeralMediaPayload(
      mediaType: mediaType,
      url: blobUrl,
      mediaKeyBase64: keyBase64,
      size: rawBytes.length,
      inlineCiphertext: inlineData,
      caption: caption,
    );
  }

  /// Uploads binary ciphertext to ephemeral storage relay (Catbox / tmpfiles)
  Future<String> _uploadToRelay(Uint8List encryptedBytes) async {
    try {
      // tmpfiles.org upload API
      final uri = Uri.parse('https://tmpfiles.org/api/v1/upload');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encryptedBytes,
          filename: 'ephemeral_${DateTime.now().millisecondsSinceEpoch}.enc',
        ),
      );

      final response = await request.send().timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        if (json['status'] == 'success' && json['data'] != null) {
          final rawUrl = json['data']['url'] as String;
          // Convert view page URL to direct download URL (tmpfiles.org/XXXX -> tmpfiles.org/dl/XXXX)
          return rawUrl.replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
        }
      }
    } catch (_) {}

    // Fallback: Catbox.moe
    try {
      final uri = Uri.parse('https://catbox.moe/user/api.php');
      final request = http.MultipartRequest('POST', uri);
      request.fields['reqtype'] = 'fileupload';
      request.files.add(
        http.MultipartFile.fromBytes(
          'fileToUpload',
          encryptedBytes,
          filename: 'blob_${DateTime.now().millisecondsSinceEpoch}.enc',
        ),
      );

      final response = await request.send().timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final directUrl = (await response.stream.bytesToString()).trim();
        if (directUrl.startsWith('http')) {
          return directUrl;
        }
      }
    } catch (_) {}

    return '';
  }

  /// Downloads ciphertext blob and decrypts directly into volatile memory (RAM)
  Future<Uint8List> downloadAndDecrypt(EphemeralMediaPayload payload) async {
    Uint8List decodeBase64Safe(String str) {
      final normalized = base64.normalize(str);
      try {
        return base64.decode(normalized);
      } catch (_) {
        return base64Url.decode(normalized);
      }
    }

    Uint8List encryptedData;

    if (payload.inlineCiphertext != null && payload.inlineCiphertext!.isNotEmpty) {
      encryptedData = decodeBase64Safe(payload.inlineCiphertext!);
    } else if (payload.url.isNotEmpty) {
      final response = await http.get(Uri.parse(payload.url)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final body = response.bodyBytes;
        if (body.length > 5 && (body[0] == 60 || body[0] == 123)) {
          final preview = String.fromCharCodes(body.take(100));
          if (preview.contains('<html') || preview.contains('<!DOCTYPE') || preview.contains('"error"')) {
            throw Exception('Relay server error: returned HTML webpage instead of encrypted media file');
          }
        }
        encryptedData = body;
      } else {
        throw Exception('Failed to download encrypted media (Status: ${response.statusCode})');
      }
    } else {
      throw Exception('No media source available');
    }

    if (encryptedData.length < 32) {
      throw Exception('Corrupted or invalid encrypted payload (size: ${encryptedData.length} bytes)');
    }

    // Decrypt binary format
    int offset = 0;
    final nonceLength = encryptedData[offset++];
    final nonce = encryptedData.sublist(offset, offset + nonceLength);
    offset += nonceLength;

    final macLength = encryptedData[offset++];
    final macBytes = encryptedData.sublist(offset, offset + macLength);
    offset += macLength;

    final cipherText = encryptedData.sublist(offset);

    final keyBytes = decodeBase64Safe(payload.mediaKeyBase64);
    final secretKey = SecretKey(keyBytes);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedList = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decryptedList);
  }

  /// Cryptographically shreds in-memory bytes by zeroing them out
  void shredMemory(Uint8List? buffer) {
    if (buffer == null || buffer.isEmpty) return;
    try {
      buffer.fillRange(0, buffer.length, 0);
    } catch (_) {}
  }
}
