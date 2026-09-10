/// WORKFLOW OF THIS FILE:
/// 1. This screen shows the transfer queue: moving files and finished files.
/// 2. A Timer adds a little progress to every active file every 100ms.
/// 3. When an active file reaches 100%, it becomes a finished row.
/// 4. Pause freezes one file, Cancel removes a moving file,
///    Remove deletes a finished file.
/// 5. When the list is empty, we show a calm empty state.
///
/// CLASSES / FUNCTIONS:
///  - _QueueItem        : simple data holder for one row.
///  - TransfersScreen   : owns the list and the timer.
///  - _activeRow()      : draws a moving file row (loud).
///  - _doneRow()        : draws a finished file row (quiet).
///  - _iconButton()     : small round action button.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/tokens.dart';

class _QueueItem {
  final int id;
  final String name;
  final String size;
  bool active;
  bool paused;
  double progress;
  String note;

  _QueueItem({
    required this.id,
    required this.name,
    required this.size,
    required this.active,
    this.paused = false,
    required this.progress,
    this.note = '',
  });
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  final math.Random _random = math.Random();
  Timer? _timer;

  final List<_QueueItem> _items = [
    _QueueItem(id: 1, name: 'Video.mp4', size: '220 MB', active: true, progress: 0.35),
    _QueueItem(id: 2, name: 'Project.zip', size: '84 MB', active: false, progress: 1, note: 'Sent to Laptop'),
    _QueueItem(id: 3, name: 'Photos.zip', size: '148 MB', active: false, progress: 1, note: 'Received from Laptop'),
  ];

  @override
  void initState() {
    super.initState();
    // timer: move every active file a little forward, finish it at 100%
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        for (final it in _items) {
          if (!it.active || it.paused) continue;
          it.progress = math.min(1.0, it.progress + 0.004 + _random.nextDouble() * 0.004);
          if (it.progress >= 1.0) {
            it.active = false;
            it.note = 'Sent to Laptop';
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // freeze or unfreeze one file
  void _togglePause(int id) {
    setState(() {
      for (final it in _items) {
        if (it.id == id) it.paused = !it.paused;
      }
    });
  }

  // delete one file from the list (cancel or remove)
  void _remove(int id) {
    setState(() => _items.removeWhere((it) => it.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // calm empty state when nothing is left
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No transfers right now',
                style: text.bodyLarge?.copyWith(color: FlovaTokens.ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Files you send or receive will appear here.', style: text.bodyMedium),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Text('Transfers', style: text.headlineMedium),
        const SizedBox(height: 16),
        for (final it in _items) it.active ? _activeRow(it) : _doneRow(it),
      ],
    );
  }

  // moving file: loud row with progress bar
  Widget _activeRow(_QueueItem it) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlovaTokens.canvas,
          border: Border.all(color: FlovaTokens.line),
          borderRadius: BorderRadius.circular(FlovaTokens.rCard),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FlovaTokens.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(FlovaTokens.rControl),
              ),
              child: const Icon(Icons.description_outlined, color: FlovaTokens.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(it.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                      ),
                      Text('${(it.progress * 100).round()}%',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: FlovaTokens.accent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: it.progress,
                      minHeight: 6,
                      backgroundColor: FlovaTokens.line,
                      valueColor: const AlwaysStoppedAnimation<Color>(FlovaTokens.accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(it.paused ? 'Paused' : it.size,
                      style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _iconButton(it.paused ? Icons.play_arrow : Icons.pause, it.paused ? 'Resume' : 'Pause',
                () => _togglePause(it.id)),
            _iconButton(Icons.close, 'Cancel', () => _remove(it.id)),
          ],
        ),
      ),
    );
  }

  // finished file: quiet row with green check
  Widget _doneRow(_QueueItem it) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlovaTokens.surface,
          border: Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(FlovaTokens.rCard),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0x1A16A34A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: FlovaTokens.success, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
                  const SizedBox(height: 2),
                  Text('${it.note} · ${it.size}',
                      style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
                ],
              ),
            ),
            _iconButton(Icons.close, 'Remove', () => _remove(it.id)),
          ],
        ),
      ),
    );
  }

  // small round action button
  Widget _iconButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 16,
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, color: FlovaTokens.ink2),
      ),
    );
  }
}