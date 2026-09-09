import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoThumbnailInfo {
  final double aspectRatio;
  final Duration duration;
  final String durationString;
  final VideoPlayerController? controller;
  final bool isReady;
  final File? file;

  const VideoThumbnailInfo({
    required this.aspectRatio,
    required this.duration,
    required this.durationString,
    this.controller,
    required this.isReady,
    this.file,
  });

  VideoThumbnailInfo copyWith({
    double? aspectRatio,
    Duration? duration,
    String? durationString,
    VideoPlayerController? controller,
    bool? isReady,
    File? file,
  }) {
    return VideoThumbnailInfo(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      duration: duration ?? this.duration,
      durationString: durationString ?? this.durationString,
      controller: controller ?? this.controller,
      isReady: isReady ?? this.isReady,
      file: file ?? this.file,
    );
  }
}

/// High-performance singleton cache for WhatsApp-style instant video thumbnails.
/// Caches persistent disk files, video metadata, and an active VideoPlayerController pool.
class VideoThumbnailManager {
  static const int _maxControllers = 12;

  static final Map<int, VideoThumbnailInfo> _infoCache = {};
  static final Map<int, VideoPlayerController> _controllerPool = {};
  static final LinkedHashSet<int> _lruKeys = LinkedHashSet<int>();
  static final Map<int, Future<VideoThumbnailInfo>> _inFlight = {};

  static Directory? _mediaDir;

  /// Retrieves or creates private media directory for caching video files
  static Future<Directory?> _getMediaDirectory() async {
    if (kIsWeb) return null;
    if (_mediaDir != null && _mediaDir!.existsSync()) return _mediaDir;
    try {
      final baseDir = await getApplicationSupportDirectory();
      final dir = Directory('${baseDir.path}/.app_media');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final noMedia = File('${dir.path}/.nomedia');
      if (!noMedia.existsSync()) {
        await noMedia.writeAsString('');
      }
      _mediaDir = dir;
      return _mediaDir;
    } catch (_) {
      return null;
    }
  }

  /// Calculates a stable hash key for raw video bytes
  static int getHashKey(Uint8List bytes) {
    return bytes.hashCode;
  }

  /// Formats Duration into a clean video badge string (e.g., '0:14', '1:02')
  static String formatDuration(Duration d) {
    if (d <= Duration.zero) return '';
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString();
      return '$hours:${minutes.padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// Synchronously returns cached thumbnail information if already loaded
  static VideoThumbnailInfo? getCachedInfo(Uint8List bytes) {
    final key = getHashKey(bytes);
    final info = _infoCache[key];
    if (info != null) {
      // Touch LRU
      _touchLru(key);
      final activeController = _controllerPool[key];
      if (activeController != null && activeController.value.isInitialized) {
        return info.copyWith(controller: activeController, isReady: true);
      }
      return info;
    }
    return null;
  }

  /// Gets or creates a persistent local `.mp4` file for the given video bytes
  static Future<File?> getOrCreateVideoFile(Uint8List bytes, {String? key}) async {
    if (kIsWeb) return null;
    try {
      final dir = await _getMediaDirectory();
      if (dir == null) return null;
      final fileKey = key ?? getHashKey(bytes).abs().toString();
      final file = File('${dir.path}/vid_$fileKey.mp4');
      if (!file.existsSync() || file.lengthSync() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads or initializes video thumbnail with instant caching
  static Future<VideoThumbnailInfo> loadThumbnail(
    Uint8List bytes, {
    String? messageId,
    VoidCallback? onUpdate,
  }) async {
    final key = getHashKey(bytes);

    // 1. Check if controller is already active and ready in pool
    final existingController = _controllerPool[key];
    final existingInfo = _infoCache[key];
    if (existingController != null && existingController.value.isInitialized && existingInfo != null) {
      _touchLru(key);
      return existingInfo.copyWith(controller: existingController, isReady: true);
    }

    // 2. De-duplicate in-flight requests
    if (_inFlight.containsKey(key)) {
      return await _inFlight[key]!;
    }

    final future = _initController(key, bytes, messageId: messageId);
    _inFlight[key] = future;

    try {
      final info = await future;
      onUpdate?.call();
      return info;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<VideoThumbnailInfo> _initController(
    int key,
    Uint8List bytes, {
    String? messageId,
  }) async {
    VideoPlayerController? controller;
    File? videoFile;

    try {
      if (kIsWeb) {
        final uri = Uri.dataFromBytes(bytes, mimeType: 'video/mp4');
        controller = VideoPlayerController.networkUrl(uri);
      } else {
        videoFile = await getOrCreateVideoFile(bytes, key: messageId);
        if (videoFile != null && videoFile.existsSync()) {
          controller = VideoPlayerController.file(videoFile);
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_v_$key.mp4');
          await tempFile.writeAsBytes(bytes, flush: true);
          videoFile = tempFile;
          controller = VideoPlayerController.file(tempFile);
        }
      }

      await controller.initialize();
      await controller.pause();

      final size = controller.value.size;
      final rawAspect = controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : (size.width > 0 && size.height > 0 ? size.width / size.height : (16.0 / 9.0));
      final clampedAspect = rawAspect.clamp(9.0 / 16.0, 16.0 / 9.0);
      final duration = controller.value.duration;
      final durStr = formatDuration(duration);

      final info = VideoThumbnailInfo(
        aspectRatio: clampedAspect,
        duration: duration,
        durationString: durStr,
        controller: controller,
        isReady: true,
        file: videoFile,
      );

      _putController(key, controller);
      _infoCache[key] = info;

      return info;
    } catch (_) {
      // Fallback with standard WhatsApp 16:9 ratio
      final fallbackInfo = _infoCache[key] ??
          VideoThumbnailInfo(
            aspectRatio: 16.0 / 9.0,
            duration: Duration.zero,
            durationString: '',
            isReady: false,
            file: videoFile,
          );
      _infoCache[key] = fallbackInfo;
      return fallbackInfo;
    }
  }

  static void _touchLru(int key) {
    _lruKeys.remove(key);
    _lruKeys.add(key);
  }

  static void _putController(int key, VideoPlayerController controller) {
    _touchLru(key);
    _controllerPool[key] = controller;

    // Evict oldest controller if pool exceeds max limit to preserve device codec resources
    while (_controllerPool.length > _maxControllers && _lruKeys.isNotEmpty) {
      final oldestKey = _lruKeys.first;
      _lruKeys.remove(oldestKey);
      if (oldestKey != key) {
        final oldController = _controllerPool.remove(oldestKey);
        try {
          oldController?.dispose();
        } catch (_) {}
      }
    }
  }

  /// Cleans up controllers when leaving or logging out
  static void clear() {
    for (final controller in _controllerPool.values) {
      try {
        controller.dispose();
      } catch (_) {}
    }
    _controllerPool.clear();
    _lruKeys.clear();
    _inFlight.clear();
    _infoCache.clear();
  }
}
