import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';
import '../../../data/models/message_model.dart';
import '../../../services/connection_manager/connection_manager.dart';
import '../../../services/media/ephemeral_media_service.dart';
import '../../../services/media/video_thumbnail_manager.dart';

/// Data model representing a media item in the viewer
class EphemeralMediaItem {
  final MessageModel? message;
  final EphemeralMediaPayload? payload;
  final Uint8List? rawBytes;
  final String mediaType; // 'photo' | 'video'
  final String senderName;
  final String? caption;

  const EphemeralMediaItem({
    this.message,
    this.payload,
    this.rawBytes,
    required this.mediaType,
    required this.senderName,
    this.caption,
  });
}

class EphemeralMediaViewerScreen extends StatefulWidget {
  final List<EphemeralMediaItem>? items;
  final int initialIndex;

  // Single-item legacy parameters for backwards compatibility
  final Uint8List? rawBytes;
  final String? mediaType;
  final String? senderName;
  final String? caption;

  const EphemeralMediaViewerScreen({
    super.key,
    this.items,
    this.initialIndex = 0,
    this.rawBytes,
    this.mediaType,
    this.senderName,
    this.caption,
  });

  @override
  State<EphemeralMediaViewerScreen> createState() => _EphemeralMediaViewerScreenState();
}

class _EphemeralMediaViewerScreenState extends State<EphemeralMediaViewerScreen> with TickerProviderStateMixin {
  late final List<EphemeralMediaItem> _items;
  late int _currentIndex;
  late PageController _pageController;

  bool _isOverlayVisible = true;
  bool _isZoomed = false;
  bool _isDraggingDismiss = false;

  // Swipe-to-dismiss tracking
  double _dragOffsetY = 0.0;
  late AnimationController _dismissAnimController;
  late Animation<double> _dismissAnimation;

  // Active Video Controller for scrubber
  VideoPlayerController? _activeVideoController;

  double _cachedTopPadding = 0.0;
  double _cachedBottomPadding = 0.0;

