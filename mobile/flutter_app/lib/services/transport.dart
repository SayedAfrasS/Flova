/// WORKFLOW OF THIS FILE:
/// 1. Owns the WebSocket and the symmetric offer/accept handshake.
/// 2. SENDING: after the laptop accepts, the file is read in 1 MB segments.
///    Each segment is wrapped in a binary frame:
///    [4-byte header length][header JSON {i, o, l}][segment bytes]
///    The phone registers the ack completer, SENDS the frame, then awaits the
///    ack before the next segment (sequential transfer).
/// 3. RECEIVING: on accept, a .part file is created and pre-allocated with
///    truncate(). Incoming segments are written at their byte offset through
///    a serialized write queue so writes can never interleave.
/// 4. Every 25 segments a manifest sidecar is saved beside the .part file so
///    interrupted transfers can be resumed in a later phase.
/// 5. On "file-end" the .part file is renamed to the final name (duplicates
///    get _(1), _(2) suffixes) and the done event fires after close.
///
/// FUNCTIONS:
///  - sendFile()           : sends offer only; streaming starts after accept.
///  - _streamPendingFile() : send-frame-then-await-ack loop over all segments.
///  - acceptIncomingFile() : pre-allocates .part, then replies file-accept.
///  - _handleBinaryFrame() : queues one serialized write for a segment.
///  - _writeFrame()        : writes at offset, acks, reports progress.
///  - _finishIncomingFile(): closes, renames, removes sidecar, emits done.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TransportState { idle, connecting, connected, paired, reconnecting, disconnected, error }
enum SendState { idle, waitingAccept, accepted, declined }

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

  static const int chunkSize = 4 * 1024 * 1024; // 1 MB segments

  // receiving
  RandomAccessFile? _recvRaf;
  File? _recvPartFile;
  String? _recvFinalName;
  int _recvSize = 0;
  String? _recvTransferId;
  Directory? _recvSaveDir;
  final Set<int> _recvReceived = {};
  int _receivedBytes = 0;
  String? _pendingOfferName; int _pendingOfferSize = 0; String? _pendingOfferId;
  Future<void> _writeQueue = Future<void>.value(); // serializes offset writes

  // sending
  File? _pendingSendFile;
  String _pendingSendName = ''; int _pendingSendSize = 0;
  int _sentBytes = 0;
  bool _sendAborted = false;
  final Map<int, Completer<void>> _ackWaiters = {};

  final StreamController<TransportState> _stateCtrl = StreamController<TransportState>.broadcast();
  final StreamController<int> _progressCtrl = StreamController<int>.broadcast();
  final StreamController<FileEvent> _fileEventCtrl = StreamController<FileEvent>.broadcast();
  final StreamController<SendState> _sendStateCtrl = StreamController<SendState>.broadcast();

  Stream<TransportState> get stateStream => _stateCtrl.stream;
  Stream<int> get progressStream => _progressCtrl.stream;
  Stream<FileEvent> get fileEventStream => _fileEventCtrl.stream;
  Stream<SendState> get sendStateStream => _sendStateCtrl.stream;

  int get sentBytes => _sentBytes;
  int get receivedBytes => _receivedBytes;

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
    if (data is List<int>) { _handleBinaryFrame(data); return; }
    if (data is String) {
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
        } else if (type == 'chunk-ack') {
          final i = (msg['i'] as num).toInt();
          _ackWaiters.remove(i)?.complete();
        } else if (type == 'file-offer') {
          _pendingOfferName = msg['name'] as String;
          _pendingOfferSize = (msg['size'] as num).toInt();
          _pendingOfferId = (msg['transferId'] ?? 't0') as String;
          _fileEventCtrl.add(FileEvent(name: _pendingOfferName!, size: _pendingOfferSize, isOffer: true));
        } else if (type == 'file-accept') {
          if (_pendingSendFile != null) {
            _sendStateCtrl.add(SendState.accepted);
            _streamPendingFile();
          }
        } else if (type == 'file-decline') {
          _pendingSendFile = null;
          _sendStateCtrl.add(SendState.declined);
        } else if (type == 'file-start') {
          // segments follow; the write sink is already open from accept
        } else if (type == 'file-end') {
          _finishIncomingFile();
        }
      } catch (_) {}
    }
  }

  // ---------- sending ----------
  Future<void> sendFile(File file) async {
    if (_channel == null) return;
    _pendingSendFile = file;
    _pendingSendSize = await file.length();
    _pendingSendName = file.path.split(Platform.pathSeparator).last;
    _sentBytes = 0;
    _channel!.sink.add(jsonEncode({
      'type': 'file-offer',
      'transferId': 't${DateTime.now().millisecondsSinceEpoch}',
      'name': _pendingSendName,
      'size': _pendingSendSize,
      'chunkSize': chunkSize,
      'chunkCount': _pendingSendSize == 0 ? 0 : (_pendingSendSize / chunkSize).ceil(),
    }));
    _sendStateCtrl.add(SendState.waitingAccept);
  }

  Future<void> _streamPendingFile() async {
    final file = _pendingSendFile;
    if (file == null) return;
    _pendingSendFile = null;
    final size = _pendingSendSize;
    final count = size == 0 ? 0 : (size / chunkSize).ceil();
    _sendAborted = false;

    _channel!.sink.add(jsonEncode({'type': 'file-start', 'name': _pendingSendName, 'size': size}));

    final raf = await file.open(mode: FileMode.read);
    try {
      for (var i = 0; i < count; i++) {
        if (_sendAborted || _channel == null) break;
        final offset = i * chunkSize;
        final len = offset + chunkSize > size ? size - offset : chunkSize;
        await raf.setPosition(offset);
        final chunk = await raf.read(len);

        final headerBytes = utf8.encode(jsonEncode({'i': i, 'o': offset, 'l': chunk.length}));
        final bb = BytesBuilder();
        bb.add((ByteData(4)..setUint32(0, headerBytes.length)).buffer.asUint8List());
        bb.add(headerBytes);
        bb.add(chunk);

        // 1) register completer, 2) SEND, 3) then wait for the ack
        final waiter = Completer<void>();
        _ackWaiters[i] = waiter;
        _channel!.sink.add(bb.toBytes());
        await waiter.future;
        if (_sendAborted || _channel == null) break;
        _sentBytes += chunk.length;
        _progressCtrl.add(chunk.length);
      }
    } finally {
      await raf.close();
    }

    if (!_sendAborted && _channel != null) {
      _channel!.sink.add(jsonEncode({'type': 'file-end'}));
    }
  }

  // ---------- receiving ----------
  Future<void> acceptIncomingFile() async {
    if (_pendingOfferName == null) return;
    Directory? baseDir;
    if (Platform.isAndroid) baseDir = await getExternalStorageDirectory();
    baseDir ??= await getApplicationDocumentsDirectory();

    final saveDir = Directory('${baseDir.path}/Flova');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final safeName = _pendingOfferName!.split(Platform.pathSeparator).last;
    final partFile = File('${saveDir.path}/$safeName.part');
    final raf = await partFile.open(mode: FileMode.write);
    await raf.truncate(_pendingOfferSize);

    _recvRaf = raf;
    _recvPartFile = partFile;
    _recvFinalName = safeName;
    _recvSize = _pendingOfferSize;
    _recvTransferId = _pendingOfferId;
    _recvSaveDir = saveDir;
    _recvReceived.clear();
    _receivedBytes = 0;

    _channel?.sink.add(jsonEncode({'type': 'file-accept'}));
    _pendingOfferName = null; _pendingOfferSize = 0; _pendingOfferId = null;
  }

  // queue every segment write so setPosition/writeFrom never interleave
  void _handleBinaryFrame(List<int> data) {
    _writeQueue = _writeQueue.then((_) => _writeFrame(data));
  }

  Future<void> _writeFrame(List<int> data) async {
    final raf = _recvRaf;
    if (raf == null) return;
    try {
      final u8 = data is Uint8List ? data : Uint8List.fromList(data);
      final headerLen = ByteData.sublistView(u8, 0, 4).getUint32(0);
      final header = jsonDecode(utf8.decode(u8.sublist(4, 4 + headerLen))) as Map<String, dynamic>;
      final payload = u8.sublist(4 + headerLen);
      final offset = (header['o'] as num).toInt();
      final index = (header['i'] as num).toInt();

      await raf.setPosition(offset);
      await raf.writeFrom(payload);

      _recvReceived.add(index);
      if (_recvReceived.length % 25 == 0) _writeSidecar();
      _receivedBytes += payload.length;
      _progressCtrl.add(payload.length);
      _channel?.sink.add(jsonEncode({'type': 'chunk-ack', 'i': index}));
    } catch (_) {}
  }

  void _writeSidecar() {
    final dir = _recvSaveDir; final id = _recvTransferId;
    if (dir == null || id == null) return;
    try {
      File('${dir.path}/.$id.flova.json').writeAsStringSync(jsonEncode({
        'name': _recvFinalName, 'size': _recvSize,
        'chunkSize': chunkSize, 'received': _recvReceived.toList(),
      }));
    } catch (_) {}
  }

  Future<void> _finishIncomingFile() async {
    final raf = _recvRaf;
    if (raf != null) { try { await raf.close(); } catch (_) {} _recvRaf = null; }
    // wait for queued writes to drain before renaming
    await _writeQueue;
    final part = _recvPartFile; final dir = _recvSaveDir; final finalName = _recvFinalName;
    if (part == null || dir == null || finalName == null) return;

    var finalPath = '${dir.path}/$finalName';
    var counter = 1;
    while (await File(finalPath).exists()) {
      final ext = finalName.contains('.') ? '.${finalName.split('.').last}' : '';
      final base = finalName.contains('.') ? finalName.substring(0, finalName.lastIndexOf('.')) : finalName;
      finalPath = '${dir.path}/${base}_($counter)$ext';
      counter++;
    }
    try {
      await part.rename(finalPath);
      final id = _recvTransferId;
      if (id != null) {
        final sidecar = File('${dir.path}/.$id.flova.json');
        if (await sidecar.exists()) await sidecar.delete();
      }
      _fileEventCtrl.add(FileEvent(name: finalPath.split(Platform.pathSeparator).last, size: _recvSize, isDone: true));
    } catch (_) {}
    _recvPartFile = null; _recvFinalName = null; _recvTransferId = null;
  }

  void _onClosed() {
    _stopTimers();
    _sendAborted = true;
    for (final w in _ackWaiters.values) { if (!w.isCompleted) w.complete(); }
    _ackWaiters.clear();
    _writeSidecar();
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
  void dispose() { disconnect(); _stateCtrl.close(); _progressCtrl.close(); _fileEventCtrl.close(); _sendStateCtrl.close(); }
}