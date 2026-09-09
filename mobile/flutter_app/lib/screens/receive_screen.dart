import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import 'progress_screen.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  static const info = TransferInfo(
    name: 'Beach Photos.zip',
    size: '148 MB',
    bytes: 148 * 1024 * 1024,
    sending: false,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Incoming file', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text('Nothing is saved until you accept.', style: text.bodyMedium),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlovaTokens.surface,
                    border: Border.all(color: FlovaTokens.line),
                    borderRadius: BorderRadius.circular(FlovaTokens.rCard),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FlovaTokens.section,
                          borderRadius: BorderRadius.circular(FlovaTokens.rControl),
                        ),
                        child: const Icon(Icons.description_outlined, color: FlovaTokens.ink2, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                            const SizedBox(height: 2),
                            Text(info.size, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text("From Afras's Laptop", style: TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProgressScreen(info: info)),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Decline'),
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