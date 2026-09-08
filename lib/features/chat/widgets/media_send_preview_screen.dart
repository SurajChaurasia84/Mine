import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';

class MediaSendResult {
  final bool shouldSend;
  final String caption;
  final Uint8List? editedBytes;

  MediaSendResult({
    required this.shouldSend,
    required this.caption,
    this.editedBytes,
  });
}

/// WhatsApp-style full screen Media Preview & Editor screen before sending.
/// Powered by `pro_image_editor` for photo editing (crop, rotate, draw, text, filters, stickers, etc.)
class MediaSendPreviewScreen extends StatefulWidget {
  final Uint8List rawBytes;
  final String mediaType; // 'photo' | 'video'
  final String recipientName;

  const MediaSendPreviewScreen({
    super.key,
    required this.rawBytes,
    required this.mediaType,
    required this.recipientName,
  });

  @override
  State<MediaSendPreviewScreen> createState() => _MediaSendPreviewScreenState();
}

class _MediaSendPreviewScreenState extends State<MediaSendPreviewScreen> {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isOverlayVisible = true;
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _isVideoInitialized = false;

  // Image editing state
  late Uint8List _currentBytes;
  bool _hasEdits = false;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.rawBytes;
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
      if (kIsWeb) {
        final uri = Uri.dataFromBytes(widget.rawBytes, mimeType: 'video/mp4');
        _videoController = VideoPlayerController.networkUrl(uri);
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.mp4';
        _tempVideoFile = File(tempPath);
        await _tempVideoFile!.writeAsBytes(widget.rawBytes, flush: true);
        _videoController = VideoPlayerController.file(_tempVideoFile!);
      }

      await _videoController!.initialize();
      _videoController!.addListener(_onVideoUpdate);
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController!.setLooping(false);
        _videoController!.play();
      }
    } catch (e) {
      debugPrint('[MediaSendPreview] Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    if (!kIsWeb && _tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  void _toggleOverlay() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
      return;
    }
    setState(() {
      _isOverlayVisible = !_isOverlayVisible;
    });
  }

  Future<void> _openProImageEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProImageEditor.memory(
          _currentBytes,
          configs: ProImageEditorConfigs(
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: Colors.black,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              colorScheme: const ColorScheme.dark(
                primary: MineTheme.accentGreen,
                secondary: MineTheme.accentGreen,
              ),
            ),
          ),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              setState(() {
                _currentBytes = bytes;
                _hasEdits = true;
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  void _resetToOriginal() {
    setState(() {
      _currentBytes = widget.rawBytes;
      _hasEdits = false;
    });
  }

  void _handleSend() {
    final caption = _captionController.text.trim();
    Navigator.pop(
      context,
      MediaSendResult(
        shouldSend: true,
        caption: caption,
        editedBytes: _hasEdits ? _currentBytes : null,
      ),
    );
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

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
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
    final bool isVideo = widget.mediaType == 'video';
    final bool isPlaying = _videoController != null && _videoController!.value.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleOverlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Center Image / Video Area
            Center(
              child: isVideo
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
                      : const CircularProgressIndicator(color: MineTheme.accentGreen))
                  : Image.memory(
                      _currentBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),

            // 2. Top Bar (Close button, Recipient Header, Edit and Reset Tools)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _isOverlayVisible ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 6,
                  left: 6,
                  right: 12,
                  bottom: 10,
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
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.recipientName.isNotEmpty ? widget.recipientName : 'Preview',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),

                    // Action Icons for Photo Editing
                    if (!isVideo) ...[
                      // Open Full Pro Image Editor (Crop, Rotate, Filter, Draw, Text, etc.)
                      IconButton(
                        tooltip: 'Edit photo',
                        icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 24),
                        onPressed: _openProImageEditor,
                      ),

                      // Reset button (Visible when modified)
                      if (_hasEdits)
                        IconButton(
                          tooltip: 'Reset to original',
                          icon: const Icon(Icons.restart_alt_rounded, color: Colors.orangeAccent, size: 24),
                          onPressed: _resetToOriginal,
                        ),
                    ],

                    if (isVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_rounded, color: Colors.white, size: 15),
                            SizedBox(width: 6),
                            Text('Video', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 3. Bottom Overlay Bar (Caption Input + Send Button)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                offset: _isOverlayVisible ? Offset.zero : const Offset(0, 1.5),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 10,
                      bottom: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 8
                          : MediaQuery.of(context).padding.bottom + 12,
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
                        if (isVideo) _buildVideoScrubber(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Caption Text Field
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: MineTheme.surfaceDark.withAlpha(240),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white12, width: 1),
                                ),
                                child: TextField(
                                  controller: _captionController,
                                  focusNode: _focusNode,
                                  maxLines: 4,
                                  minLines: 1,
                                  textCapitalization: TextCapitalization.sentences,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                  decoration: const InputDecoration(
                                    hintText: 'Add a caption...',
                                    hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Send Button
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: MineTheme.accentGreen,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _handleSend,
                                  child: const Center(
                                    child: Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFF00382B),
                                      size: 22,
                                    ),
                                  ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
