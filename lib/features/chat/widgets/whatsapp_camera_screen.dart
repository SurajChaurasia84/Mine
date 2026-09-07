import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../app/theme.dart';

class CapturedMedia {
  final Uint8List rawBytes;
  final String mediaType; // 'photo' | 'video'

  CapturedMedia({required this.rawBytes, required this.mediaType});
}

class WhatsAppCameraScreen extends StatefulWidget {
  const WhatsAppCameraScreen({super.key});

  @override
  State<WhatsAppCameraScreen> createState() => _WhatsAppCameraScreenState();
}

class _WhatsAppCameraScreenState extends State<WhatsAppCameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIdx = 0;
  bool _isCameraInitialized = false;
  bool _isRecordingVideo = false;
  FlashMode _currentFlashMode = FlashMode.off;
  String _activeMode = 'photo'; // 'video' | 'photo'
  Timer? _videoTimer;
  int _recordedSeconds = 0;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCameraController(_cameras[_selectedCameraIdx]);
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        await _initCameraController(_cameras[_selectedCameraIdx]);
      } else {
        _fallbackToSystemCamera();
      }
    } catch (_) {
      _fallbackToSystemCamera();
    }
  }

  Future<void> _initCameraController(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = controller;

    try {
      await controller.initialize();
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _currentZoom = 1.0;
      await controller.setFlashMode(_currentFlashMode);

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (_) {
      if (mounted) {
        _fallbackToSystemCamera();
      }
    }
  }

  Future<void> _fallbackToSystemCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (!mounted) return;
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        Navigator.pop(context, CapturedMedia(rawBytes: bytes, mediaType: 'photo'));
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    FlashMode newMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        newMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        newMode = FlashMode.always;
        break;
      case FlashMode.always:
      case FlashMode.torch:
        newMode = FlashMode.off;
        break;
    }
    try {
      await _controller!.setFlashMode(newMode);
      setState(() {
        _currentFlashMode = newMode;
      });
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) return;
    _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    setState(() {
      _isCameraInitialized = false;
    });
    await _initCameraController(_cameras[_selectedCameraIdx]);
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final XFile file = await _controller!.takePicture();
      Uint8List bytes = await file.readAsBytes();

      // If captured using Front/Selfie camera, flip horizontally to preserve WYSIWYG preview orientation
      final isFrontCamera = _cameras.isNotEmpty &&
          _selectedCameraIdx < _cameras.length &&
          _cameras[_selectedCameraIdx].lensDirection == CameraLensDirection.front;

      if (isFrontCamera) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final oriented = img.bakeOrientation(decoded);
            final flipped = img.flipHorizontal(oriented);
            bytes = Uint8List.fromList(img.encodeJpg(flipped, quality: 90));
          }
        } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context, CapturedMedia(rawBytes: bytes, mediaType: 'photo'));
      }
    } catch (_) {}
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecordingVideo = true;
        _recordedSeconds = 0;
      });
      _videoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordedSeconds++;
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;

    _videoTimer?.cancel();
    try {
      final XFile file = await _controller!.stopVideoRecording();
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
        Navigator.pop(context, CapturedMedia(rawBytes: bytes, mediaType: 'video'));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickMedia(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
            file.path.toLowerCase().endsWith('.mov') ||
            file.path.toLowerCase().endsWith('.mkv') ||
            file.path.toLowerCase().endsWith('.webm') ||
            file.path.toLowerCase().endsWith('.avi');
        if (!mounted) return;
        Navigator.pop(
          context,
          CapturedMedia(rawBytes: bytes, mediaType: isVideo ? 'video' : 'photo'),
        );
      }
    } catch (_) {}
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Viewfinder with pinch to zoom
          if (_isCameraInitialized && _controller != null)
            GestureDetector(
              onScaleStart: (details) {
                _baseZoom = _currentZoom;
              },
              onScaleUpdate: (details) async {
                final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom.clamp(1.0, 8.0));
                if (newZoom != _currentZoom) {
                  _currentZoom = newZoom;
                  await _controller?.setZoomLevel(newZoom);
                }
              },
              child: Center(
                child: CameraPreview(_controller!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: MineTheme.accentGreen),
            ),

          // 2. Top Bar (Close & Flash)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    // Recording Timer (when recording video)
                    if (_isRecordingVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(200),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                            const SizedBox(width: 6),
                            Text(
                              _formatTimer(_recordedSeconds),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    // Flash Toggle
                    IconButton(
                      icon: Icon(_getFlashIcon(), color: Colors.white, size: 26),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Controls Area (Gallery, Shutter, Switch, Mode Selector)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Action buttons row (Gallery, Shutter, Flip)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Gallery Button
                        GestureDetector(
                          onTap: _pickFromGallery,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),

                        // Shutter Button (Capture / Record)
                        GestureDetector(
                          onTap: () {
                            if (_activeMode == 'photo') {
                              _capturePhoto();
                            } else {
                              if (_isRecordingVideo) {
                                _stopVideoRecording();
                              } else {
                                _startVideoRecording();
                              }
                            }
                          },
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isRecordingVideo ? Colors.red : Colors.white,
                                width: 4,
                              ),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _isRecordingVideo
                                    ? Colors.red
                                    : (_activeMode == 'video' ? Colors.redAccent : Colors.white),
                                shape: _isRecordingVideo ? BoxShape.rectangle : BoxShape.circle,
                                borderRadius: _isRecordingVideo ? BorderRadius.circular(8) : null,
                              ),
                            ),
                          ),
                        ),

                        // Switch Camera Button
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flip_camera_ios_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Mode Selector Pill: [ Video ] [ Photo ] (matching WhatsApp)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(150),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Video Mode Pill
                        GestureDetector(
                          onTap: () {
                            if (!_isRecordingVideo) {
                              setState(() {
                                _activeMode = 'video';
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: _activeMode == 'video'
                                  ? Colors.white.withAlpha(40)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Video',
                              style: TextStyle(
                                color: _activeMode == 'video' ? Colors.white : Colors.white60,
                                fontSize: 13,
                                fontWeight: _activeMode == 'video' ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),

                        // Photo Mode Pill
                        GestureDetector(
                          onTap: () {
                            if (!_isRecordingVideo) {
                              setState(() {
                                _activeMode = 'photo';
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: _activeMode == 'photo'
                                  ? Colors.white.withAlpha(40)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Photo',
                              style: TextStyle(
                                color: _activeMode == 'photo' ? Colors.white : Colors.white60,
                                fontSize: 13,
                                fontWeight: _activeMode == 'photo' ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
