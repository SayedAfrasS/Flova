import 'package:flutter/material.dart';
import '../core/flova_mark.dart';
import '../core/tokens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget bodyContent = _selectedIndex == 0
        ? _buildHomeContent(context, textTheme)
        : Center(child: Text('Coming soon', style: textTheme.bodyLarge));

    return Scaffold(
      body: SafeArea(child: bodyContent),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: FlovaTokens.canvas,
        indicatorColor: FlovaTokens.accent.withValues(alpha: 0.1),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.sync_alt), label: 'Transfers'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context, TextTheme textTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const FlovaMark(),
            const SizedBox(width: 8),
            Text('flova', style: textTheme.headlineMedium?.copyWith(letterSpacing: -0.3)),
          ]),
          const SizedBox(height: 32),
          Text('Laptop connected', style: textTheme.headlineLarge),
          const SizedBox(height: 4),
          Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: FlovaTokens.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Afras\'s Laptop', style: textTheme.bodyLarge?.copyWith(color: FlovaTokens.ink2)),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.send),
              label: const Text('Send a file'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download),
              label: const Text('Receive a file'),
            ),
          ),
          const SizedBox(height: 40),
          Text('Recent transfers', style: textTheme.headlineMedium?.copyWith(fontSize: 18)),
          const SizedBox(height: 16),
          _buildTransferItem('document.pdf', '2.4 MB', 'Today, 10:42 AM'),
          const Divider(height: 1, color: FlovaTokens.line),
          _buildTransferItem('presentation.key', '14.1 MB', 'Yesterday'),
          const Divider(height: 1, color: FlovaTokens.line),
          _buildTransferItem('vacation_video.mp4', '1.8 GB', 'Sep 5'),
        ],
      ),
    );
  }

  Widget _buildTransferItem(String name, String size, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: FlovaTokens.section, borderRadius: BorderRadius.circular(FlovaTokens.rControl)),
          child: const Icon(Icons.description_outlined, color: FlovaTokens.ink2, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
          const SizedBox(height: 2),
          Text(size, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(time, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
          const SizedBox(height: 2),
          const Text('Completed', style: TextStyle(fontSize: 12, color: FlovaTokens.success, fontWeight: FontWeight.w500)),
        ])
      ]),
    );
  }
}