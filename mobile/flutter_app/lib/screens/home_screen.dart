/// WORKFLOW OF THIS FILE:
/// 1. Mobile home shell that owns the bottom navigation bar.
/// 2. Receives a TransportClient from ScannerScreen and owns it for its lifetime.
/// 3. Subscribes to the client's state stream.
/// 4. While paired: normal home UI.
/// 5. While reconnecting: shows a full-screen overlay with a spinner and
///    "Trying to reconnect..." text. User can cancel the attempt.
/// 6. While disconnected/error: same overlay but with "Reconnect" and "Go back".
/// 7. On paired again, overlay fades out automatically.
/// 8. Tab 0 = Home, Tab 1 = Transfers, Tab 2 = History, Tab 3 = Settings.
///
/// CLASSES / FUNCTIONS:
///  - HomeScreen             : owns the transport client and the selected tab.
///  - _buildHomeContent()    : builds the Home tab content.
///  - _buildTransferItem()   : builds one row of the Recent transfers list.
///  - _buildConnectionOverlay() : overlay shown when connection drops.
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/flova_mark.dart';
import '../core/tokens.dart';
import '../services/transport.dart';
import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'settings_screen.dart';
import 'transfers_screen.dart';

class HomeScreen extends StatefulWidget {
  final String peerName;
  final TransportClient transport;
  const HomeScreen({super.key, this.peerName = 'Laptop', required this.transport});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  TransportState _state = TransportState.paired;
  StreamSubscription<TransportState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.transport.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.transport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget bodyContent;
    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildHomeContent(context, textTheme);
      case 1:
        bodyContent = const TransfersScreen();
      case 2:
        bodyContent = const HistoryScreen();
      default:
        bodyContent = const SettingsScreen();
    }

    final showOverlay =
        _state == TransportState.reconnecting ||
        _state == TransportState.error ||
        _state == TransportState.disconnected;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(child: bodyContent),
          if (showOverlay) _buildConnectionOverlay(),
        ],
      ),
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

  Widget _buildConnectionOverlay() {
    final isReconnecting = _state == TransportState.reconnecting;
    return Container(
      color: FlovaTokens.canvas.withValues(alpha: 0.98),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isReconnecting)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(color: FlovaTokens.accent),
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(color: Color(0x1AEF4444), shape: BoxShape.circle),
                    child: const Icon(Icons.wifi_off_rounded, color: FlovaTokens.error, size: 32),
                  ),
                const SizedBox(height: 24),
                Text(
                  isReconnecting ? 'Trying to reconnect…' : 'Connection lost',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isReconnecting
                      ? 'Attempting to reach ${widget.peerName} again.'
                      : 'Could not reach ${widget.peerName}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (!isReconnecting)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => widget.transport.reconnectNow(),
                      child: const Text('Reconnect'),
                    ),
                  ),
                if (!isReconnecting) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        widget.transport.disconnect();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Go back'),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        widget.transport.disconnect();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel', style: TextStyle(color: FlovaTokens.ink2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context, TextTheme textTheme) {
    final isConnected = _state == TransportState.paired;
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
          Text(
            isConnected ? 'Laptop connected' : 'Connection interrupted',
            style: textTheme.headlineLarge,
          ),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isConnected ? FlovaTokens.success : FlovaTokens.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(widget.peerName, style: textTheme.bodyLarge?.copyWith(color: FlovaTokens.ink2)),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isConnected
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SendScreen()))
                  : null,
              icon: const Icon(Icons.send),
              label: const Text('Send a file'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isConnected
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiveScreen()))
                  : null,
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: FlovaTokens.section, borderRadius: BorderRadius.circular(FlovaTokens.rControl)),
          child: const Icon(Icons.description_outlined, color: FlovaTokens.ink2, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: FlovaTokens.ink)),
            const SizedBox(height: 2),
            Text(size, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(time, style: const TextStyle(fontSize: 12, color: FlovaTokens.ink3)),
          const SizedBox(height: 2),
          const Text('Completed', style: TextStyle(fontSize: 12, color: FlovaTokens.success, fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }
}