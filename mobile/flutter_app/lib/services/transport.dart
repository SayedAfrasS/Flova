/// WORKFLOW OF THIS FILE:
/// 1. Manages the WebSocket connection and the offer/accept handshake.
/// 2. When accepting a file, it saves to the external storage directory on Android
///    so the file is visible in standard file manager apps.
/// 3. Properly awaits the file sink flush and close before emitting the "done" event,
///    ensuring the file is fully written to disk before the UI updates.
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
        } else if (type == 'file-end') {
          _finishIncomingFile();
        }
      } catch (_) {}
    }
  }

  Future<void> acceptIncomingFile() async {
    if (_pendingOfferName == null) return;

    // Use external storage on Android so it's visible in file managers
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    baseDir ??= await getApplicationDocumentsDirectory();

    final saveDir = Directory('${baseDir.path}/Flova');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final safeName = _pendingOfferName!.split(Platform.pathSeparator).last;
    var file = File('${saveDir.path}/$safeName');

    // Handle duplicate filenames
    int counter = 1;
    while (await file.exists()) {
      final ext = safeName.contains('.') ? '.${safeName.split('.').last}' : '';
      final nameWithoutExt = safeName.contains('.') ? safeName.substring(0, safeName.lastIndexOf('.')) : safeName;
      file = File('${saveDir.path}/${nameWithoutExt}_($counter)$ext');
      counter++;
    }

    _fileSink = file.openWrite();
    _currentFileName = file.path.split(Platform.pathSeparator).last;
    _currentFilePath = file.path;
    _currentFileSize = _pendingOfferSize!;
    _receivedBytes = 0;

    _channel?.sink.add(jsonEncode({'type': 'file-accept'}));
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

  // CRITICAL FIX: Await flush and close so the file is actually on disk before emitting done
  Future<void> _finishIncomingFile() async {
    final name = _currentFileName;
    if (_fileSink != null) {
      try {
        await _fileSink!.flush();
        await _fileSink!.close();
      } catch (e) {
        print('[transport] error closing file sink: $e');
      }
    }
    _fileSink = null;

    if (name != null) {
      _fileEventCtrl.add(FileEvent(name: name, size: _currentFileSize, isDone: true));
    }

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