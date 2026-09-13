/// WORKFLOW OF THIS FILE:
/// 1. Displays incoming file offers from the peer.
/// 2. Shows file name, size, and accept/decline buttons.
/// 3. On accept, transitions to ProgressScreen for the transfer.
/// 4. On decline, sends rejection and closes the screen.
/// 5. Handles multiple queued offers sequentially.
///
/// FUNCTIONS:
///  - _buildOfferUI()     : display file details and action buttons.
///  - _buildWaitingUI()   : show waiting state when no offer is pending.
///  - _handleAccept()     : accept the offer and navigate to progress.
///  - _handleDecline()    : decline the offer and pop the screen.

import 'package:flutter/material.dart';
import '../services/transport.dart';
import 'progress_screen.dart';

class ReceiveScreen extends StatefulWidget {
  final TransportClient transport;

  const ReceiveScreen({super.key, required this.transport});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  ({String id, String name, int size})? _offer;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    widget.transport.offerStream.listen(_handleOffer);
  }

  void _handleOffer(({String id, String name, int size}) offer) {
    if (mounted) {
      setState(() {
        _offer = offer;
        _accepting = false;
      });
    }
  }

  void _handleAccept() {
    if (_offer == null || _accepting) return;
    setState(() => _accepting = true);

    widget.transport.acceptIncoming(_offer!.id);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ProgressScreen(
          transport: widget.transport,
          fileId: _offer!.id,
          fileName: _offer!.name,
          fileSize: _offer!.size,
          isSending: false,
        ),
      ),
    );
  }

  void _handleDecline() {
    if (_offer == null) return;
    widget.transport.declineIncoming(_offer!.id);
    Navigator.of(context).pop();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildWaitingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          'Waiting for files...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          'The sender is preparing files to send to you.',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildOfferUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.file_present, size: 64, color: Theme.of(context).primaryColor),
        const SizedBox(height: 24),
        const Text(
          'Incoming File',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                _offer!.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _formatBytes(_offer!.size),
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _accepting ? null : _handleDecline,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Decline'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _accepting ? null : _handleAccept,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: _accepting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Accept'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive File')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _offer == null ? _buildWaitingUI() : _buildOfferUI(),
        ),
      ),
    );
  }
}