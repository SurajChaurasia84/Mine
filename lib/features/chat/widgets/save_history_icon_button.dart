import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme.dart';

/// A custom icon button matching the AppBar menu icon style.
/// - In both states, uses the same color as the AppBar menu icon (MineTheme.textLight).
/// - Unticked (Default): Dashed circular bubble with tail (no tick, no center dot, no outer box).
/// - Ticked: Dashed circular bubble with tail + tick mark inside.
class SaveHistoryIconButton extends StatelessWidget {
  final bool isSaved;
  final VoidCallback onTap;

  const SaveHistoryIconButton({
    super.key,
    required this.isSaved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isSaved
          ? 'Save Chat History: ON (Messages saved to DB)'
          : 'Temporary Mode: ON (No history, destroys on exit)',
      icon: CustomPaint(
        size: const Size(24, 24),
        painter: _HistoryTogglePainter(
          isSaved: isSaved,
          color: MineTheme.textLight,
        ),
      ),
      onPressed: onTap,
    );
  }
}

class _HistoryTogglePainter extends CustomPainter {
  final bool isSaved;
  final Color color;

  _HistoryTogglePainter({
    required this.isSaved,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2.0;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;

    // Draw segmented/dashed circular chat bubble ring (3 segments)
    const double startAngle1 = -math.pi / 2 + 0.35;
    const double sweepAngle1 = 1.6;

    const double startAngle2 = startAngle1 + sweepAngle1 + 0.45;
    const double sweepAngle2 = 1.6;

    const double startAngle3 = startAngle2 + sweepAngle2 + 0.45;
    const double sweepAngle3 = 1.4;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle1, sweepAngle1, false, ringPaint);
    canvas.drawArc(rect, startAngle2, sweepAngle2, false, ringPaint);
    canvas.drawArc(rect, startAngle3, sweepAngle3, false, ringPaint);

    // Draw speech tail notch at bottom left
    final tailPath = Path();
    final tailOrigin = Offset(center.dx - radius * 0.72, center.dy + radius * 0.70);
    tailPath.moveTo(tailOrigin.dx, tailOrigin.dy);
    tailPath.lineTo(tailOrigin.dx - 2.8, tailOrigin.dy + 3.2);
    tailPath.lineTo(tailOrigin.dx + 2.8, tailOrigin.dy + 1.2);
    canvas.drawPath(tailPath, ringPaint);

    // Draw checkmark inside ONLY if isSaved is true (when ticked)
    if (isSaved) {
      final tickPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final tickPath = Path();
      tickPath.moveTo(center.dx - 4.5, center.dy + 0.2);
      tickPath.lineTo(center.dx - 1.0, center.dy + 3.8);
      tickPath.lineTo(center.dx + 4.8, center.dy - 3.5);

      canvas.drawPath(tickPath, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryTogglePainter oldDelegate) {
    return oldDelegate.isSaved != isSaved || oldDelegate.color != color;
  }
}
