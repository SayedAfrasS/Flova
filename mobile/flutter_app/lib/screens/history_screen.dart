/// WORKFLOW OF THIS FILE:
/// 1. This screen shows old transfers grouped by day: Today and Earlier.
/// 2. The data is fake (mock) for now. Real data will come from the
///    local database later (Phase 13).
/// 3. Each row shows: file icon, name, direction + size, status, time.
/// 4. Rows are separated by thin lines, no heavy cards (calm look).
///
/// CLASSES / FUNCTIONS:
///  - _HistoryItem    : simple data holder for one row.
///  - HistoryScreen   : draws the two day sections.
///  - _row()          : draws one transfer row.
import 'package:flutter/material.dart';
import '../core/tokens.dart';

class _HistoryItem {
  final String name;
  final String size;
  final String direction;
  final String time;
  const _HistoryItem(this.name, this.size, this.direction, this.time);
}

const _today = [
  _HistoryItem('document.pdf', '2.4 MB', 'Sent to Laptop', '10:42 AM'),
  _HistoryItem('Vacation Video.mp4', '1.8 GB', 'Received from Laptop', '9:15 AM'),
];

const _earlier = [
  _HistoryItem('Project.zip', '84 MB', 'Sent to Laptop', 'Yesterday'),
  _HistoryItem('Photos.zip', '148 MB', 'Received from Laptop', 'Monday'),
];

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Text('History', style: text.headlineMedium),
        const SizedBox(height: 16),
        _sectionTitle('Today'),
        for (final item in _today) _row(item),
        const SizedBox(height: 24),
        _sectionTitle('Earlier'),
        for (final item in _earlier) _row(item),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FlovaTokens.ink)),
    );
  }

  Widget _row(_HistoryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FlovaTokens.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: FlovaTokens.section,
              borderRadius: BorderRadius.circular(FlovaTokens.rControl),
            ),
            child: const Icon(Icons.description_outlined, color: FlovaTokens.ink2, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                const SizedBox(height: 2),
                Text('${item.direction} · ${item.size}',
                    style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Completed',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: FlovaTokens.success)),
              const SizedBox(height: 2),
              Text(item.time, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}