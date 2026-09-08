import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme.dart';

/// WhatsApp-style slide-to-reply gesture wrapper.
/// Supports swiping right on both sent and received message bubbles.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  static const double _triggerThreshold = 36.0;
  static const double _maxDragOffset = 58.0;
  bool _hasHapticTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    // Only allow sliding right (positive values)
    final newOffset = (_dragOffset + details.delta.dx).clamp(0.0, _maxDragOffset);
    if (newOffset != _dragOffset) {
      if (newOffset >= _triggerThreshold && !_hasHapticTriggered) {
        _hasHapticTriggered = true;
        HapticFeedback.lightImpact();
      } else if (newOffset < _triggerThreshold) {
        _hasHapticTriggered = false;
      }
      setState(() {
        _dragOffset = newOffset;
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    if (_dragOffset >= _triggerThreshold) {
      widget.onReply();
    }
    _animateBack();
  }

  void _onHorizontalDragCancel() {
    _animateBack();
  }

  void _animateBack() {
    _hasHapticTriggered = false;
    _animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_dragOffset / _triggerThreshold).clamp(0.0, 1.0);
    final iconScale = progress;
    final iconOpacity = progress;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          // WhatsApp reply circular icon indicator on left
          if (_dragOffset > 0)
            Positioned(
              left: 12,
              child: Opacity(
                opacity: iconOpacity,
                child: Transform.scale(
                  scale: iconScale,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2C34),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(50),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      color: MineTheme.accentGreen,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          // Message bubble sliding with touch
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
