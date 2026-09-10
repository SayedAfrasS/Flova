/// WORKFLOW OF THIS FILE:
/// 1. In Phase 3 this is a manual connect screen (camera view is faked).
/// 2. User types the laptop's hotspot IP + port from the desktop dev line.
/// 3. Tapping "Connect" opens a TransportClient and watches its state stream.
/// 4. While connecting: spinner + "Connecting..." label.
/// 5. On "paired": shows the peer's name and a "Continue" button.
/// 6. On "error": shows a red retry button.
/// 7. The flashlight icon is a placeholder for Phase 4.
///
/// CLASSES / FUNCTIONS:
///  - ScannerScreen         : owns the form, the transport client, the state.
///  - ScannerScreen.connect : triggers the connect flow.
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../services/transport.dart';
import 'home_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8431');
  final _transport = TransportClient();
  StreamSubscription<TransportState>? _sub;

  TransportState _state = TransportState.idle;
  String? _peerName;

  @override
  void dispose() {
    _sub?.cancel();
    _transport.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null) return;

    _sub?.cancel();
    _sub = _transport.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        if (s == TransportState.paired) _peerName = _transport.peerName;
      });
    });

    _transport.connect(
      host: host,
      port: port,
      selfName: Platform.operatingSystem == 'android' ? "Afras's Phone" : 'Phone',
      platform: 'mobile',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isBusy = _state == TransportState.connecting || _state == TransportState.connected;
    final isError = _state == TransportState.error || _state == TransportState.disconnected;

    return Scaffold(
      backgroundColor: FlovaTokens.canvas,
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Connect to laptop',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text('Connect to laptop', style: text.headlineMedium),
              const SizedBox(height: 6),
              Text('Enter the server address shown on your laptop. (QR scanner lands in Phase 4.)',
                  style: text.bodyMedium),
              const SizedBox(height: 24),

              // host field
              TextField(
                controller: _hostCtrl,
                enabled: !isBusy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Laptop IP',
                  hintText: '192.168.43.100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // port field
              TextField(
                controller: _portCtrl,
                enabled: !isBusy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // primary action
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isBusy ? null : _connect,
                  child: isBusy
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Connect'),
                ),
              ),
              const SizedBox(height: 16),

              // status line
              _statusLine(),
              const SizedBox(height: 24),

              // paired confirmation
              if (_state == TransportState.paired)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlovaTokens.surface,
                    border: Border.all(color: FlovaTokens.line),
                    borderRadius: BorderRadius.circular(FlovaTokens.rCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: FlovaTokens.success, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text('Connected',
                            style: TextStyle(fontSize: 13, color: FlovaTokens.success, fontWeight: FontWeight.w500)),
                      ]),
                      const SizedBox(height: 6),
                      Text(_peerName ?? 'Laptop',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => HomeScreen(peerName: _peerName ?? 'Laptop')),
                          ),
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ),

              // error retry
              if (isError) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _connect,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    final Color dot;
    final String label;
    switch (_state) {
      case TransportState.connecting:
        dot = FlovaTokens.warning;
        label = 'Connecting...';
      case TransportState.connected:
        dot = FlovaTokens.accent;
        label = 'Socket open, waiting for hello-ack...';
      case TransportState.paired:
        dot = FlovaTokens.success;
        label = 'Paired';
      case TransportState.error:
      case TransportState.disconnected:
        dot = FlovaTokens.error;
        label = 'Could not connect. Check the IP and try again.';
      case TransportState.idle:
      default:
        dot = FlovaTokens.ink3;
        label = 'Ready to connect.';
    }
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: FlovaTokens.ink2))),
    ]);
  }
}