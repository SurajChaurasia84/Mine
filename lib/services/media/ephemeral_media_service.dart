import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class EphemeralMediaPayload {
  final String mediaType; // 'photo' | 'video'
  final String url;
  final String mediaKeyBase64;
  final int size;
  final String? inlineCiphertext; // Optional fallback for fast local/offline delivery
  final String? caption;
  final String? senderName;
  final String? replyToMessageId;
  final String? replySenderName;
  final String? replyText;
  final String? replyMediaType;

  EphemeralMediaPayload({
    required this.mediaType,
    required this.url,
    required this.mediaKeyBase64,
    required this.size,
    this.inlineCiphertext,
    this.caption,
    this.senderName,
    this.replyToMessageId,
    this.replySenderName,
    this.replyText,
    this.replyMediaType,
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
      if (senderName != null && senderName!.isNotEmpty) 'sender_name': senderName,
      if (replyToMessageId != null || replySenderName != null || replyText != null)
        'reply_to': {
          if (replyToMessageId != null) 'id': replyToMessageId,
          if (replySenderName != null) 'sender_name': replySenderName,
          if (replyText != null) 'text': replyText,
          if (replyMediaType != null) 'media_type': replyMediaType,
        },
    };
  }

  factory EphemeralMediaPayload.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? replyMap;
    if (map['reply_to'] is Map) {
      replyMap = Map<String, dynamic>.from(map['reply_to'] as Map);
    }

    return EphemeralMediaPayload(
      mediaType: map['media_type'] as String? ?? 'photo',
      url: map['url'] as String? ?? '',
      mediaKeyBase64: map['key'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      inlineCiphertext: map['data'] as String?,
      caption: map['caption'] as String?,
      senderName: (map['sender_name'] ?? map['senderName']) as String?,
      replyToMessageId: replyMap?['id'] as String?,
      replySenderName: replyMap?['sender_name'] as String?,
      replyText: replyMap?['text'] as String?,
      replyMediaType: replyMap?['media_type'] as String?,
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
  final Sha256 _sha256 = Sha256();
  final Map<String, Uint8List> _memoryCache = {};
  Directory? _mediaDir;

  /// Retrieves or initializes the private app-only media storage directory.
  /// Uses a hidden folder and `.nomedia` file so media is strictly invisible to
  /// Gallery, Photos, and MediaScanner.
  Future<Directory?> _getMediaDirectory() async {
    if (kIsWeb) return null;
    if (_mediaDir != null && _mediaDir!.existsSync()) {
      return _mediaDir;
    }
    try {
      final baseDir = await getApplicationSupportDirectory();
      final mediaDir = Directory('${baseDir.path}/.app_media');
      if (!mediaDir.existsSync()) {
        await mediaDir.create(recursive: true);
      }
      // Create .nomedia file to prevent Android MediaScanner from scanning
      final noMediaFile = File('${mediaDir.path}/.nomedia');
      if (!noMediaFile.existsSync()) {
        await noMediaFile.writeAsString('');
      }
      _mediaDir = mediaDir;
      return _mediaDir;
    } catch (_) {
      return null;
    }
  }

  /// Generates a deterministic SHA-256 filename for caching on disk
  Future<String> _getDiskFileName(String key) async {
    final hash = await _sha256.hash(utf8.encode(key));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Saves decrypted media to local private disk cache
  Future<void> _saveMediaToDisk(String key, Uint8List bytes) async {
    if (kIsWeb || key.isEmpty || bytes.isEmpty) return;
    try {
      final dir = await _getMediaDirectory();
      if (dir == null) return;
      final fileName = await _getDiskFileName(key);
      final file = File('${dir.path}/$fileName.bin');
      if (!file.existsSync() || file.lengthSync() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  /// Reads media from local private disk cache if it exists
  Future<Uint8List?> _readMediaFromDisk(String key) async {
    if (kIsWeb || key.isEmpty) return null;
    try {
      final dir = await _getMediaDirectory();
      if (dir == null) return null;
      final fileName = await _getDiskFileName(key);
      final file = File('${dir.path}/$fileName.bin');
      if (file.existsSync() && file.lengthSync() > 0) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  /// Caches decrypted media bytes in memory and background-saves to app private disk
  void cacheMedia(String key, Uint8List bytes) {
    if (key.isEmpty || bytes.isEmpty) return;
    _memoryCache[key] = bytes;
    _saveMediaToDisk(key, bytes);
  }

  /// Synchronously retrieves in-memory media bytes if present
  Uint8List? getCachedMedia(String key) {
    return _memoryCache[key];
  }

  /// Asynchronously checks RAM first, then local private disk storage
  Future<Uint8List?> getCachedMediaAsync(String key) async {
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }
    final diskBytes = await _readMediaFromDisk(key);
    if (diskBytes != null && diskBytes.isNotEmpty) {
      _memoryCache[key] = diskBytes;
      return diskBytes;
    }
    return null;
  }

  /// Deletes cached media from memory and disk for a specific key
  Future<void> deleteMedia(String key) async {
    if (key.isEmpty) return;
    _memoryCache.remove(key);
    if (kIsWeb) return;
    try {
      final dir = await _getMediaDirectory();
      if (dir == null) return;
      final fileName = await _getDiskFileName(key);
      final file = File('${dir.path}/$fileName.bin');
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Deletes all media associated with a message (checks message ID, mediaKey, URL)
  Future<void> deleteMessageMedia(String messageId, {String? decryptedContent}) async {
    await deleteMedia(messageId);
    if (decryptedContent != null && decryptedContent.isNotEmpty) {
      final payload = EphemeralMediaPayload.tryParse(decryptedContent);
      if (payload != null) {
        if (payload.mediaKeyBase64.isNotEmpty) {
          await deleteMedia(payload.mediaKeyBase64);
        }
        if (payload.url.isNotEmpty) {
          await deleteMedia(payload.url);
        }
      }
    }
  }

  /// Deletes multiple media files (for clear chat or delete conversation)
  Future<void> deleteMessagesMedia(List<dynamic> messages) async {
    for (final m in messages) {
      try {
        final id = m.id as String;
        final content = m.decryptedContent as String?;
        await deleteMessageMedia(id, decryptedContent: content);
      } catch (_) {}
    }
  }

  /// Destroys in-memory media buffers for temporary/transient chats
  void clearTransientCache() {
    _memoryCache.forEach((_, buffer) {
      try {
        buffer.fillRange(0, buffer.length, 0);
      } catch (_) {}
    });
    _memoryCache.clear();
  }

  /// Generates a cryptographically secure 256-bit symmetric media key
  List<int> generateMediaKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  /// Compresses high-res images to optimal size (~200KB) for lightning-fast transmission
  Uint8List _optimizePhotoBytes(Uint8List rawBytes) {
    try {
      if (rawBytes.length <= 300000) return rawBytes;
      final image = img.decodeImage(rawBytes);
      if (image == null) return rawBytes;

      img.Image resized = image;
      if (image.width > 1600 || image.height > 1600) {
        resized = img.copyResize(
          image,
          width: image.width > image.height ? 1600 : null,
          height: image.height >= image.width ? 1600 : null,
          interpolation: img.Interpolation.linear,
        );
      }
      return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    } catch (_) {
      return rawBytes;
    }
  }

  /// Encrypts raw in-memory bytes with AES-256-GCM and uploads ciphertext blob
  Future<EphemeralMediaPayload> encryptAndUpload({
    required Uint8List rawBytes,
    required String mediaType, // 'photo' or 'video'
    String? caption,
    String? senderName,
    String? messageId,
    String? replyToMessageId,
    String? replySenderName,
    String? replyText,
    String? replyMediaType,
  }) async {
    final processedBytes = mediaType == 'photo' ? _optimizePhotoBytes(rawBytes) : rawBytes;
    final keyBytes = generateMediaKey();
    final secretKey = SecretKey(keyBytes);

    // 1. Encrypt with AES-GCM
    final secretBox = await _aesGcm.encrypt(
      processedBytes,
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

    String blobUrl = '';
    String? inlineData;

    // For tiny payloads <= 180KB (e.g. low-res thumbnail/tiny image), embed inline directly in E2EE message for 0ms instant delivery
    if (encryptedBlob.length <= 180000) {
      inlineData = base64.encode(encryptedBlob);
    } else {
      try {
        blobUrl = await _uploadToRelay(encryptedBlob);
      } catch (e) {
        // Log upload error
      }
    }

    if (blobUrl.isEmpty && inlineData == null) {
      // If upload failed, only embed inline if size is within safe MQTT broker limit (< 300KB)
      if (encryptedBlob.length <= 300000) {
        inlineData = base64.encode(encryptedBlob);
      } else {
        throw Exception('Media upload failed. Please check internet connection.');
      }
    }

    // Cache the original processed bytes under the media key, message ID, and URL
    _memoryCache[keyBase64] = processedBytes;
    await _saveMediaToDisk(keyBase64, processedBytes);
    if (messageId != null) {
      _memoryCache[messageId] = processedBytes;
      await _saveMediaToDisk(messageId, processedBytes);
    }
    if (blobUrl.isNotEmpty) {
      await _saveMediaToDisk(blobUrl, processedBytes);
    }

    return EphemeralMediaPayload(
      mediaType: mediaType,
      url: blobUrl,
      mediaKeyBase64: keyBase64,
      size: processedBytes.length,
      inlineCiphertext: inlineData,
      caption: caption,
      senderName: senderName,
      replyToMessageId: replyToMessageId,
      replySenderName: replySenderName,
      replyText: replyText,
      replyMediaType: replyMediaType,
    );
  }

  /// Uploads binary ciphertext to fast, reliable ephemeral relays (Bytebin / Filebin)
  Future<String> _uploadToRelay(Uint8List encryptedBytes) async {
    // 1. Primary Relay: Bytebin (Direct raw binary POST, high-speed CDN, full CORS support)
    try {
      final uri = Uri.parse('https://bytebin.lucko.me/post');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/octet-stream',
          'User-Agent': 'MineMessenger/1.0',
        },
        body: encryptedBytes,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json is Map && json['key'] != null) {
          final key = json['key'] as String;
          final directUrl = 'https://bytebin.lucko.me/$key';
          return directUrl;
        }
      }
    } catch (_) {}

    // 2. Secondary Relay: Filebin.net (Direct binary POST, CORS enabled, no auth needed)
    try {
      final binId = 'mine_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      final fileName = 'enc_${DateTime.now().millisecondsSinceEpoch}.bin';
      final uri = Uri.parse('https://filebin.net/$binId/$fileName');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/octet-stream',
          'User-Agent': 'MineMessenger/1.0',
        },
        body: encryptedBytes,
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return 'https://filebin.net/$binId/$fileName';
      }
    } catch (_) {}

    return '';
  }

  /// Gets media from in-memory cache or local disk storage, or downloads and decrypts
  Future<Uint8List> getOrDownloadMedia(EphemeralMediaPayload payload, {String? messageId}) async {
    // 1. Check RAM cache by key
    if (payload.mediaKeyBase64.isNotEmpty && _memoryCache.containsKey(payload.mediaKeyBase64)) {
      return _memoryCache[payload.mediaKeyBase64]!;
    }
    // 2. Check RAM cache by message ID
    if (messageId != null && _memoryCache.containsKey(messageId)) {
      return _memoryCache[messageId]!;
    }

    // 3. Check Local Disk Storage by mediaKeyBase64
    if (payload.mediaKeyBase64.isNotEmpty) {
      final diskBytes = await _readMediaFromDisk(payload.mediaKeyBase64);
      if (diskBytes != null && diskBytes.isNotEmpty) {
        _memoryCache[payload.mediaKeyBase64] = diskBytes;
        if (messageId != null) _memoryCache[messageId] = diskBytes;
        return diskBytes;
      }
    }

    // 4. Check Local Disk Storage by messageId
    if (messageId != null && messageId.isNotEmpty) {
      final diskBytes = await _readMediaFromDisk(messageId);
      if (diskBytes != null && diskBytes.isNotEmpty) {
        _memoryCache[messageId] = diskBytes;
        if (payload.mediaKeyBase64.isNotEmpty) _memoryCache[payload.mediaKeyBase64] = diskBytes;
        return diskBytes;
      }
    }

    // 5. Check Local Disk Storage by URL
    if (payload.url.isNotEmpty) {
      final diskBytes = await _readMediaFromDisk(payload.url);
      if (diskBytes != null && diskBytes.isNotEmpty) {
        _memoryCache[payload.url] = diskBytes;
        if (payload.mediaKeyBase64.isNotEmpty) _memoryCache[payload.mediaKeyBase64] = diskBytes;
        if (messageId != null) _memoryCache[messageId] = diskBytes;
        return diskBytes;
      }
    }

    // 6. Not in local storage -> Download over network and decrypt
    final bytes = await downloadAndDecrypt(payload);

    // 7. Store in RAM and persist to private app disk storage so it never downloads again
    if (payload.mediaKeyBase64.isNotEmpty) {
      _memoryCache[payload.mediaKeyBase64] = bytes;
      await _saveMediaToDisk(payload.mediaKeyBase64, bytes);
    }
    if (messageId != null) {
      _memoryCache[messageId] = bytes;
      await _saveMediaToDisk(messageId, bytes);
    }
    if (payload.url.isNotEmpty) {
      await _saveMediaToDisk(payload.url, bytes);
    }

    return bytes;
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
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
      };
      final response = await http.get(Uri.parse(payload.url), headers: headers).timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        final body = response.bodyBytes;
        if (body.length > 5 && (body[0] == 60 || body[0] == 123)) {
          final preview = String.fromCharCodes(body.take(100));
          if (preview.contains('<html') || preview.contains('<!DOCTYPE') || preview.contains('"error"') || preview.contains('BunkerWeb')) {
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
