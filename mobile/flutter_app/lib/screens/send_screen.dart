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
  List<File> _files = [];
  List<String> _names = [];
  List<int> _sizes = [];
  bool _isSending = false;
  StreamSubscription<SendState>? _sendSub;

  @override
  void dispose() { _sendSub?.cancel(); super.dispose(); }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;

    final files = <File>[];
    final names = <String>[];
    final sizes = <int>[];
    for (final p in picked) {
      final path = p.path;
      if (path == null) continue;
      final f = File(path);
      files.add(f);
      names.add(p.name);
      sizes.add(await f.length());
    }
    setState(() { _files = files; _names = names; _sizes = sizes; });
  }

  void _sendFiles() {
    if (_files.isEmpty) return;
    setState(() => _isSending = true);

    _sendSub?.cancel();
    _sendSub = widget.transport.sendStateStream.listen((s) {
      if (!mounted) return;
      if (s == SendState.accepted) {
        final first = _files.first;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ProgressScreen(
            info: TransferInfo(
              name: first.path.split(Platform.pathSeparator).last,
              size: _formatBytes(_sizes.first),
              bytes: _sizes.first.toDouble(),
              sending: true,
            ),
            transport: widget.transport,
          ),
        ));
      } else if (s == SendState.declined) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The laptop declined this transfer.')),
        );
      }
    });

    widget.transport.sendMultipleFiles(_files);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = _sizes.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas, surfaceTintColor: Colors.transparent,
        title: const Text('Send files', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
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
                Text(_files.isEmpty ? 'No files selected' : '${_files.length} file${_files.length > 1 ? "s" : ""} selected',
                    style: text.headlineMedium, textAlign: TextAlign.center),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${_formatBytes(total)} total', style: text.bodyMedium),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(color: FlovaTokens.surface, border: Border.all(color: FlovaTokens.line), borderRadius: BorderRadius.circular(FlovaTokens.rCard)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: FlovaTokens.line),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: Text(_names[i], maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: FlovaTokens.ink)),
                          ),
                          const SizedBox(width: 8),
                          Text(_formatBytes(_sizes[i]), style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
                        ]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (_files.isEmpty)
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _pickFiles, child: const Text('Browse files')))
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSending ? null : _sendFiles,
                      child: Text(_isSending ? 'Starting...' : 'Send files'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(onPressed: _isSending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
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