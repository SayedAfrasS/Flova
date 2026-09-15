/// WORKFLOW OF THIS FILE:
/// 1. Transfers page shows history only (completed and failed transfers).
/// 2. Rows are loaded from SQLite (HistoryStore) every time the page opens.
/// 3. Each row shows a direction icon, name, size, time and status.
/// 4. Shows a calm empty state when there is no history yet.
import 'package:flutter/material.dart';
import '../core/tokens.dart';
import '../services/history_store.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  List<HistoryRow> _history = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await HistoryStore.list();
    if (mounted) setState(() => _history = rows);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Text('Transfers', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No transfers yet. Files you send or receive will appear here.',
                style: TextStyle(fontSize: 13, color: FlovaTokens.ink3),
              ),
            ),
          )
        else
          ..._history.map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: FlovaTokens.section,
                      borderRadius: BorderRadius.circular(FlovaTokens.rControl),
                    ),
                    child: Icon(row.direction == 'sent' ? Icons.north_east : Icons.south_west,
                        size: 16, color: FlovaTokens.ink2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatBytes(row.size)} · ${row.direction == 'sent' ? 'Sent to laptop' : 'Received from laptop'} · ${_formatTime(row.ts)}',
                        style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3),
                      ),
                    ]),
                  ),
                  Text(
                    row.ok ? 'Completed' : 'Failed',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                        color: row.ok ? FlovaTokens.success : FlovaTokens.error),
                  ),
                ]),
              )),
      ],
    );
  }
}