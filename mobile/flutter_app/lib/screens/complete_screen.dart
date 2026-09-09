import 'package:flutter/material.dart';
import '../core/tokens.dart';

class CompleteScreen extends StatelessWidget {
  const CompleteScreen({super.key});

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
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) =>
                      Transform.scale(scale: 0.5 + 0.5 * value, child: child),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(color: Color(0x1A16A34A), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: FlovaTokens.success, size: 32),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Transfer complete', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text('Your file has been transferred successfully.',
                    style: text.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlovaTokens.surface,
                    border: Border.all(color: FlovaTokens.line),
                    borderRadius: BorderRadius.circular(FlovaTokens.rCard),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vacation Video.mp4',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                      SizedBox(height: 2),
                      Text('1.8 GB', style: TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
                      SizedBox(height: 12),
                      SizedBox(height: 1, child: ColoredBox(color: FlovaTokens.line)),
                      SizedBox(height: 12),
                      Text('Saved to Downloads', style: TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, child: const Text('Open file'))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Send another'),
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