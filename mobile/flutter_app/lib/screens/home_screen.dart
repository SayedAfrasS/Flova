/// WORKFLOW OF THIS FILE:
/// 1. Mobile home shell: bottom navigation with three tabs
///    (Home, Transfers, Settings).
/// 2. Transfers tab is history-only (TransfersScreen has no live state).
/// 3. Records every finished transfer into SQLite history (HistoryStore).
/// 4. Incoming offers push the Receive screen; resume events push Progress.
/// 5. Connection overlay handles reconnecting / lost / checking states.
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/flova_mark.dart';
import '../core/tokens.dart';
import '../core/transfer.dart';
import '../services/history_store.dart';
import '../services/transport.dart';
import 'progress_screen.dart';
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
  bool _checkingResume = false;
  bool _resumePushed = false;
  bool _receiveOpen = false;
  StreamSubscription<TransportState>? _stateSub;
  StreamSubscription<FileEvent>? _fileSub;
  Timer? _checkingTimer;

  @override
  void initState() {
    super.initState();

    final stashed = widget.transport.takeLastResumeEvent();
    if (stashed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _resumePushed) return;
        _resumePushed = true;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProgressScreen(
            info: TransferInfo(
              name: stashed.name,
              size: _formatBytes(stashed.size),
              bytes: stashed.size.toDouble(),
              sending: stashed.sending,
            ),
            transport: widget.transport,
          ),
        ));
      });
    }

    _stateSub = widget.transport.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s == TransportState.paired) {
        widget.transport.hasPendingResume().then((pending) {
          if (!mounted) return;
          if (pending) {
            setState(() => _checkingResume = true);
            _checkingTimer?.cancel();
            _checkingTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _checkingResume = false);
            });
          }
        });
      } else {
        setState(() => _checkingResume = false);
      }
    });

    _fileSub = widget.transport.fileEventStream.listen((event) {
      if (!mounted) return;
      if (event.isOffer) {
        setState(() => _checkingResume = false);
        if (_receiveOpen) return;
        _receiveOpen = true;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReceiveScreen(
            transport: widget.transport,
            onDismissed: () { if (mounted) setState(() => _receiveOpen = false); },
          ),
        ));
      } else if (event.isResume) {
        setState(() => _checkingResume = false);
        if (_resumePushed) return;
        _resumePushed = true;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProgressScreen(
            info: TransferInfo(
              name: event.name,
              size: _formatBytes(event.size),
              bytes: event.size.toDouble(),
              sending: event.sending,
            ),
            transport: widget.transport,
          ),
        ));
      } else if (event.isDone) {
        _resumePushed = false;
        // persist into real history
        HistoryStore.record(event.name, event.size, event.sending ? 'sent' : 'received', event.ok);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.ok ? 'Saved: ${event.name}' : 'Failed: ${event.name} arrived damaged'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _fileSub?.cancel();
    _checkingTimer?.cancel();
    widget.transport.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget bodyContent;
    switch (_selectedIndex) {
      case 0:
        bodyContent = _buildHomeContent(context, textTheme);
        break;
      case 1:
        bodyContent = const TransfersScreen();
        break;
      default:
        bodyContent = const SettingsScreen();
    }

    final showOverlay =
        _state == TransportState.reconnecting ||
        _state == TransportState.error ||
        _state == TransportState.disconnected ||
        (_state == TransportState.paired && _checkingResume);

    return Scaffold(
      body: Stack(
        children: [SafeArea(child: bodyContent), if (showOverlay) _buildConnectionOverlay()],
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
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildConnectionOverlay() {
    final isReconnecting = _state == TransportState.reconnecting;
    final isChecking = _state == TransportState.paired && _checkingResume;

    String title;
    String subtitle;
    if (isChecking) {
      title = 'Checking transfer...';
      subtitle = 'Looking for an interrupted transfer to continue.';
    } else if (isReconnecting) {
      title = 'Trying to reconnect…';
      subtitle = 'Attempting to reach ${widget.peerName} again.';
    } else {
      title = 'Connection lost';
      subtitle = 'Could not reach ${widget.peerName}.';
    }

    return Container(
      color: FlovaTokens.canvas.withValues(alpha: 0.98),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: FlovaTokens.accent)),
                const SizedBox(height: 24),
                Text(title, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                if (!isReconnecting && !isChecking) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => widget.transport.reconnectNow(), child: const Text('Reconnect')),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () { widget.transport.disconnect(); Navigator.of(context).pop(); },
                      child: const Text('Go back'),
                    ),
                  ),
                ],
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
          Text(isConnected ? 'Laptop connected' : 'Connection interrupted', style: textTheme.headlineLarge),
          const SizedBox(height: 4),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: isConnected ? FlovaTokens.success : FlovaTokens.error, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(widget.peerName, style: textTheme.bodyLarge?.copyWith(color: FlovaTokens.ink2)),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isConnected
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SendScreen(transport: widget.transport)))
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
                  ? () {
                      if (_receiveOpen) return;
                      _receiveOpen = true;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReceiveScreen(
                          transport: widget.transport,
                          onDismissed: () { if (mounted) setState(() => _receiveOpen = false); },
                        ),
                      ));
                    }
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Receive a file'),
            ),
          ),
        ],
      ),
    );
  }
}