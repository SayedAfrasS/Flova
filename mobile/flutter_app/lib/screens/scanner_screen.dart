/// WORKFLOW OF THIS FILE:
/// 1. This screen looks like the camera scanner from the design.
/// 2. In Phase 2 the camera is simulated with a dark background.
///    The real camera (mobile_scanner) is connected in Phase 4.
/// 3. The flashlight button toggles its icon on and off (visual only).
/// 4. The small "Simulate successful scan" text at the bottom acts
///    like a found QR code and moves the app to the Home screen.
///
/// CLASSES / FUNCTIONS:
///  - ScannerScreen   : owns the flashlight on/off state.
///  - _CornersPainter : draws the four blue rounded corner brackets.
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import 'home_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _flashOn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1524),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // title block
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Text('Scan laptop code',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('Point your camera at the QR code shown on your laptop.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ),
            const Spacer(),
            // scan frame with blue corners
            SizedBox(
              width: 260,
              height: 260,
              child: CustomPaint(painter: _CornersPainter()),
            ),
            const Spacer(),
            // flashlight toggle
            IconButton(
              tooltip: 'Flashlight',
              onPressed: () => setState(() => _flashOn = !_flashOn),
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color: _flashOn ? Colors.white : Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            // dev-only action, removed in Phase 4 when real scanning lands
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              child: Text('Simulate successful scan',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF60A5FA);
    const r = 24.0; // corner radius

    // top-left corner
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), pi, pi / 2, false, paint);
    // top-right corner
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2), 1.5 * pi, pi / 2, false, paint);
    // bottom-right corner
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, size.height - r * 2, r * 2, r * 2), 0, pi / 2, false, paint);
    // bottom-left corner
    canvas.drawArc(Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2), 0.5 * pi, pi / 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}