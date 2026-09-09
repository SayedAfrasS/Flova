import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import 'complete_screen.dart';

class ProgressScreen extends StatefulWidget {
  final TransferInfo info;
  const ProgressScreen({super.key, required this.info});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with SingleTickerProviderStateMixin {
  double _progress = 0;
  double _speed = 45;
  bool _paused = false;
  bool _done = false;
  Timer? _timer;
  final math.Random _random = math.Random();

  late final AnimationController _dot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_paused || _done) return;
      setState(() {
        _progress = math.min(1.0, _progress + 0.004 + _random.nextDouble() * 0.004);
        _speed = 38 + _random.nextDouble() * 14;
      });
      if (_progress >= 1.0 && !_done) {
        _done = true;
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => CompleteScreen(info: widget.info)),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dot.dispose();
    super.dispose();
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _dot.stop();
      } else {
        _dot.repeat();
      }
    });
  }

  String _fmt(double bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final transferred = widget.info.bytes * _progress;
    final secondsLeft =
        math.max(1, ((widget.info.bytes - transferred) / (_speed * 1024 * 1024)).round());

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.info.sending ? 'Sending file' : 'Receiving file',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 40, color: FlovaTokens.accent),
            const SizedBox(height: 8),
            Text(widget.info.name, style: text.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(widget.info.size, style: text.bodyMedium),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(size: const Size(200, 200), painter: _RingPainter(_progress)),
                  Text('${(_progress * 100).round()}%',
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 180,
              height: 16,
              child: AnimatedBuilder(
                animation: _dot,
                builder: (context, _) {
                  final t = _dot.value;
                  final opacity = t < 0.12 ? t / 0.12 : (t > 0.88 ? (1 - t) / 0.12 : 1.0);
                  return Stack(
                    children: [
                      Positioned(top: 7, left: 0, right: 0, child: Container(height: 2, color: FlovaTokens.line)),
                      Positioned(
                        top: 4,
                        left: t * 172,
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: FlovaTokens.accent, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('${_fmt(transferred)} of ${_fmt(widget.info.bytes)}',
                style: text.bodyLarge?.copyWith(color: FlovaTokens.ink)),
            const SizedBox(height: 4),
            Text(_paused ? 'Paused' : '${_speed.round()} MB/s', style: text.bodyMedium),
            const SizedBox(height: 2),
            Text(_paused ? 'Transfer paused' : 'About $secondsLeft seconds left',
                style: text.bodyMedium?.copyWith(color: FlovaTokens.ink3)),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: _togglePause, child: Text(_paused ? 'Resume' : 'Pause'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(color: FlovaTokens.ink2)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = FlovaTokens.line;
    canvas.drawCircle(center, radius, track);
    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = FlovaTokens.accent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * progress, false, bar);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}