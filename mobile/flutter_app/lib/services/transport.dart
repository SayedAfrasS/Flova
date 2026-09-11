/// WORKFLOW OF THIS FILE:
/// 1. Opens a WebSocket to the desktop server at ws://host:port.
/// 2. Waits for the connection to be ready, then sends a "hello" JSON message.
/// 3. Listens for a "hello-ack" reply and records the peer's name.
/// 4. While paired, sends "ping" every 3 seconds and expects "pong".
/// 5. If no "pong" is received within 10 seconds, the connection is closed
///    and the client enters "reconnecting" state.
/// 6. Auto-reconnects with backoff: 1s, 2s, 4s, 8s, 15s (cap).
/// 7. If reconnect keeps failing, stays in "reconnecting" so the UI can
///    offer a manual "Reconnect" button.
///
/// CLASSES / FUNCTIONS:
///  - TransportClient              : owns the channel, peer name, and state stream.
///  - TransportClient.connect      : saves host/port and initiates the first connection.
///  - TransportClient.reconnectNow : forces a reconnect attempt (user tap).
///  - TransportClient.disconnect   : closes socket and forgets host/port.
///  - TransportClient.dispose      : disconnects and closes the state stream.
///  - _doConnect                   : actual connect attempt.
///  - _onMessage                   : handles hello-ack / ping / pong frames.
///  - _onClosed                    : called when socket closes; triggers auto-reconnect.
///  - _startHeartbeat              : ping/pong timer while paired.
///  - _scheduleReconnect           : backoff reconnect timer.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TransportState { idle, connecting, connected, paired, reconnecting, disconnected, error }

class TransportClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? peerName;

  String? _host;
  int? _port;
  String? _selfName;
  String? _platform;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _lastPongMs = 0;
  int _reconnectAttempt = 0;

  static const Duration pingInterval = Duration(seconds: 3);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const List<Duration> backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  final StreamController<TransportState> _stateCtrl =
      StreamController<TransportState>.broadcast();
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  Future<void> connect({
    required String host,
    required int port,
    required String selfName,
    required String platform,
  }) async {
    _host = host;
    _port = port;
    _selfName = selfName;
    _platform = platform;
    _reconnectAttempt = 0;
    await _doConnect(emitError: true);
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    if (_host == null || _port == null) {
      _stateCtrl.add(TransportState.error);
      return;
    }
    await _doConnect(emitError: true);
  }

  Future<void> _doConnect({required bool emitError}) async {
    _stopTimers();
    _stateCtrl.add(TransportState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$_host:$_port'));
      await _channel!.ready;
      _stateCtrl.add(TransportState.connected);

      _channel!.sink.add(jsonEncode({
        'type': 'hello',
        'name': _selfName,
        'platform': _platform,
      }));

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
      );
    } catch (_) {
      if (emitError && _reconnectAttempt == 0) {
        _stateCtrl.add(TransportState.error);
      } else {
        _stateCtrl.add(TransportState.reconnecting);
      }
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'];
      if (type == 'hello-ack') {
        peerName = msg['name'] as String?;
        _reconnectAttempt = 0;
        _lastPongMs = DateTime.now().millisecondsSinceEpoch;
        _startHeartbeat();
        _stateCtrl.add(TransportState.paired);
      } else if (type == 'ping') {
        _channel?.sink.add(jsonEncode({'type': 'pong'}));
      } else if (type == 'pong') {
        _lastPongMs = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (_) {
      // ignore malformed
    }
  }

  void _onClosed() {
    _stopTimers();
    if (_host != null && _port != null) {
      _stateCtrl.add(TransportState.reconnecting);
      _scheduleReconnect();
    } else {
      _stateCtrl.add(TransportState.disconnected);
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPongMs > pongTimeout.inMilliseconds) {
        try {
          _channel?.sink.close();
        } catch (_) {}
        return;
      }
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final step = _reconnectAttempt < backoff.length
        ? backoff[_reconnectAttempt]
        : backoff.last;
    _reconnectAttempt++;
    _reconnectTimer = Timer(step, () => _doConnect(emitError: false));
  }

  void _stopTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void disconnect() {
    _host = null;
    _port = null;
    _stopTimers();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
  }
}