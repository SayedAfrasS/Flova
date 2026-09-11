/// WORKFLOW OF THIS FILE:
/// 1. User picks a file with the real file_picker v12 API.
/// 2. "Send file" sends only an offer, then waits for the laptop's decision.
/// 3. On accept, opens the Progress screen (bytes start flowing at that moment).
/// 4. On decline, shows a snackbar and re-enables the button.
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import '../services/transport.dart';
import 'progress_screen.dart';

class SendScreen extends StatefulWidget {
  final TransportClient transport;
  const SendScreen({super.key, required this.transport});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  File? _selectedFile;
  String _fileName = "";
  int _fileSize = 0;
  bool _waiting = false;
  StreamSubscription<SendState>? _sendSub;

  @override
  void dispose() { _sendSub?.cancel(); super.dispose(); }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final path = picked.path;
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that file. Please pick another one.')),
        );
      }
      return;
    }
    final file = File(path);
    final size = await file.length();
    setState(() { _selectedFile = file; _fileName = picked.name; _fileSize = size; });
  }

  void _sendFile() {
    if (_selectedFile == null) return;
    setState(() => _waiting = true);

    _sendSub?.cancel();
    _sendSub = widget.transport.sendStateStream.listen((s) {
      if (!mounted) return;
      if (s == SendState.accepted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ProgressScreen(
            info: TransferInfo(name: _fileName, size: _formatBytes(_fileSize), bytes: _fileSize.toDouble(), sending: true),
            transport: widget.transport,
          ),
        ));
      } else if (s == SendState.declined) {
        setState(() => _waiting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The laptop declined this file.')),
        );
      }
    });

    widget.transport.sendFile(_selectedFile!);
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
        title: const Text('Send a file', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: FlovaTokens.surface, border: Border.all(color: FlovaTokens.line), borderRadius: BorderRadius.circular(FlovaTokens.rCard)),
                  child: const Icon(Icons.description_outlined, size: 36, color: FlovaTokens.accent),
                ),
                const SizedBox(height: 16),
                Text(_fileName.isEmpty ? 'No file selected' : _fileName, style: text.headlineMedium, textAlign: TextAlign.center),
                if (_fileName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_formatBytes(_fileSize), style: text.bodyMedium),
                ],
                const SizedBox(height: 24),
                if (_fileName.isEmpty)
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _pickFile, child: const Text('Browse files')))
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _waiting ? null : _sendFile,
                      child: Text(_waiting ? 'Waiting for laptop to accept…' : 'Send file'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(onPressed: _waiting ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}