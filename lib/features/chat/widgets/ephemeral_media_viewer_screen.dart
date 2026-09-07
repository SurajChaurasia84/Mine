import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class EphemeralMediaViewerScreen extends StatefulWidget {
  final Uint8List rawBytes;
  final String mediaType; // 'photo' | 'video'
  final String senderName;

  const EphemeralMediaViewerScreen({
    super.key,
    required this.rawBytes,
    required this.mediaType,
    required this.senderName,
  });

  @override
  State<EphemeralMediaViewerScreen> createState() => _EphemeralMediaViewerScreenState();
}

class _EphemeralMediaViewerScreenState extends State<EphemeralMediaViewerScreen> {
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/ephemeral_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _tempVideoFile = File(tempPath);
      await _tempVideoFile!.writeAsBytes(widget.rawBytes, flush: true);

      _videoController = VideoPlayerController.file(_tempVideoFile!)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoInitialized = true;
            });
            _videoController!.play();
            _videoController!.setLooping(true);
          }
        });
    } catch (_) {}
  }

  @override
  void dispose() {
    // 1. Dispose video controller
    _videoController?.dispose();

    // 2. Wipe & delete temp video file if any
    if (_tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }

    // 3. Shred in-memory byte buffer
    try {
      widget.rawBytes.fillRange(0, widget.rawBytes.length, 0);
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media Content Area
            Center(
              child: widget.mediaType == 'video'
                  ? (_isVideoInitialized && _videoController != null
                      ? GestureDetector(
                          onTap: () {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                            setState(() {});
                          },
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_videoController!),
                                if (!_videoController!.value.isPlaying)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(120),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const CircularProgressIndicator(color: Colors.white))
                  : InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: Image.memory(
                        widget.rawBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),

            // Top overlay bar with sender name and close button
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(150),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.mediaType == 'video' ? Icons.videocam : Icons.photo_camera,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.senderName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Close Button
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
