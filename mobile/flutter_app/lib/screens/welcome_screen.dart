/// WORKFLOW OF THIS FILE:
/// 1. First screen of the mobile app (welcome).
/// 2. "Scan laptop code" opens the Scanner screen.
/// 3. "How it works" is a quiet placeholder for now.
/// 4. The line art at the bottom is drawn by _LineArtPainter.
///
/// CLASSES / FUNCTIONS:
///  - WelcomeScreen   : builds the welcome layout.
///  - _LineArtPainter : draws phone + laptop + connecting curve.
import 'package:flutter/material.dart';
import '../core/flova_mark.dart';
import '../core/tokens.dart';
import 'scanner_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const FlovaMark(),
                const SizedBox(width: 8),
                Text('flova', style: text.headlineMedium?.copyWith(letterSpacing: -0.3)),
              ]),
              const Spacer(),
              Text('Transfer files easily', style: text.headlineLarge),
              const SizedBox(height: 8),
              Text('Connect your laptop and start sharing.', style: text.bodyLarge),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ScannerScreen(),
                )),
                child: const Text('Scan laptop code'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {},
                child: const Text('How it works', style: TextStyle(color: FlovaTokens.accent)),
              ),
              const Spacer(),
              SizedBox(height: 110, child: CustomPaint(painter: _LineArtPainter(), size: Size.infinite)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = FlovaTokens.accent.withValues(alpha: 0.4);
    final w = size.width, h = size.height;

    // phone
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.34, w * 0.09, h * 0.44), const Radius.circular(6)),
      stroke,
    );
    // laptop: screen + base line
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.50, h * 0.26, w * 0.28, h * 0.40), const Radius.circular(6)),
      stroke,
    );
    canvas.drawLine(Offset(w * 0.45, h * 0.74), Offset(w * 0.83, h * 0.74), stroke);
    // connecting flow
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.29, h * 0.56)
        ..cubicTo(w * 0.35, h * 0.48, w * 0.41, h * 0.64, w * 0.50, h * 0.56),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}