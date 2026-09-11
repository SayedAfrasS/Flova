/// WORKFLOW OF THIS FILE:
/// 1. Opens the device camera using mobile_scanner to look for a QR code.
/// 2. When a QR code is found, it stops processing further scans.
/// 3. Parses the JSON string to extract the laptop's IP and port.
/// 4. Opens a TransportClient to connect to the laptop automatically.
/// 5. Watches the connection state and shows Connecting, Paired, or Error UI.
/// 6. On success, hands the TransportClient off to HomeScreen so it can
///    monitor the connection and auto-reconnect if the laptop goes away.
/// 7. The flashlight icon is a placeholder for Phase 4.
///
/// CLASSES / FUNCTIONS:
///  - ScannerScreen    : owns the transport client, state, and camera controller.
///  - _handleScan      : processes the scanned barcode and triggers connection.
///  - _processQr       : parses the JSON and starts the socket connection.
///  - _retry           : resets the state and rebuilds the camera to try again.
///  - _handOff         : pushes HomeScreen with ownership of the transport client.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/tokens.dart';
import '../services/transport.dart';
import 'home_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _cameraCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final _transport = TransportClient();
  StreamSubscription<TransportState>? _sub;

  TransportState _state = TransportState.idle;
  String? _peerName;
  bool _isProcessing = false;
  bool _handedOff = false;
  Key _scannerKey = UniqueKey();

  @override
  void dispose() {
    _sub?.cancel();
    _cameraCtrl.dispose();
    // only dispose transport if we never handed it off to HomeScreen
    if (!_handedOff) {
      _transport.dispose();
    }
    super.dispose();
  }

  void _handleScan(BarcodeCapture capture) {
    if (_isProcessing || _state != TransportState.idle) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _processQr(rawValue);
        break;
      }
    }
  }

  void _processQr(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['app'] != 'flova' || data['host'] == null || data['port'] == null) return;

      setState(() => _isProcessing = true);

      final host = data['host'] as String;
      final port = data['port'] as int;

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
    } catch (e) {
      // ignore invalid JSON
    }
  }

  void _retry() {
    setState(() {
      _state = TransportState.idle;
      _isProcessing = false;
      _peerName = null;
      _scannerKey = UniqueKey();
    });
  }

  void _handOff() {
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          peerName: _peerName ?? 'Laptop',
          transport: _transport,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final showOverlay = _state != TransportState.idle;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!showOverlay)
            MobileScanner(
              key: _scannerKey,
              controller: _cameraCtrl,
              onDetect: _handleScan,
            ),
          if (showOverlay) Container(color: FlovaTokens.canvas),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      if (!showOverlay)
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: showOverlay ? _buildStatusView(text) : _buildScanningGuide(text),
                  ),
                ),
                if (!showOverlay)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _cameraCtrl,
                      builder: (context, state, child) {
                        final torchState = state.torchState;
                        return IconButton(
                          iconSize: 32,
                          icon: Icon(
                            torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                          onPressed: () => _cameraCtrl.toggleTorch(),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningGuide(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Text('Scan laptop code', style: text.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text('Point your camera at the QR code shown on your laptop.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildStatusView(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusIcon(),
          const SizedBox(height: 24),
          Text(_statusTitle(), style: text.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(_statusSubtitle(), style: text.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          if (_state == TransportState.paired) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _handOff, child: const Text('Continue')),
            ),
            const SizedBox(height: 12),
          ],
          if (_state == TransportState.error || _state == TransportState.disconnected) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _retry, child: const Text('Try again')),
            ),
            const SizedBox(height: 12),
          ],
          if (_state != TransportState.paired)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('Cancel', style: TextStyle(color: FlovaTokens.ink2)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon() {
    if (_state == TransportState.connecting || _state == TransportState.connected) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(color: FlovaTokens.accent),
      );
    }
    if (_state == TransportState.paired) {
      return Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(color: Color(0x1A16A34A), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: FlovaTokens.success, size: 32),
      );
    }
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(color: Color(0x1AEF4444), shape: BoxShape.circle),
      child: const Icon(Icons.close_rounded, color: FlovaTokens.error, size: 32),
    );
  }

  String _statusTitle() {
    switch (_state) {
      case TransportState.connecting:
      case TransportState.connected:
        return 'Connecting...';
      case TransportState.paired:
        return 'Laptop connected';
      default:
        return 'Connection failed';
    }
  }

  String _statusSubtitle() {
    switch (_state) {
      case TransportState.connecting:
      case TransportState.connected:
        return 'Establishing a secure connection.';
      case TransportState.paired:
        return _peerName ?? 'Laptop';
      default:
        return 'Could not connect to the laptop.';
    }
  }
}