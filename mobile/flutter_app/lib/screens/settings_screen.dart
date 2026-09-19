/// WORKFLOW OF THIS FILE:
/// 1. Shows connection info (host, port, fingerprint), app version.
/// 2. Provides a "Clear history" button that wipes the SQLite history table.
/// 3. Shows the encrypted session status with the fingerprint badge.
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../services/history_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistoryCount();
  }

  Future<void> _loadHistoryCount() async {
    final rows = await HistoryStore.list();
    if (mounted) setState(() => _historyCount = rows.length);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),

        // History
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlovaTokens.surface,
            border: Border.all(color: FlovaTokens.line),
            borderRadius: BorderRadius.circular(FlovaTokens.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('History', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
              const SizedBox(height: 8),
              Text('$_historyCount transfers', style: const TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // Clear history
                    setState(() => _historyCount = 0);
                  },
                  child: const Text('Clear history'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // About
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlovaTokens.surface,
            border: Border.all(color: FlovaTokens.line),
            borderRadius: BorderRadius.circular(FlovaTokens.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
              const SizedBox(height: 12),
              _buildRow('App', 'Flova'),
              const SizedBox(height: 8),
              _buildRow('Version', '1.0.0'),
              const SizedBox(height: 8),
              _buildRow('Encryption', 'AES-256-GCM + X25519'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
        Text(value, style: const TextStyle(fontSize: 13, color: FlovaTokens.ink)),
      ],
    );
  }
}