/// WORKFLOW OF THIS FILE:
/// 1. Shows the incoming-file decision: Accept or Decline.
/// 2. On mount it PEEKS the transport's pending offer, so it shows the file
///    immediately even though the offer event fired before this screen
///    existed (this fixes the old "Waiting for file..." dead end).
/// 3. It also listens for later offers while it stays open.
/// 4. Accept opens the disk sink + replies file-accept, then opens Progress.
/// 5. Decline replies file-decline and pops; onDismissed tells HomeScreen
///    this screen is gone so a future offer can push a fresh one.
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import '../services/transport.dart';
import 'progress_screen.dart';

class ReceiveScreen extends StatefulWidget {
  final TransportClient transport;
  final VoidCallback? onDismissed;
  const ReceiveScreen({super.key, required this.transport, this.onDismissed});

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
    // read an offer that arrived before this screen mounted
    _offer = widget.transport.peekPendingOffer();
    _sub = widget.transport.fileEventStream.listen((event) {
      if (event.isOffer && !_accepted && mounted) setState(() => _offer = event);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.onDismissed?.call();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_offer == null) return;
    setState(() => _accepted = true);
    await widget.transport.acceptIncomingFile();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ProgressScreen(
        info: TransferInfo(
          name: _offer!.name,
          size: _formatBytes(_offer!.size),
          bytes: _offer!.size.toDouble(),
          sending: false,
        ),
        transport: widget.transport,
      ),
    ));
  }

  void _decline() {
    widget.transport.declineIncoming();
    Navigator.of(context).pop();
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
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas, surfaceTintColor: Colors.transparent,
        title: const Text('Receive a file', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _offer == null ? _buildWaiting(text) : _buildOffer(text),
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting(TextTheme text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: FlovaTokens.accent)),
      const SizedBox(height: 24),
      Text('Waiting for file...', style: text.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Choose a file on your laptop and send it.', style: text.bodyMedium, textAlign: TextAlign.center),
    ]);
  }

  Widget _buildOffer(TextTheme text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(color: FlovaTokens.surface, border: Border.all(color: FlovaTokens.line), borderRadius: BorderRadius.circular(FlovaTokens.rCard)),
        child: const Icon(Icons.description_outlined, size: 36, color: FlovaTokens.accent),
      ),
      const SizedBox(height: 16),
      Text('Incoming file', style: text.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(_offer!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: FlovaTokens.ink), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text('${_formatBytes(_offer!.size)} · From ${widget.transport.peerName ?? 'Laptop'}', style: text.bodyMedium),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: _accepted ? null : _accept, child: Text(_accepted ? 'Preparing...' : 'Accept')),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: _accepted ? null : _decline, child: const Text('Decline')),
      ),
    ]);
  }
}