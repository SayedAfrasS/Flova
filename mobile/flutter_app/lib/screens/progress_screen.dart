/// WORKFLOW OF THIS FILE:
/// 1. Shows live progress with a centered ring and centered stats.
/// 2. Seeds transferred bytes from transport counters on mount (resume-safe).
/// 3. Completion in BOTH directions now waits for the done event, which only
///    fires after the receiver's hash verdict (verify-result) arrives, so the
///    Complete screen always shows the true result.
/// 4. At 100% the subtitle shows "Checking file..." until that verdict lands.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import '../services/transport.dart';
import 'complete_screen.dart';

class ProgressScreen extends StatefulWidget {
  final TransferInfo info;
  final TransportClient transport;
  const ProgressScreen({super.key, required this.info, required this.transport});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  double _transferred = 0;
  double _speed = 0;
  int _lastUpdateMs = 0;
  double _lastBytes = 0;
  bool _isDone = false;
  StreamSubscription<int>? _sub;
  StreamSubscription<FileEvent>? _fileSub;

  @override
  void initState() {
    super.initState();
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    _transferred = widget.info.sending
        ? widget.transport.sentBytes.toDouble()
        : widget.transport.receivedBytes.toDouble();
    _lastBytes = _transferred;

    // ring + speed only; completion comes from the done event below
    _sub = widget.transport.progressStream.listen((bytes) {
      if (_isDone) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - _lastUpdateMs) / 1000.0;
      setState(() {
        _transferred += bytes;
        if (dt > 0.5) {
          _speed = (_transferred - _lastBytes) / dt;
          _lastUpdateMs = now;
          _lastBytes = _transferred;
        }
      });
    });

    _fileSub = widget.transport.fileEventStream.listen((event) {
      if (event.isDone && event.sending == widget.info.sending) _complete(event.ok);
    });
  }

  void _complete(bool verified) {
    if (_isDone) return;
    _isDone = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CompleteScreen(
              info: TransferInfo(
                name: widget.info.name,
                size: widget.info.size,
                bytes: widget.info.bytes,
                sending: widget.info.sending,
                verified: verified,
              ),
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() { _sub?.cancel(); _fileSub?.cancel(); super.dispose(); }

  String _formatBytes(double bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pct = widget.info.bytes > 0 ? math.min(1.0, _transferred / widget.info.bytes) : 0.0;
    final checking = pct >= 1.0 && !_isDone;
    final secondsLeft = _speed > 0 ? math.max(1, ((widget.info.bytes - _transferred) / _speed).round()) : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas, surfaceTintColor: Colors.transparent,
        title: Text(widget.info.sending ? 'Sending file' : 'Receiving file',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.description_outlined, size: 40, color: FlovaTokens.accent),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(widget.info.name, style: text.headlineMedium, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 32),
                Center(
                  child: SizedBox(
                    width: 200, height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(size: const Size(200, 200), painter: _RingPainter(pct)),
                        Text('${(pct * 100).round()}%',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('${_formatBytes(_transferred)} of ${_formatBytes(widget.info.bytes)}',
                    style: text.bodyLarge?.copyWith(color: FlovaTokens.ink), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(_speed > 0 && !checking ? '${_formatBytes(_speed)}/s' : '',
                    style: text.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Text(
                  checking ? 'Checking file...' : (_speed > 0 ? 'About $secondsLeft seconds left' : ''),
                  style: text.bodyMedium?.copyWith(color: FlovaTokens.ink3), textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = FlovaTokens.line;
    canvas.drawCircle(center, radius, track);
    final bar = Paint()..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round..color = FlovaTokens.accent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * progress, false, bar);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}