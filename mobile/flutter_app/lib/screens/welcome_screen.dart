/// WORKFLOW OF THIS FILE:
/// 1. First screen of the mobile app.
/// 2. On start it loads the persisted session (SessionStore). If a previous
///    pairing exists, a primary "Reconnect to <Laptop>" button appears so an
///    app relaunch never forces a new QR scan.
/// 3. Reconnect creates a TransportClient with the saved host/port; on paired
///    it jumps straight to Home (where any resume continues automatically).
/// 4. If reconnect fails or times out, a snackbar explains and the user can
///    still fall back to "Scan laptop code".
/// 5. The line art at the bottom is drawn by _LineArtPainter.
///
/// FUNCTIONS:
///  - _reconnect()     : connects with the saved session and navigates on success.
///  - _scan()          : opens the QR scanner flow (fresh pairing).
///  - _LineArtPainter  : draws phone + laptop + connecting curve.
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/flova_mark.dart';
import '../core/tokens.dart';
import '../services/session_store.dart';
import '../services/transport.dart';
import 'home_screen.dart';
import 'scanner_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  SessionInfo? _session;
  bool _reconnecting = false;
  TransportClient? _client;
  StreamSubscription<TransportState>? _sub;
  Timer? _timeout;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) {
      if (mounted) setState(() => _session = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    if (!_handedOff) _client?.dispose();
    super.dispose();
  }

  void _reconnect() {
    final s = _session;
    if (s == null || _reconnecting) return;
    setState(() => _reconnecting = true);

    final client = TransportClient();
    _client = client;
    _sub?.cancel();
    _sub = client.stateStream.listen((st) {
      if (!mounted) return;
      if (st == TransportState.paired) {
        _timeout?.cancel();
        _handedOff = true;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => HomeScreen(peerName: client.peerName ?? s.peerName, transport: client),
        ));
      } else if (st == TransportState.error || st == TransportState.disconnected) {
        _timeout?.cancel();
        setState(() => _reconnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reach your laptop. Make sure you are on its hotspot, or scan the code instead.')),
        );
      }
    });

    // unreachable laptop should not hang forever
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (_reconnecting) {
        client.disconnect();
        setState(() => _reconnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No response from your laptop. Scan the QR code instead.')),
        );
      }
    });

    client.connect(host: s.host, port: s.port, selfName: "Afras's Phone", platform: 'mobile');
  }

  void _scan() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScannerScreen()));
  }

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
              if (_session != null) ...[
                FilledButton(
                  onPressed: _reconnecting ? null : _reconnect,
                  child: _reconnecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Reconnect to ${_session!.peerName}'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reconnecting ? null : _scan, child: const Text('Scan laptop code')),
              ] else
                FilledButton(onPressed: _scan, child: const Text('Scan laptop code')),
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

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.34, w * 0.09, h * 0.44), const Radius.circular(6)),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.50, h * 0.26, w * 0.28, h * 0.40), const Radius.circular(6)),
      stroke,
    );
    canvas.drawLine(Offset(w * 0.45, h * 0.74), Offset(w * 0.83, h * 0.74), stroke);
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