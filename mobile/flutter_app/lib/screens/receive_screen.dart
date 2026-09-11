/// WORKFLOW OF THIS FILE:
/// 1. Opens when the user taps "Receive a file".
/// 2. Shows "Waiting for file..." until a file-offer arrives from the desktop.
/// 3. When an offer arrives, shows the file name, size, and Accept/Decline buttons.
/// 4. On Accept, opens the file sink, sends file-accept, and navigates to ProgressScreen.
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import '../services/transport.dart';
import 'progress_screen.dart';

class ReceiveScreen extends StatefulWidget {
  final TransportClient transport;
  const ReceiveScreen({super.key, required this.transport});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  StreamSubscription<FileEvent>? _sub;
  FileEvent? _offer;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.transport.fileEventStream.listen((event) {
      if (event.isOffer && !_accepted) setState(() => _offer = event);
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  Future<void> _accept() async {
    if (_offer == null) return;
    setState(() => _accepted = true);
    await widget.transport.acceptIncomingFile();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ProgressScreen(
        info: TransferInfo(name: _offer!.name, size: _formatBytes(_offer!.size), bytes: _offer!.size.toDouble(), sending: false),
        transport: widget.transport,
      ),
    ));
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(backgroundColor: FlovaTokens.canvas, surfaceTintColor: Colors.transparent,
        title: const Text('Receive a file', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink))),
      body: SafeArea(
        child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: _offer == null ? _buildWaiting(text) : _buildOffer(text))),
      ),
    );
  }

  Widget _buildWaiting(TextTheme text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: FlovaTokens.accent)),
      const SizedBox(height: 24),
      Text('Waiting for file...', style: text.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Go to your laptop and select a file to send.', style: text.bodyMedium, textAlign: TextAlign.center),
    ]);
  }

  Widget _buildOffer(TextTheme text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(color: FlovaTokens.surface, border: Border.all(color: FlovaTokens.line), borderRadius: BorderRadius.circular(FlovaTokens.rCard)),
        child: const Icon(Icons.description_outlined, size: 36, color: FlovaTokens.accent)),
      const SizedBox(height: 16),
      Text('Incoming file', style: text.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(_offer!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: FlovaTokens.ink), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(_formatBytes(_offer!.size), style: text.bodyMedium),
      const SizedBox(height: 32),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: _accepted ? null : _accept, child: Text(_accepted ? 'Preparing...' : 'Accept'))),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _accepted ? null : () => Navigator.of(context).pop(), child: const Text('Decline'))),
    ]);
  }
}