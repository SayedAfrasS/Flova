import 'package:flutter/material.dart';
import 'tokens.dart';

class FlovaMark extends StatelessWidget {
  const FlovaMark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.125
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [FlovaTokens.accent, FlovaTokens.violet],
      ).createShader(rect);

    final center = rect.center;
    final radius = size.width / 2 - paint.strokeWidth / 2;
    // two opposing quarter arcs = flows meeting
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3.14159, 1.5708, false, paint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 0, 1.5708, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}