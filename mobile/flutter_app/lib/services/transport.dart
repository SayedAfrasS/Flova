/// WORKFLOW OF THIS FILE:
/// 1. Manages the WebSocket connection to the desktop server.
/// 2. Handles the control protocol: hello, ping/pong, and file metadata.
/// 3. When a file transfer starts, it opens a write stream to the app's documents folder.
/// 4. Incoming binary frames are appended to the file stream.
/// 5. Provides a sendFile method that reads a local file in chunks and
///    sends them as binary frames to the peer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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

  IOSink? _fileSink;
  String? _currentFileName;
  int _currentFileSize = 0;
  int _receivedBytes = 0;
  int _sentBytes = 0;

  final StreamController<TransportState> _stateCtrl = StreamController<TransportState>.broadcast();
  final StreamController<int> _progressCtrl = StreamController<int>.broadcast();

  Stream<TransportState> get stateStream => _stateCtrl.stream;
  Stream<int> get progressStream => _progressCtrl.stream;

  static const Duration pingInterval = Duration(seconds: 3);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const List<Duration> backoff = [
    Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4),
    Duration(seconds: 8), Duration(seconds: 15),
  ];

  Future<void> connect({
    required String host, required int port,
    required String selfName, required String platform,
  }) async {
    _host = host; _port = port; _selfName = selfName; _platform = platform;
    _reconnectAttempt = 0;
    await _doConnect(emitError: true);
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel(); _reconnectAttempt = 0;
    if (_host == null || _port == null) { _stateCtrl.add(TransportState.error); return; }
    await _doConnect(emitError: true);
  }

  Future<void> _doConnect({required bool emitError}) async {
    _stopTimers();
    _stateCtrl.add(TransportState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$_host:$_port'));
      await _channel!.ready;
      _stateCtrl.add(TransportState.connected);
      _channel!.sink.add(jsonEncode({'type': 'hello', 'name': _selfName, 'platform': _platform}));
      _sub = _channel!.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
    } catch (_) {
      if (emitError && _reconnectAttempt == 0) _stateCtrl.add(TransportState.error);
      else _stateCtrl.add(TransportState.reconnecting);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    if (data is List<int>) {
      if (_fileSink != null) {
        _fileSink!.add(data);
        _receivedBytes += data.length;
        _progressCtrl.add(data.length);
      }
    } else if (data is String) {
      try {
        final msg = jsonDecode(data) as Map<String, dynamic>;
        final type = msg['type'];
        if (type == 'hello-ack') {
          peerName = msg['name'] as String?;
          _reconnectAttempt = 0; _lastPongMs = DateTime.now().millisecondsSinceEpoch;
          _startHeartbeat(); _stateCtrl.add(TransportState.paired);
        } else if (type == 'ping') {
          _channel?.sink.add(jsonEncode({'type': 'pong'}));
        } else if (type == 'pong') {
          _lastPongMs = DateTime.now().millisecondsSinceEpoch;
        } else if (type == 'file-start') {
          _handleIncomingFile(msg['name'] as String, msg['size'] as int);
        } else if (type == 'file-end') {
          _finishIncomingFile();
        }
      } catch (_) {}
    }
  }

  Future<void> _handleIncomingFile(String name, int size) async {
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/Flova');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final safeName = name.split('/').last.split('\\').last;
    final file = File('${saveDir.path}/$safeName');
    _fileSink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _currentFileName = safeName;
    _currentFileSize = size;
    _receivedBytes = 0;
  }

  Future<void> _finishIncomingFile() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
    _currentFileName = null;
  }

  Future<void> sendFile(File file) async {
    if (_channel == null) return;
    final size = await file.length();
    final name = file.path.split('/').last.split('\\').last;

    _channel!.sink.add(jsonEncode({'type': 'file-start', 'name': name, 'size': size}));
    _sentBytes = 0;

    // openRead() yields chunks (default 64KB) safely without memory spikes
    final stream = file.openRead();
    await for (final chunk in stream) {
      _channel!.sink.add(chunk);
      _sentBytes += chunk.length;
      _progressCtrl.add(chunk.length);
    }

    _channel!.sink.add(jsonEncode({'type': 'file-end'}));
  }

  void _onClosed() {
    _stopTimers();
    if (_host != null && _port != null) { _stateCtrl.add(TransportState.reconnecting); _scheduleReconnect(); }
    else _stateCtrl.add(TransportState.disconnected);
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPongMs > pongTimeout.inMilliseconds) { try { _channel?.sink.close(); } catch (_) {} return; }
      try { _channel?.sink.add(jsonEncode({'type': 'ping'})); } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final step = _reconnectAttempt < backoff.length ? backoff[_reconnectAttempt] : backoff.last;
    _reconnectAttempt++;
    _reconnectTimer = Timer(step, () => _doConnect(emitError: false));
  }

  void _stopTimers() { _pingTimer?.cancel(); _pingTimer = null; _reconnectTimer?.cancel(); _reconnectTimer = null; }

  void disconnect() {
    _host = null; _port = null; _stopTimers(); _sub?.cancel(); _sub = null;
    try { _channel?.sink.close(); } catch (_) {} _channel = null;
  }

  void dispose() {
    disconnect(); _stateCtrl.close(); _progressCtrl.close();
  }
}