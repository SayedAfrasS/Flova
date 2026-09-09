import 'package:flutter/material.dart';
import '../core/tokens.dart';

class StubScreen extends StatelessWidget {
  const StubScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: FlovaTokens.canvas,
          surfaceTintColor: Colors.transparent,
          title: Text(title, style: const TextStyle(color: FlovaTokens.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        body: Center(
          child: Text('Screen lands in the next Phase 2 increment.',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}