import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';
import 'whatsapp_camera_screen.dart';
import '../../../services/media/media_picker_helper.dart';
export '../../../services/media/media_picker_helper.dart' show MediaPreviewItem, MediaPickerHelper;

class MediaSendResult {
  final bool shouldSend;
  final String caption;
  final Uint8List? editedBytes;
  final List<MediaPreviewItem>? items;

  MediaSendResult({
    required this.shouldSend,
    required this.caption,
    this.editedBytes,
    this.items,
  });
}

/// WhatsApp-style full screen Media Preview & Editor screen before sending.
/// Supports both single media and multi-media with a bottom thumbnail carousel,
/// horizontal swipe navigation, add/remove media, and photo editing via `pro_image_editor`.
class MediaSendPreviewScreen extends StatefulWidget {
  final Uint8List rawBytes;
  final String mediaType; // 'photo' | 'video'
  final String recipientName;
  final List<MediaPreviewItem>? initialItems;

  const MediaSendPreviewScreen({
    super.key,
    required this.rawBytes,
    required this.mediaType,
    required this.recipientName,
    this.initialItems,
  });

  @override
  State<MediaSendPreviewScreen> createState() => _MediaSendPreviewScreenState();
}

class _MediaSendPreviewScreenState extends State<MediaSendPreviewScreen> {
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isOverlayVisible = true;

  late List<MediaPreviewItem> _items;
  int _currentIndex = 0;
  late PageController _pageController;

