/// WORKFLOW OF THIS FILE:
/// 1. Shows live progress for the active file with a centered ring and stats.
/// 2. QUEUE HEADER pill shows "File N of M" for multi-file transfers.
/// 3. Resets per file on three signals:
///    - queueNext event  : receiver side, next queued file was auto-accepted.
///    - accepted state   : sender side, next queued file got its file-accept.
///    - isOffer event    : receiver side, first file of a new batch.
/// 4. Navigates to Complete only after the LAST file's done event.
/// 5. At 100% shows "Checking file..." until the verify verdict arrives.
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
  String _currentName = '';
  double _currentTotal = 0;
  int _queueIndex = 0;
  int _queueTotal = 1;
  StreamSubscription<int>? _sub;
  StreamSubscription<FileEvent>? _fileSub;
  StreamSubscription<SendState>? _sendSub;

  @override
  void initState() {
    super.initState();
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    _transferred = widget.info.sending
        ? widget.transport.sentBytes.toDouble()
        : widget.transport.receivedBytes.toDouble();
    _lastBytes = _transferred;
    _currentName = widget.info.name;
    _currentTotal = widget.info.bytes;

    // ring + speed updates
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

    // receiver side: queueNext resets for each auto-accepted file;
    // isDone on the last file completes the whole batch
    _fileSub = widget.transport.fileEventStream.listen((event) {
      if (!mounted) return;
      if (event.queueNext && !widget.info.sending) {
        setState(() {
          _transferred = 0;
          _lastBytes = 0;
          _speed = 0;
          _currentName = event.name;
          _currentTotal = event.size.toDouble();
          _queueIndex = event.queueIndex;
          _queueTotal = event.queueTotal;
          _isDone = false;
        });
      } else if (event.isOffer && !widget.info.sending) {
        setState(() {
          _transferred = 0;
          _lastBytes = 0;
          _speed = 0;
          _currentName = event.name;
          _currentTotal = event.size.toDouble();
          _queueIndex = event.queueIndex;
          _queueTotal = event.queueTotal;
          _isDone = false;
        });
      } else if (event.isDone && event.sending == widget.info.sending) {
        final isLast = event.queueIndex >= event.queueTotal - 1;
        if (isLast) {
          _complete(event.ok);
        } else {
          setState(() {
            _transferred = 0;
            _lastBytes = 0;
            _speed = 0;
            _isDone = false;
          });
        }
      }
    });

    // sender side: when the next queued file is accepted, reload its metadata
    _sendSub = widget.transport.sendStateStream.listen((s) {
      if (!mounted || s != SendState.accepted || !widget.info.sending) return;
      final q = widget.transport.sendQueue;
      final idx = widget.transport.currentSendIndex;
      if (idx < q.length) {
        setState(() {
          _transferred = widget.transport.sentBytes.toDouble();
          _lastBytes = _transferred;
          _speed = 0;
          _currentName = q[idx].name;
          _currentTotal = q[idx].size.toDouble();
          _queueIndex = idx;
          _queueTotal = q.length;
          _isDone = false;
        });
      }
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
  void dispose() {
    _sub?.cancel();
    _fileSub?.cancel();
    _sendSub?.cancel();
    super.dispose();
  }

  String _formatBytes(double bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pct = _currentTotal > 0 ? math.min(1.0, _transferred / _currentTotal) : 0.0;
    final checking = pct >= 1.0 && !_isDone;
    final secondsLeft = _speed > 0 ? math.max(1, ((_currentTotal - _transferred) / _speed).round()) : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.info.sending ? 'Sending files' : 'Receiving files',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_queueTotal > 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: FlovaTokens.surface,
                      border: Border.all(color: FlovaTokens.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('File ${_queueIndex + 1} of $_queueTotal',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                  ),
                const Icon(Icons.description_outlined, size: 40, color: FlovaTokens.accent),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(_currentName, style: text.headlineMedium, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 32),
                Center(
                  child: SizedBox(
                    width: 200,
                    height: 200,
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
                Text('${_formatBytes(_transferred)} of ${_formatBytes(_currentTotal)}',
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