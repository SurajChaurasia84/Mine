import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'media_picker_helper.dart';

/// Service to handle incoming media (photos & videos) shared from external apps
/// (Gallery, File Manager, etc.) via the system share sheet.
class IncomingShareService {
  static StreamSubscription? _intentSub;
  static bool _isProcessing = false;

  /// Starts listening to incoming shared media.
  static void listen({
    required Function(List<MediaPreviewItem> items) onMediaReceived,
  }) {
    // 1. Listen when app is already in memory / background
    _intentSub?.cancel();
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) async {
        if (value.isNotEmpty) {
          await _handleIncomingFiles(value, onMediaReceived);
        }
      },
      onError: (err) {
        debugPrint('[IncomingShareService] Media stream error: $err');
      },
    );

    // 2. Handle cold start when app was launched from terminated state via share
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) async {
      if (value.isNotEmpty) {
        await _handleIncomingFiles(value, onMediaReceived);
        // Reset intent once handled so it doesn't trigger repeatedly
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((err) {
      debugPrint('[IncomingShareService] Initial media error: $err');
    });
  }

  static Future<void> _handleIncomingFiles(
    List<SharedMediaFile> files,
    Function(List<MediaPreviewItem> items) onMediaReceived,
  ) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final items = <MediaPreviewItem>[];
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final file = File(f.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final pathLower = f.path.toLowerCase();
          final isVideo = f.type == SharedMediaType.video ||
              pathLower.endsWith('.mp4') ||
              pathLower.endsWith('.mov') ||
              pathLower.endsWith('.mkv') ||
              pathLower.endsWith('.webm') ||
              pathLower.endsWith('.avi');

          items.add(MediaPreviewItem(
            id: 'share_${DateTime.now().millisecondsSinceEpoch}_$i',
            rawBytes: bytes,
            mediaType: isVideo ? 'video' : 'photo',
          ));
        }
      }

      if (items.isNotEmpty) {
        onMediaReceived(items);
      }
    } catch (e) {
      debugPrint('[IncomingShareService] Error processing shared files: $e');
    } finally {
      _isProcessing = false;
    }
  }

  static void dispose() {
    _intentSub?.cancel();
    _intentSub = null;
  }
}