  double _cachedTopPadding = 0.0;
  double _cachedBottomPadding = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _items = List.from(widget.initialItems!);
    } else {
      _items = [
        MediaPreviewItem(
          id: 'item_0',
          rawBytes: widget.rawBytes,
          mediaType: widget.mediaType,
        ),
      ];
    }

    _pageController = PageController(initialPage: _currentIndex);
    if (_items[_currentIndex].isVideo) {
      _initVideoForItem(_items[_currentIndex]);
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final item = _items.isNotEmpty && _currentIndex < _items.length ? _items[_currentIndex] : null;
    if (item?.videoController == null) return;
    final value = item!.videoController!.value;
    if (value.isInitialized && value.duration > Duration.zero && value.position >= value.duration) {
      if (value.isPlaying) {
        item.videoController!.pause();
        item.videoController!.seekTo(Duration.zero);
      }
    }
    setState(() {});
  }

  Future<void> _initVideoForItem(MediaPreviewItem item) async {
    if (item.videoController != null && item.isVideoInitialized) return;
    try {
      if (kIsWeb) {
        final uri = Uri.dataFromBytes(item.rawBytes, mimeType: 'video/mp4');
        item.videoController = VideoPlayerController.networkUrl(uri);
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}_${item.id}.mp4';
        item.tempVideoFile = File(tempPath);
        await item.tempVideoFile!.writeAsBytes(item.rawBytes, flush: true);
        item.videoController = VideoPlayerController.file(item.tempVideoFile!);
      }

      await item.videoController!.initialize();
      item.videoController!.addListener(_onVideoUpdate);
      if (mounted) {
        setState(() {
          item.isVideoInitialized = true;
        });
        item.videoController!.setLooping(false);
        item.videoController!.play();
      }
    } catch (e) {
      debugPrint('[MediaSendPreview] Error initializing video: $e');
    }
  }

  void _onPageChanged(int index) {
    if (_items.isEmpty) return;
    // Save current caption
    _items[_currentIndex].caption = _captionController.text;

    // Pause previous video if playing
    if (_items[_currentIndex].videoController?.value.isPlaying == true) {
      _items[_currentIndex].videoController!.pause();
    }

    setState(() {
      _currentIndex = index;
      _captionController.text = _items[_currentIndex].caption;
    });

    if (_items[_currentIndex].isVideo) {
      _initVideoForItem(_items[_currentIndex]);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _captionController.dispose();
    _focusNode.dispose();
    _pageController.dispose();

    for (final item in _items) {
      item.videoController?.removeListener(_onVideoUpdate);
      item.videoController?.dispose();
      if (!kIsWeb && item.tempVideoFile != null && item.tempVideoFile!.existsSync()) {
        try {
          item.tempVideoFile!.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final top = MediaQuery.paddingOf(context).top;
    if (top > _cachedTopPadding) {
      _cachedTopPadding = top;
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (bottom > _cachedBottomPadding) {
      _cachedBottomPadding = bottom;
    }
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
    final currentItem = _items[_currentIndex];
    if (currentItem.isVideo) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProImageEditor.memory(
          currentItem.displayBytes,
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
                currentItem.editedBytes = bytes;
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
      _items[_currentIndex].editedBytes = null;
    });
  }

  void _handleSend() {
    if (_items.isEmpty) return;
    _items[_currentIndex].caption = _captionController.text.trim();
    Navigator.pop(
      context,
      MediaSendResult(
        shouldSend: true,
        caption: _items.first.caption,
        editedBytes: _items.first.editedBytes,
        items: _items,
      ),
    );
  }

  void _toggleVideoPlayback() {
    final currentItem = _items[_currentIndex];
    if (currentItem.videoController == null) return;
    setState(() {
      if (currentItem.videoController!.value.isPlaying) {
        currentItem.videoController!.pause();
      } else {
        if (currentItem.videoController!.value.position >= currentItem.videoController!.value.duration) {
          currentItem.videoController!.seekTo(Duration.zero);
        }
        currentItem.videoController!.play();
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }


  Future<void> _pickFromBottomPhotoPicker() async {
    final newItems = await MediaPickerHelper.pickMultipleMedia();
    if (newItems.isEmpty) return;

    if (mounted) {
      setState(() {
        _items.addAll(newItems);
        _currentIndex = _items.length - 1;
        _captionController.text = _items[_currentIndex].caption;
      });

      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );

      if (_items[_currentIndex].isVideo) {
        _initVideoForItem(_items[_currentIndex]);
      }
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final result = await Navigator.push<CapturedMedia>(
        context,
        MaterialPageRoute(builder: (_) => const WhatsAppCameraScreen()),
      );
      if (result == null) return;

      final newItems = <MediaPreviewItem>[
        MediaPreviewItem(
          id: 'item_${DateTime.now().millisecondsSinceEpoch}_0',
          rawBytes: result.rawBytes,
          mediaType: result.mediaType,
        ),
      ];

      if (result.additionalMedia != null) {
        for (int i = 0; i < result.additionalMedia!.length; i++) {
          final add = result.additionalMedia![i];
          newItems.add(MediaPreviewItem(
            id: 'item_${DateTime.now().millisecondsSinceEpoch}_${i + 1}',
            rawBytes: add.rawBytes,
            mediaType: add.mediaType,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _currentIndex = _items.length - 1;
          _captionController.text = _items[_currentIndex].caption;
        });

        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );

        if (_items[_currentIndex].isVideo) {
          _initVideoForItem(_items[_currentIndex]);
        }
      }
    } catch (e) {
      debugPrint('[MediaSendPreview] Error capturing from camera: $e');
    }
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
      Navigator.pop(context);
      return;
    }

    final removed = _items.removeAt(index);
    removed.videoController?.removeListener(_onVideoUpdate);
    removed.videoController?.dispose();
    if (!kIsWeb && removed.tempVideoFile?.existsSync() == true) {
      try {
        removed.tempVideoFile!.deleteSync();
      } catch (_) {}
    }

    int nextIndex = _currentIndex;
    if (nextIndex >= _items.length) {
      nextIndex = _items.length - 1;
    }

    setState(() {
      _currentIndex = nextIndex;
      _captionController.text = _items[_currentIndex].caption;
    });

    _pageController.jumpToPage(_currentIndex);

    if (_items[_currentIndex].isVideo) {
      _initVideoForItem(_items[_currentIndex]);
    }
  }

  Widget _buildVideoScrubber(MediaPreviewItem item) {
    if (!item.isVideoInitialized || item.videoController == null) return const SizedBox.shrink();
    final duration = item.videoController!.value.duration;
    final position = item.videoController!.value.position;
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
                  item.videoController!.seekTo(Duration(milliseconds: value.toInt()));
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

  Widget _buildThumbnailStrip() {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            // "+" Add more media button
            return Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Add media',
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                onPressed: _pickFromCamera,
              ),
            );
          }

          final item = _items[index];
          final isSelected = index == _currentIndex;

          return GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? MineTheme.accentGreen : Colors.transparent,
                      width: 2.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: item.isVideo
                        ? Container(
                            color: const Color(0xFF1B272E),
                            child: const Center(
                              child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 20),
                            ),
                          )
                        : Image.memory(
                            item.displayBytes,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _removeItem(index),
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 11),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaItemView(MediaPreviewItem item) {
    if (item.isVideo) {
      final isPlaying = item.videoController != null && item.videoController!.value.isPlaying;
      return Center(
        child: item.isVideoInitialized && item.videoController != null
            ? AspectRatio(
                aspectRatio: item.videoController!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(item.videoController!),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
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
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
            : const CircularProgressIndicator(color: MineTheme.accentGreen),
      );
    } else {
      return Center(
        child: Image.memory(
          item.displayBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = _items.isNotEmpty && _currentIndex < _items.length ? _items[_currentIndex] : null;
    final bool isVideo = currentItem?.isVideo ?? false;
    final bool hasEdits = currentItem?.editedBytes != null;

    final currentTop = MediaQuery.paddingOf(context).top;
    if (currentTop > _cachedTopPadding) {
      _cachedTopPadding = currentTop;
    }
    final topPadding = _cachedTopPadding > 0 ? _cachedTopPadding : 28.0;

    final currentBottom = MediaQuery.paddingOf(context).bottom;
    if (currentBottom > _cachedBottomPadding) {
      _cachedBottomPadding = currentBottom;
    }
    final bottomPadding = _cachedBottomPadding > 0 ? _cachedBottomPadding : 12.0;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _isOverlayVisible ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: _isOverlayVisible ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Center Swipeable Media PageView
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    return _buildMediaItemView(_items[index]);
                  },
                ),
              ),

              // 2. Top Bar (Close button, Recipient Header, Edit/Reset Tools, Count)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  opacity: _isOverlayVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_isOverlayVisible,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: topPadding + 6,
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.recipientName.isNotEmpty ? widget.recipientName : 'Preview',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_items.length > 1)
                                Text(
                                  '${_currentIndex + 1} of ${_items.length}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),

                          // Action Icons for Photo Editing
                          if (!isVideo) ...[
                            IconButton(
                              tooltip: 'Edit photo',
                              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 24),
                              onPressed: _openProImageEditor,
                            ),
                            if (hasEdits)
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
                ),
              ),

              // 3. Bottom Overlay Bar (Thumbnail Strip + Caption Input + Send Button)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  opacity: _isOverlayVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_isOverlayVisible,
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
                              : bottomPadding + 8,
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
                            if (isVideo && currentItem != null) _buildVideoScrubber(currentItem),
                            _buildThumbnailStrip(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Caption Text Field with Image Icon before text
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: MineTheme.surfaceDark.withAlpha(240),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white12, width: 1),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          padding: const EdgeInsets.only(left: 10, right: 4),
                                          constraints: const BoxConstraints(),
                                          tooltip: 'Select photos/videos',
                                          icon: const Icon(
                                            Icons.photo_library_outlined,
                                            color: Colors.white70,
                                            size: 22,
                                          ),
                                          onPressed: _pickFromBottomPhotoPicker,
                                        ),
                                        Expanded(
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
                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),
                                      ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
