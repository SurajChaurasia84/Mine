import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';

class EphemeralMediaViewerScreen extends StatefulWidget {
  final Uint8List rawBytes;
  final String mediaType; // 'photo' | 'video'
  final String senderName;
  final String? caption;

  const EphemeralMediaViewerScreen({
    super.key,
    required this.rawBytes,
    required this.mediaType,
    required this.senderName,
    this.caption,
  });

  @override
  State<EphemeralMediaViewerScreen> createState() => _EphemeralMediaViewerScreenState();
}

class _EphemeralMediaViewerScreenState extends State<EphemeralMediaViewerScreen> {
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _isVideoInitialized = false;
  bool _isOverlayVisible = true;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _initVideo();
    }
  }

  void _onVideoUpdate() {
    if (!mounted || _videoController == null) return;
    final value = _videoController!.value;
    if (value.isInitialized && value.duration > Duration.zero && value.position >= value.duration) {
      if (value.isPlaying) {
        _videoController!.pause();
        _videoController!.seekTo(Duration.zero);
      }
    }
    setState(() {});
  }

  Future<void> _initVideo() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/ephemeral_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _tempVideoFile = File(tempPath);
      await _tempVideoFile!.writeAsBytes(widget.rawBytes, flush: true);

      _videoController = VideoPlayerController.file(_tempVideoFile!);
      await _videoController!.initialize();
      _videoController!.addListener(_onVideoUpdate);
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController!.setLooping(false);
        _videoController!.play();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    if (_tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }
    try {
      widget.rawBytes.fillRange(0, widget.rawBytes.length, 0);
    } catch (_) {}
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() {
      _isOverlayVisible = !_isOverlayVisible;
    });
  }

  void _toggleVideoPlayback() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        if (_videoController!.value.position >= _videoController!.value.duration) {
          _videoController!.seekTo(Duration.zero);
        }
        _videoController!.play();
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildVideoScrubber() {
    if (!_isVideoInitialized || _videoController == null) return const SizedBox.shrink();
    final duration = _videoController!.value.duration;
    final position = _videoController!.value.position;
    final durationMs = duration.inMilliseconds.toDouble();
    final positionMs = position.inMilliseconds.toDouble().clamp(0.0, durationMs > 0 ? durationMs : 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            _formatDuration(position),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: MineTheme.accentGreen,
                inactiveTrackColor: Colors.white30,
                thumbColor: MineTheme.accentGreen,
                overlayColor: MineTheme.accentGreen.withAlpha(60),
              ),
              child: Slider(
                value: positionMs,
                min: 0.0,
                max: durationMs > 0 ? durationMs : 1.0,
                onChanged: (value) {
                  _videoController!.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
          ),
          Text(
            _formatDuration(duration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = _videoController != null && _videoController!.value.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleOverlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media Content Area
            Center(
              child: widget.mediaType == 'video'
                  ? (_isVideoInitialized && _videoController != null
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_videoController!),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _isOverlayVisible ? 1.0 : 0.0,
                                child: IgnorePointer(
                                  ignoring: !_isOverlayVisible,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(40),
                                      onTap: _toggleVideoPlayback,
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(140),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(80),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 46,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _isOverlayVisible ? 0 : -80,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
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
            ),

            // Bottom Bar (Video Progress Scrubber + Caption)
            if ((widget.caption != null && widget.caption!.isNotEmpty) || widget.mediaType == 'video')
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _isOverlayVisible ? 0 : -140,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 14,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black87],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.mediaType == 'video') _buildVideoScrubber(),
                      if (widget.caption != null && widget.caption!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            widget.caption!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
