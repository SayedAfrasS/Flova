/// WORKFLOW OF THIS FILE:
/// 1. This screen lists app preferences in a grouped list style.
/// 2. Tapping "Device name" opens a small dialog with a text field
///    so the user can rename this phone (kept in state for now).
/// 3. Other rows are quiet placeholders for later phases.
/// 4. The footer shows the app version.
///
/// CLASSES / FUNCTIONS:
///  - SettingsScreen  : owns the device name state.
///  - _group()        : draws one rounded panel of rows with hairlines.
///  - _row()          : draws one row: label left, value + chevron right.
///  - _renameDialog() : dialog with a text field for the device name.
import 'package:flutter/material.dart';
import '../core/tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _deviceName = "Afras's Phone";

  // dialog with a text field; returns the new name or null
  Future<void> _renameDialog() async {
    final controller = TextEditingController(text: _deviceName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name of this phone'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _deviceName = result);
    }
    // Note: we don't call controller.dispose() here to avoid race conditions
    // with the widget tree cleanup. The garbage collector will handle it.
  }

  // one rounded panel; hairline dividers inserted between rows
  Widget _group(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 1, child: ColoredBox(color: FlovaTokens.line)));
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: FlovaTokens.canvas,
        border: Border.all(color: FlovaTokens.line),
        borderRadius: BorderRadius.circular(FlovaTokens.rCard),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FlovaTokens.rCard),
        child: Column(children: children),
      ),
    );
  }

  Widget _row(String label, {String? value, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: FlovaTokens.ink))),
            if (value != null) Text(value, style: const TextStyle(fontSize: 13, color: FlovaTokens.ink2)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: FlovaTokens.ink3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Text('Settings', style: text.headlineMedium),
        const SizedBox(height: 16),
        _group([
          _row('Device name', value: _deviceName, onTap: _renameDialog),
        ]),
        const SizedBox(height: 16),
        _group([
          _row('Notifications'),
          _row('Storage'),
          _row('Privacy'),
        ]),
        const SizedBox(height: 16),
        _group([
          _row('About', value: 'Flova 1.0'),
        ]),
        const SizedBox(height: 32),
        Center(
          child: Text('Flova 1.0', style: TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
        ),
      ],
    );
  }
}