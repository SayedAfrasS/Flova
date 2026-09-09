import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import 'progress_screen.dart';

class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  static const info = TransferInfo(
    name: 'Project Presentation.pdf',
    size: '24.8 MB',
    bytes: 24.8 * 1024 * 1024,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlovaTokens.canvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Send a file',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: FlovaTokens.surface,
                    border: Border.all(color: FlovaTokens.line),
                    borderRadius: BorderRadius.circular(FlovaTokens.rCard),
                  ),
                  child: const Icon(Icons.description_outlined, size: 36, color: FlovaTokens.accent),
                ),
                const SizedBox(height: 16),
                Text(info.name, style: text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(info.size, style: text.bodyMedium),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlovaTokens.surface,
                    border: Border.all(color: FlovaTokens.line),
                    borderRadius: BorderRadius.circular(FlovaTokens.rCard),
                  ),
                  child: const Row(
                    children: [
                      Text('Sending to', style: TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
                      SizedBox(width: 8),
                      Icon(Icons.laptop, size: 16, color: FlovaTokens.ink2),
                      SizedBox(width: 6),
                      Text("Afras's Laptop",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProgressScreen(info: info)),
                    ),
                    child: const Text('Send file'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}