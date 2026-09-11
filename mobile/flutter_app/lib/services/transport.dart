/// WORKFLOW OF THIS FILE:
/// 1. Manages the WebSocket connection and the offer/accept handshake.
/// 2. When a file-offer arrives, it emits an event to the UI.
/// 3. When the user accepts, it opens the file sink FIRST, then sends file-accept.
/// 4. This guarantees the sink is ready before the desktop sends binary chunks.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TransportState { idle, connecting, connected, paired, reconnecting, disconnected, error }

class FileEvent {
  final String name;
  final int size;
  final bool isOffer;
  final bool isDone;
  const FileEvent({required this.name, required this.size, this.isOffer = false, this.isDone = false});
}

class TransportClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? peerName;

  String? _host; int? _port; String? _selfName; String? _platform;
  Timer? _pingTimer; Timer? _reconnectTimer;
  int _lastPongMs = 0; int _reconnectAttempt = 0;

  IOSink? _fileSink;
  String? _currentFileName; String? _currentFilePath;
  int _currentFileSize = 0; int _receivedBytes = 0;

  String? _pendingOfferName; int _pendingOfferSize = 0;

  final StreamController<TransportState> _stateCtrl = StreamController<TransportState>.broadcast();
  final StreamController<int> _progressCtrl = StreamController<int>.broadcast();
  final StreamController<FileEvent> _fileEventCtrl = StreamController<FileEvent>.broadcast();

  Stream<TransportState> get stateStream => _stateCtrl.stream;
  Stream<int> get progressStream => _progressCtrl.stream;
  Stream<FileEvent> get fileEventStream => _fileEventCtrl.stream;

  static const Duration pingInterval = Duration(seconds: 3);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const List<Duration> backoff = [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 15)];

  Future<void> connect({required String host, required int port, required String selfName, required String platform}) async {
    _host = host; _port = port; _selfName = selfName; _platform = platform; _reconnectAttempt = 0;
    await _doConnect(emitError: true);
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel(); _reconnectAttempt = 0;
    if (_host == null || _port == null) { _stateCtrl.add(TransportState.error); return; }
    await _doConnect(emitError: true);
  }

  Future<void> _doConnect({required bool emitError}) async {
    _stopTimers(); _stateCtrl.add(TransportState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$_host:$_port'));
      await _channel!.ready; _stateCtrl.add(TransportState.connected);
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
      if (_fileSink != null) { _fileSink!.add(data); _receivedBytes += data.length; _progressCtrl.add(data.length); }
    } else if (data is String) {
      try {
        final msg = jsonDecode(data) as Map<String, dynamic>;
        final type = msg['type'];
        if (type == 'hello-ack') {
          peerName = msg['name'] as String?; _reconnectAttempt = 0; _lastPongMs = DateTime.now().millisecondsSinceEpoch;
          _startHeartbeat(); _stateCtrl.add(TransportState.paired);
        } else if (type == 'ping') { _channel?.sink.add(jsonEncode({'type': 'pong'})); }
        else if (type == 'pong') { _lastPongMs = DateTime.now().millisecondsSinceEpoch; }
        else if (type == 'file-offer') {
          _pendingOfferName = msg['name'] as String;
          _pendingOfferSize = msg['size'] as int;
          _fileEventCtrl.add(FileEvent(name: _pendingOfferName!, size: _pendingOfferSize!, isOffer: true));
        } else if (type == 'file-end') { _finishIncomingFile(); }
      } catch (_) {}
    }
  }

  // Called by the UI when the user taps "Accept"
  Future<void> acceptIncomingFile() async {
    if (_pendingOfferName == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/Flova');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final safeName = _pendingOfferName!.split(Platform.pathSeparator).last;
    final file = File('${saveDir.path}/$safeName');
    _fileSink = file.openWrite(); // Open sink BEFORE telling desktop to send
    _currentFileName = safeName; _currentFilePath = file.path;
    _currentFileSize = _pendingOfferSize!; _receivedBytes = 0;

    _channel?.sink.add(jsonEncode({'type': 'file-accept'})); // Tell desktop to start streaming
    _pendingOfferName = null; _pendingOfferSize = 0;
  }

  Future<void> sendFile(File file) async {
    if (_channel == null) return;
    final size = await file.length();
    final name = file.path.split(Platform.pathSeparator).last;
    _channel!.sink.add(jsonEncode({'type': 'file-start', 'name': name, 'size': size}));
    final stream = file.openRead();
    await for (final chunk in stream) { _channel!.sink.add(chunk); _progressCtrl.add(chunk.length); }
    _channel!.sink.add(jsonEncode({'type': 'file-end'}));
  }

  void _finishIncomingFile() {
    final name = _currentFileName;
    _fileSink?.flush(); _fileSink?.close(); _fileSink = null;
    if (name != null) _fileEventCtrl.add(FileEvent(name: name, size: _currentFileSize, isDone: true));
    _currentFileName = null; _currentFilePath = null;
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
  void disconnect() { _host = null; _port = null; _stopTimers(); _sub?.cancel(); _sub = null; try { _channel?.sink.close(); } catch (_) {} _channel = null; }
  void dispose() { disconnect(); _stateCtrl.close(); _progressCtrl.close(); _fileEventCtrl.close(); }
}