  @override
  void initState() {
    super.initState();

    if (widget.items != null && widget.items!.isNotEmpty) {
      _items = List<EphemeralMediaItem>.from(widget.items!);
      _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    } else {
      _items = [
        EphemeralMediaItem(
          rawBytes: widget.rawBytes,
          mediaType: widget.mediaType ?? 'photo',
          senderName: widget.senderName ?? '',
          caption: widget.caption,
        ),
      ];
      _currentIndex = 0;
    }

    _pageController = PageController(initialPage: _currentIndex);

    _dismissAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        setState(() {
          _dragOffsetY = _dismissAnimation.value;
        });
      });
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

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _dismissAnimController.dispose();
    _activeVideoController?.removeListener(_onVideoUpdate);
    super.dispose();
  }

  void _onVideoUpdate() {
    if (!mounted || _activeVideoController == null) return;
    final value = _activeVideoController!.value;
    if (value.isInitialized && value.duration > Duration.zero && value.position >= value.duration) {
      if (value.isPlaying) {
        _activeVideoController!.pause();
        _activeVideoController!.seekTo(Duration.zero);
      }
    }
    setState(() {});
  }

  void _setActiveVideoController(VideoPlayerController? controller) {
    if (_activeVideoController == controller) return;
    _activeVideoController?.removeListener(_onVideoUpdate);
    _activeVideoController = controller;
    _activeVideoController?.addListener(_onVideoUpdate);
    if (mounted) setState(() {});
  }

  void _onPageChanged(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      _isZoomed = false;
      if (_items[index].mediaType != 'video') {
        _setActiveVideoController(null);
      }
    });
  }

  void _toggleOverlay() {
    setState(() {
      _isOverlayVisible = !_isOverlayVisible;
    });
  }

  void _snapBack() {
    _dismissAnimation = Tween<double>(
      begin: _dragOffsetY,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _dismissAnimController,
      curve: Curves.easeOutBack,
    ));
    _dismissAnimController.forward(from: 0.0);
  }

  void _onDragOffsetYDelta(double delta) {
    setState(() {
      _dragOffsetY += delta;
      if (_dragOffsetY < 0) {
        _dragOffsetY = 0.0;
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
    if (_activeVideoController == null || !_activeVideoController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final duration = _activeVideoController!.value.duration;
    final position = _activeVideoController!.value.position;
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
                  _activeVideoController!.seekTo(Duration(milliseconds: value.toInt()));
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

  Widget _buildTopBar(double topPadding, bool showOverlays, double bgOpacity) {
    final currentItem = _items[_currentIndex];
    final isVideo = currentItem.mediaType == 'video';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        opacity: showOverlays ? bgOpacity : 0.0,
        child: IgnorePointer(
          ignoring: !showOverlays,
          child: Container(
            padding: EdgeInsets.only(
              top: topPadding + 6,
              left: 10,
              right: 14,
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
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context, true),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVideo ? Icons.videocam_rounded : Icons.photo_camera_rounded,
                            color: Colors.white70,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              currentItem.senderName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_items.length > 1) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_currentIndex + 1} of ${_items.length}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(double bottomPadding, bool showOverlays, double bgOpacity) {
    final currentItem = _items[_currentIndex];
    final bool isVideo = currentItem.mediaType == 'video';
    final bool hasCaption = currentItem.caption != null && currentItem.caption!.trim().isNotEmpty;

    if (!isVideo && !hasCaption) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        opacity: showOverlays ? bgOpacity : 0.0,
        child: IgnorePointer(
          ignoring: !showOverlays,
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: bottomPadding + 8,
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
                if (hasCaption) ...[
                  if (isVideo) const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      currentItem.caption!.trim(),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    final double dragProgress = (_dragOffsetY.abs() / (screenSize.height * 0.45)).clamp(0.0, 1.0);
    final double bgOpacity = (1.0 - dragProgress).clamp(0.0, 1.0);
    final double contentScale = (1.0 - (_dragOffsetY.abs() / (screenSize.height * 1.5))).clamp(0.82, 1.0);

    final currentTop = MediaQuery.paddingOf(context).top;
    if (currentTop > _cachedTopPadding) {
      _cachedTopPadding = currentTop;
    }
    final topPadding = _cachedTopPadding > 0 ? _cachedTopPadding : 28.0;

    final currentBottom = MediaQuery.paddingOf(context).bottom;
    if (currentBottom > _cachedBottomPadding) {
      _cachedBottomPadding = currentBottom;
    }
    final bottomPadding = _cachedBottomPadding > 0 ? _cachedBottomPadding : 16.0;

    final bool showOverlays = _isOverlayVisible && _dragOffsetY.abs() < 20;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: showOverlays ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: showOverlays ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            Navigator.pop(context, true);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black.withAlpha((bgOpacity * 255).toInt()),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Slide Viewport
              Center(
                child: Transform.translate(
                  offset: Offset(0, _dragOffsetY),
                  child: Transform.scale(
                    scale: contentScale,
                    child: PageView.builder(
                      controller: _pageController,
                      physics: (_isZoomed || _isDraggingDismiss)
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      itemCount: _items.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _MediaSlideItem(
                          key: ValueKey('media_${item.message?.id ?? index}'),
                          item: item,
                          isActive: index == _currentIndex,
                          showOverlays: showOverlays,
                          dragOffsetY: _dragOffsetY,
                          onZoomChanged: (zoomed) {
                            if (_isZoomed != zoomed) {
                              setState(() => _isZoomed = zoomed);
                            }
                          },
                          onDragOffsetYDelta: _onDragOffsetYDelta,
                          onDraggingDismissChanged: (dragging) {
                            setState(() => _isDraggingDismiss = dragging);
                          },
                          onResetDrag: () {
                            if (_dragOffsetY != 0) {
                              setState(() => _dragOffsetY = 0.0);
                            }
                          },
                          onDismiss: () => Navigator.pop(context, true),
                          onSnapBack: _snapBack,
                          onVideoControllerReady: (controller) {
                            if (index == _currentIndex) {
                              _setActiveVideoController(controller);
                            }
                          },
                          onToggleOverlay: _toggleOverlay,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Top Bar
              _buildTopBar(topPadding, showOverlays, bgOpacity),

              // Bottom Bar
              _buildBottomBar(bottomPadding, showOverlays, bgOpacity),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaSlideItem extends StatefulWidget {
  final EphemeralMediaItem item;
  final bool isActive;
  final bool showOverlays;
  final double dragOffsetY;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<double> onDragOffsetYDelta;
  final ValueChanged<bool> onDraggingDismissChanged;
  final VoidCallback onResetDrag;
  final VoidCallback onDismiss;
  final VoidCallback onSnapBack;
  final ValueChanged<VideoPlayerController?> onVideoControllerReady;
  final VoidCallback onToggleOverlay;

  const _MediaSlideItem({
    super.key,
    required this.item,
    required this.isActive,
    required this.showOverlays,
    required this.dragOffsetY,
    required this.onZoomChanged,
    required this.onDragOffsetYDelta,
    required this.onDraggingDismissChanged,
    required this.onResetDrag,
    required this.onDismiss,
    required this.onSnapBack,
    required this.onVideoControllerReady,
    required this.onToggleOverlay,
  });

  @override
  State<_MediaSlideItem> createState() => _MediaSlideItemState();
}

class _MediaSlideItemState extends State<_MediaSlideItem> with TickerProviderStateMixin {
  Uint8List? _mediaBytes;
  bool _isLoadingBytes = false;

  // Video state
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _isVideoInitialized = false;
  bool _isInitializingVideo = false;
  bool _isDisposed = false;

  // Photo Zoom state
  final TransformationController _transController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  bool _isZoomed = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _mediaBytes = widget.item.rawBytes;

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transController.value = _zoomAnimation!.value;
        }
      });

    _transController.addListener(_onTransformationChanged);

    if (_mediaBytes == null || _mediaBytes!.isEmpty) {
      _loadMediaBytes();
    } else if (widget.item.mediaType == 'video' && widget.isActive) {
      _initVideo();
    }
  }

  @override
  void didUpdateWidget(covariant _MediaSlideItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive != widget.isActive) {
      if (!widget.isActive) {
        // Pausing immediately when swiped away
        if (_videoController != null && _isVideoInitialized) {
          _videoController!.pause();
        }
        if (_isZoomed) {
          _transController.value = Matrix4.identity();
          _isZoomed = false;
          widget.onZoomChanged(false);
        }
      } else {
        // Became active slide
        if (widget.item.mediaType == 'video') {
          if (_isVideoInitialized && _videoController != null) {
            widget.onVideoControllerReady(_videoController);
            _videoController!.play();
          } else if (!_isInitializingVideo) {
            _initVideo();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _transController.removeListener(_onTransformationChanged);
    _transController.dispose();
    _zoomAnimController.dispose();

    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    if (!kIsWeb && _tempVideoFile != null && _tempVideoFile!.existsSync()) {
      if (_tempVideoFile!.path.contains('ephemeral_') || _tempVideoFile!.path.contains('temp_')) {
        try {
          _tempVideoFile!.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
      widget.onZoomChanged(zoomed);
    }
  }

  void _onVideoUpdate() {
    if (!mounted || _videoController == null || _isDisposed) return;
    setState(() {});
  }

  Future<void> _loadMediaBytes() async {
    if (_isLoadingBytes || _isDisposed) return;
    _isLoadingBytes = true;

    try {
      final connManager = context.read<ConnectionManager>();
      final mediaService = connManager.ephemeralMediaService;

      final cacheKey = widget.item.payload?.mediaKeyBase64.isNotEmpty == true
          ? widget.item.payload!.mediaKeyBase64
          : (widget.item.message?.id ?? '');

      // 1. RAM check
      var bytes = mediaService.getCachedMedia(cacheKey);
      if (bytes == null && widget.item.message != null) {
        bytes = mediaService.getCachedMedia(widget.item.message!.id);
      }
      if (bytes == null && widget.item.payload?.url.isNotEmpty == true) {
        bytes = mediaService.getCachedMedia(widget.item.payload!.url);
      }

      // 2. Disk check
      if (bytes == null && cacheKey.isNotEmpty) {
        bytes = await mediaService.getCachedMediaAsync(cacheKey);
      }
      if (bytes == null && widget.item.message != null) {
        bytes = await mediaService.getCachedMediaAsync(widget.item.message!.id);
      }

      // 3. Network download fallback
      if (bytes == null && widget.item.payload != null) {
        bytes = await mediaService.getOrDownloadMedia(
          widget.item.payload!,
          messageId: widget.item.message?.id,
        );
      }

      if (!_isDisposed && mounted && bytes != null && bytes.isNotEmpty) {
        setState(() {
          _mediaBytes = bytes;
          _isLoadingBytes = false;
        });
        if (widget.item.mediaType == 'video' && widget.isActive) {
          _initVideo();
        }
      } else {
        _isLoadingBytes = false;
      }
    } catch (_) {
      _isLoadingBytes = false;
    }
  }

  Future<void> _initVideo() async {
    if (_isDisposed || _isInitializingVideo || _isVideoInitialized) return;
    _isInitializingVideo = true;

    try {
      if (_mediaBytes == null || _mediaBytes!.isEmpty) {
        await _loadMediaBytes();
      }
      if (_mediaBytes == null || _mediaBytes!.isEmpty || _isDisposed) {
        _isInitializingVideo = false;
        return;
      }

      if (kIsWeb) {
        final uri = Uri.dataFromBytes(_mediaBytes!, mimeType: 'video/mp4');
        _videoController = VideoPlayerController.networkUrl(uri);
      } else {
        final cachedFile = await VideoThumbnailManager.getOrCreateVideoFile(_mediaBytes!);
        if (cachedFile != null && cachedFile.existsSync()) {
          _tempVideoFile = cachedFile;
          _videoController = VideoPlayerController.file(cachedFile);
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempPath =
              '${tempDir.path}/ephemeral_${DateTime.now().millisecondsSinceEpoch}_${widget.item.message?.id ?? ""}.mp4';
          _tempVideoFile = File(tempPath);
          await _tempVideoFile!.writeAsBytes(_mediaBytes!, flush: true);
          _videoController = VideoPlayerController.file(_tempVideoFile!);
        }
      }

      if (_isDisposed) {
        _videoController?.dispose();
        return;
      }

      await _videoController!.initialize();
      if (_isDisposed) {
        _videoController?.dispose();
        return;
      }

      _videoController!.setLooping(false);
      _videoController!.addListener(_onVideoUpdate);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isInitializingVideo = false;
        });

        if (widget.isActive) {
          widget.onVideoControllerReady(_videoController);
          _videoController!.play();
        }
      }
    } catch (e) {
      _isInitializingVideo = false;
      debugPrint('[EphemeralMediaViewer] Error initializing video: $e');
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;
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

  void _handleDoubleTap() {
    final currentScale = _transController.value.getMaxScaleOnAxis();
    final targetMatrix = Matrix4.identity();

    if (currentScale < 1.5) {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      targetMatrix
        ..setTranslationRaw(-position.dx * 1.5, -position.dy * 1.5, 0.0)
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }

    _zoomAnimation = Matrix4Tween(
      begin: _transController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOutCubic,
    ));

    _zoomAnimController.forward(from: 0.0);
  }

  // --- Photo Gestures ---
  void _onPhotoInteractionStart(ScaleStartDetails details) {
    _pointerCount = details.pointerCount;
    if (_pointerCount > 1) {
      widget.onDraggingDismissChanged(false);
      if (widget.dragOffsetY != 0) {
        widget.onResetDrag();
      }
    }
  }

  void _onPhotoInteractionUpdate(ScaleUpdateDetails details) {
    _pointerCount = details.pointerCount;
    final scale = _transController.value.getMaxScaleOnAxis();

    if (_pointerCount > 1 || scale > 1.05) {
      if (widget.dragOffsetY != 0) {
        widget.onResetDrag();
        widget.onDraggingDismissChanged(false);
      }
      return;
    }

    // Single finger downward drag at 1.0x scale -> Dismiss
    final dy = details.focalPointDelta.dy;
    if (dy > 0 || widget.dragOffsetY > 0) {
      widget.onDraggingDismissChanged(true);
      widget.onDragOffsetYDelta(dy);
    }
  }

  void _onPhotoInteractionEnd(ScaleEndDetails details) {
    final scale = _transController.value.getMaxScaleOnAxis();
    if (widget.dragOffsetY > 0) {
      widget.onDraggingDismissChanged(false);
      final velocity = details.velocity.pixelsPerSecond.dy;
      if (widget.dragOffsetY > 110 || velocity > 400) {
        widget.onDismiss();
      } else {
        widget.onSnapBack();
      }
    } else if (scale <= 1.05 && !_transController.value.isIdentity()) {
      _zoomAnimation = Matrix4Tween(
        begin: _transController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(
        parent: _zoomAnimController,
        curve: Curves.easeOutCubic,
      ));
      _zoomAnimController.forward(from: 0.0);
    }
  }

  // --- Video Gestures ---
  void _onVideoVerticalDragStart(DragStartDetails details) {
    widget.onDraggingDismissChanged(true);
  }

  void _onVideoVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0.0;
    widget.onDragOffsetYDelta(dy);
  }

  void _onVideoVerticalDragEnd(DragEndDetails details) {
    widget.onDraggingDismissChanged(false);
    final velocity = details.primaryVelocity ?? 0.0;
    if (widget.dragOffsetY > 110 || velocity > 400) {
      widget.onDismiss();
    } else {
      widget.onSnapBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = widget.item.mediaType == 'video';
    final screenSize = MediaQuery.of(context).size;

    if (isVideo) {
      final bool isPlaying = _videoController != null && _videoController!.value.isPlaying;
      final persistentThumb = VideoThumbnailManager.getPersistentThumbnail(
        widget.item.message?.id ?? '',
        _mediaBytes,
      );

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggleOverlay,
        onVerticalDragStart: _onVideoVerticalDragStart,
        onVerticalDragUpdate: _onVideoVerticalDragUpdate,
        onVerticalDragEnd: _onVideoVerticalDragEnd,
        child: Center(
          child: _isVideoInitialized && _videoController != null
              ? AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        opacity: (widget.showOverlays || !isPlaying) ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: (!widget.showOverlays && isPlaying),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(40),
                              onTap: _togglePlayPause,
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
              : (persistentThumb != null && persistentThumb.isNotEmpty
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          persistentThumb,
                          fit: BoxFit.contain,
                          width: screenSize.width,
                        ),
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(140),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )),
        ),
      );
    }

    // Photo rendering with pinch zoom and double tap
    return GestureDetector(
      onTap: widget.onToggleOverlay,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transController,
        minScale: 1.0,
        maxScale: 5.0,
        panEnabled: _isZoomed,
        scaleEnabled: true,
        boundaryMargin: EdgeInsets.zero,
        onInteractionStart: _onPhotoInteractionStart,
        onInteractionUpdate: _onPhotoInteractionUpdate,
        onInteractionEnd: _onPhotoInteractionEnd,
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: Center(
            child: _mediaBytes != null && _mediaBytes!.isNotEmpty
                ? Image.memory(
                    _mediaBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Unable to display image',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
