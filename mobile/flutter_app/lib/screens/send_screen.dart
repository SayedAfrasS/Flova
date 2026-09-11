/// WORKFLOW OF THIS FILE:
/// 1. Allows the user to pick a file from their phone using the file_picker package.
/// 2. Displays the selected file's name and size.
/// 3. When "Send file" is clicked, it triggers the real file transfer via the TransportClient.
/// 4. Navigates to the ProgressScreen to show real-time transfer stats.
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
  bool _isSending = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _fileName = file.path.split('/').last.split('\\').last;
        _fileSize = result.files.single.size;
      });
    }
  }

  void _sendFile() {
    if (_selectedFile == null) return;
    setState(() => _isSending = true);

    widget.transport.sendFile(_selectedFile!);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProgressScreen(
        info: TransferInfo(name: _fileName, size: _formatBytes(_fileSize), bytes: _fileSize.toDouble()),
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
                    child: FilledButton(onPressed: _isSending ? null : _sendFile, child: Text(_isSending ? 'Starting...' : 'Send file')),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}