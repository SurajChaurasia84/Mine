import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:video_player/video_player.dart';

/// Reusable model for any picked/captured media item in the app
class MediaPreviewItem {
  final String id;
  final Uint8List rawBytes;
  Uint8List? editedBytes;
  final String mediaType; // 'photo' | 'video'
  String caption;
  VideoPlayerController? videoController;
  File? tempVideoFile;
  bool isVideoInitialized;

  MediaPreviewItem({
    required this.id,
    required this.rawBytes,
    this.editedBytes,
    required this.mediaType,
    this.caption = '',
    this.videoController,
    this.tempVideoFile,
    this.isVideoInitialized = false,
  });

  Uint8List get displayBytes => editedBytes ?? rawBytes;
  bool get isVideo => mediaType == 'video';
}

/// Centralized reusable helper for picking single or multiple media (photos & videos)
/// across the entire app. Launches the modern system bottom-sheet Photo Picker.
class MediaPickerHelper {
  static final ImagePicker _picker = ImagePicker();
  static bool _configured = false;

  /// Ensures Android system Photo Picker (bottom sheet) is enabled instead of
  /// the fallback document/file manager.
  static void ensureConfigured() {
    if (_configured) return;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final platform = ImagePickerPlatform.instance;
        if (platform is ImagePickerAndroid) {
          platform.useAndroidPhotoPicker = true;
        }
      }
    } catch (e) {
      debugPrint('[MediaPickerHelper] Error enabling Android photo picker: $e');
    }
    _configured = true;
  }

  /// Launches the system bottom-sheet Photo Picker (supports multiple photos and videos together).
  static Future<List<MediaPreviewItem>> pickMultipleMedia() async {
    ensureConfigured();
    try {
      final List<XFile> pickedFiles = await _picker.pickMultipleMedia();
      if (pickedFiles.isEmpty) return [];

      final items = <MediaPreviewItem>[];
      for (int i = 0; i < pickedFiles.length; i++) {
        final f = pickedFiles[i];
        final bytes = await f.readAsBytes();
        final pathLower = f.path.toLowerCase();
        final isVideo = pathLower.endsWith('.mp4') ||
            pathLower.endsWith('.mov') ||
            pathLower.endsWith('.mkv') ||
            pathLower.endsWith('.webm') ||
            pathLower.endsWith('.avi');

        items.add(MediaPreviewItem(
          id: 'item_${DateTime.now().millisecondsSinceEpoch}_$i',
          rawBytes: bytes,
          mediaType: isVideo ? 'video' : 'photo',
        ));
      }
      return items;
    } catch (e) {
      debugPrint('[MediaPickerHelper] Error picking multiple media: $e');
      return [];
    }
  }

  /// Launches single media capture/picker from camera or gallery
  static Future<MediaPreviewItem?> pickSingle({
    ImageSource source = ImageSource.camera,
    bool isVideo = false,
  }) async {
    ensureConfigured();
    try {
      final XFile? file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(
              source: source,
              imageQuality: 80,
              maxWidth: 1920,
              maxHeight: 1920,
            );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final pathLower = file.path.toLowerCase();
      final actualIsVideo = isVideo ||
          pathLower.endsWith('.mp4') ||
          pathLower.endsWith('.mov') ||
          pathLower.endsWith('.mkv') ||
          pathLower.endsWith('.webm') ||
          pathLower.endsWith('.avi');

      return MediaPreviewItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}',
        rawBytes: bytes,
        mediaType: actualIsVideo ? 'video' : 'photo',
      );
    } catch (e) {
      debugPrint('[MediaPickerHelper] Error picking single media: $e');
      return null;
    }
  }
}
