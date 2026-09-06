import 'dart:math' as math;
import 'package:flutter/material.dart';

/// WhatsApp-inspired subtle doodle background wallpaper.
/// Draws an organic, low-opacity pattern of privacy, chat, and lifestyle icons.
class ChatDoodlePainter extends CustomPainter {
  const ChatDoodlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withAlpha(12) // ~4.7% opacity for subtle texture
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withAlpha(8)
      ..style = PaintingStyle.fill;

    const double tileSize = 140.0;
    final int cols = (size.width / tileSize).ceil() + 1;
    final int rows = (size.height / tileSize).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      // Stagger odd rows for a brick-like organic pattern
      final double xOffset = (r % 2 == 1) ? tileSize / 2 : 0.0;
      final double y = r * tileSize;

      for (int c = -1; c < cols; c++) {
        final double x = c * tileSize + xOffset;
        final int variant = (r * 3 + c).abs() % 3;

        _drawTile(canvas, Offset(x, y), variant, strokePaint, fillPaint);
      }
    }
  }

  void _drawTile(Canvas canvas, Offset origin, int variant, Paint stroke, Paint fill) {
    if (variant == 0) {
      _drawSpeechBubble(canvas, origin + const Offset(30, 25), stroke);
      _drawLock(canvas, origin + const Offset(105, 30), stroke, fill);
      _drawStar(canvas, origin + const Offset(70, 70), stroke, fill);
      _drawCoffeeCup(canvas, origin + const Offset(25, 110), stroke);
      _drawPaperPlane(canvas, origin + const Offset(110, 105), stroke);
    } else if (variant == 1) {
      _drawHeart(canvas, origin + const Offset(30, 30), stroke, fill);
      _drawMusicNote(canvas, origin + const Offset(110, 25), stroke, fill);
      _drawSmiley(canvas, origin + const Offset(70, 70), stroke);
      _drawLeaf(canvas, origin + const Offset(28, 110), stroke);
      _drawClock(canvas, origin + const Offset(110, 110), stroke);
    } else {
      _drawEnvelope(canvas, origin + const Offset(30, 28), stroke);
      _drawHeadphones(canvas, origin + const Offset(110, 30), stroke);
      _drawLock(canvas, origin + const Offset(70, 70), stroke, fill);
      _drawStar(canvas, origin + const Offset(25, 110), stroke, fill);
      _drawSpeechBubble(canvas, origin + const Offset(108, 112), stroke);
    }

    // Add tiny decorative floating dots around icons
    canvas.drawCircle(origin + const Offset(68, 25), 1.2, fill);
    canvas.drawCircle(origin + const Offset(18, 70), 1.0, fill);
    canvas.drawCircle(origin + const Offset(125, 68), 1.2, fill);
    canvas.drawCircle(origin + const Offset(68, 118), 1.0, fill);
  }

  void _drawSpeechBubble(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: 17, height: 12);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(rrect, paint);

    final path = Path()
      ..moveTo(center.dx - 4, center.dy + 6)
      ..lineTo(center.dx - 7, center.dy + 9)
      ..lineTo(center.dx - 1, center.dy + 6);
    canvas.drawPath(path, paint);
  }

  void _drawLock(Canvas canvas, Offset center, Paint stroke, Paint fill) {
    final bodyRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 2.5),
      width: 12,
      height: 9.5,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(2)), stroke);

    final shackleRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 2),
      width: 7.5,
      height: 7,
    );
    canvas.drawArc(shackleRect, math.pi, math.pi, false, stroke);

    // Keyhole
    canvas.drawCircle(Offset(center.dx, center.dy + 1.5), 1.0, fill);
    canvas.drawLine(
      Offset(center.dx, center.dy + 1.5),
      Offset(center.dx, center.dy + 4.5),
      stroke,
    );
  }

  void _drawPaperPlane(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx + 8, center.dy - 6)
      ..lineTo(center.dx - 8, center.dy - 1)
      ..lineTo(center.dx - 2, center.dy + 2)
      ..lineTo(center.dx + 1, center.dy + 7)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(center.dx + 8, center.dy - 6),
      Offset(center.dx - 2, center.dy + 2),
      paint,
    );
  }

  void _drawCoffeeCup(Canvas canvas, Offset center, Paint paint) {
    final bodyRect = Rect.fromCenter(center: center, width: 12, height: 10);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(2)), paint);

    // Handle
    final handleRect = Rect.fromCenter(
      center: Offset(center.dx + 7.5, center.dy),
      width: 5,
      height: 6,
    );
    canvas.drawArc(handleRect, -math.pi / 2, math.pi, false, paint);

    // Steam wavy line
    final steam = Path()
      ..moveTo(center.dx - 2, center.dy - 7)
      ..quadraticBezierTo(center.dx, center.dy - 9, center.dx - 1, center.dy - 11);
    canvas.drawPath(steam, paint);
  }

  void _drawMusicNote(Canvas canvas, Offset center, Paint stroke, Paint fill) {
    // Left note head
    canvas.drawCircle(Offset(center.dx - 4.5, center.dy + 4), 2.2, fill);
    canvas.drawCircle(Offset(center.dx - 4.5, center.dy + 4), 2.2, stroke);

    // Right note head
    canvas.drawCircle(Offset(center.dx + 4.5, center.dy + 2), 2.2, fill);
    canvas.drawCircle(Offset(center.dx + 4.5, center.dy + 2), 2.2, stroke);

    // Stems & Beam
    canvas.drawLine(Offset(center.dx - 2.5, center.dy + 4), Offset(center.dx - 2.5, center.dy - 5), stroke);
    canvas.drawLine(Offset(center.dx + 6.5, center.dy + 2), Offset(center.dx + 6.5, center.dy - 7), stroke);
    canvas.drawLine(Offset(center.dx - 2.5, center.dy - 5), Offset(center.dx + 6.5, center.dy - 7), stroke);
  }

  void _drawHeart(Canvas canvas, Offset center, Paint stroke, Paint fill) {
    final path = Path();
    path.moveTo(center.dx, center.dy + 5);
    path.cubicTo(
      center.dx - 7, center.dy - 1,
      center.dx - 7, center.dy - 6,
      center.dx, center.dy - 3,
    );
    path.cubicTo(
      center.dx + 7, center.dy - 6,
      center.dx + 7, center.dy - 1,
      center.dx, center.dy + 5,
    );
    canvas.drawPath(path, stroke);
  }

  void _drawSmiley(Canvas canvas, Offset center, Paint paint) {
    canvas.drawCircle(center, 7.5, paint);
    // Eyes
    canvas.drawCircle(Offset(center.dx - 2.5, center.dy - 2), 0.9, paint);
    canvas.drawCircle(Offset(center.dx + 2.5, center.dy - 2), 0.9, paint);
    // Smile arc
    final smileRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 0.5),
      width: 7.5,
      height: 6,
    );
    canvas.drawArc(smileRect, 0.2 * math.pi, 0.6 * math.pi, false, paint);
  }

  void _drawClock(Canvas canvas, Offset center, Paint paint) {
    canvas.drawCircle(center, 7.5, paint);
    // Hands
    canvas.drawLine(center, Offset(center.dx, center.dy - 4.5), paint);
    canvas.drawLine(center, Offset(center.dx + 3.5, center.dy), paint);
  }

  void _drawStar(Canvas canvas, Offset center, Paint stroke, Paint fill) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 7)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + 7, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + 7)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - 7, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - 7)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _drawLeaf(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 6, center.dy + 6)
      ..quadraticBezierTo(center.dx - 6, center.dy - 6, center.dx + 6, center.dy - 6)
      ..quadraticBezierTo(center.dx + 6, center.dy + 6, center.dx - 6, center.dy + 6);
    canvas.drawPath(path, paint);
    canvas.drawLine(Offset(center.dx - 4, center.dy + 4), Offset(center.dx + 4, center.dy - 4), paint);
  }

  void _drawEnvelope(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: 16, height: 11);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    // Envelope fold
    final path = Path()
      ..moveTo(center.dx - 8, center.dy - 5.5)
      ..lineTo(center.dx, center.dy + 0.5)
      ..lineTo(center.dx + 8, center.dy - 5.5);
    canvas.drawPath(path, paint);
  }

  void _drawHeadphones(Canvas canvas, Offset center, Paint paint) {
    final bandRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 1),
      width: 12,
      height: 12,
    );
    canvas.drawArc(bandRect, math.pi, math.pi, false, paint);

    // Left ear cup
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx - 6, center.dy + 2), width: 3, height: 6),
        const Radius.circular(1.5),
      ),
      paint,
    );

    // Right ear cup
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx + 6, center.dy + 2), width: 3, height: 6),
        const Radius.circular(1.5),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
