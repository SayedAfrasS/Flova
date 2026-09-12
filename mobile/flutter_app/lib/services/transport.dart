/// WORKFLOW OF THIS FILE:
/// 1. Owns the WebSocket and the symmetric offer/accept handshake.
/// 2. INTEGRITY: every segment frame header carries the SHA-256 of its payload;
///    the receiver verifies each segment BEFORE writing and nacks mismatches;
///    the offer carries a whole-file hash that is re-checked after file-end.
/// 3. ALL HASHING GOES THROUGH NativeSha256: hardware-accelerated on Android,
///    pure Dart fallback elsewhere. This keeps transfers link-bound instead
///    of CPU-bound and makes the final "Checking file..." step ~1s per GB.
/// 4. SENDING: adaptive worker pool (2-8); nacked indices jump the resend queue.
/// 5. RECEIVING: serialized offset writes into a pre-allocated .part file;
///    manifest sidecar every 25 segments for future resume support.
///
/// FUNCTIONS:
///  - sendFile()           : hashes file (native), sends offer, waits accept.
///  - _streamPendingFile() : adaptive parallel segment workers.
///  - acceptIncomingFile() : pre-allocates .part, replies file-accept.
///  - _writeFrame()        : native-verify hash -> write at offset -> ack/nack.
///  - _finishIncomingFile(): native whole-file verify, rename or delete, done.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_sha256.dart';

enum TransportState { idle, connecting, connected, paired, reconnecting, disconnected, error }
enum SendState { idle, waitingAccept, accepted, declined }

class FileEvent {
  final String name;
  final int size;
  final bool isOffer;
  final bool isDone;
  final bool ok;
  const FileEvent({required this.name, required this.size, this.isOffer = false, this.isDone = false, this.ok = true});
}

class TransportClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? peerName;

  String? _host; int? _port; String? _selfName; String? _platform;
  Timer? _pingTimer; Timer? _reconnectTimer;
  int _lastPongMs = 0; int _reconnectAttempt = 0;

  static const int chunkSize = 4 * 1024 * 1024;
  static const int minWorkers = 2;
  static const int startWorkers = 4;
  static const int maxWorkers = 8;

  // receiving
  RandomAccessFile? _recvRaf;
  File? _recvPartFile;
  String? _recvFinalName;
  int _recvSize = 0;
  String? _recvTransferId;
  Directory? _recvSaveDir;
  String? _recvExpectedHash;
  final Set<int> _recvReceived = {};
  int _receivedBytes = 0;
  String? _pendingOfferName; int _pendingOfferSize = 0; String? _pendingOfferId; String? _pendingOfferHash;
  Future<void> _writeQueue = Future<void>.value();

  // sending
  File? _pendingSendFile;
  String _pendingSendName = ''; int _pendingSendSize = 0;
  int _sentBytes = 0;
  bool _sendAborted = false;
  final Map<int, Completer<void>> _ackWaiters = {};
  final List<int> _resendQueue = [];

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
        } else if (type == 'chunk-nack') {
          final i = (msg['i'] as num).toInt();
          if (!_resendQueue.contains(i)) _resendQueue.add(i);
        } else if (type == 'file-offer') {
          _pendingOfferName = msg['name'] as String;
          _pendingOfferSize = (msg['size'] as num).toInt();
          _pendingOfferId = (msg['transferId'] ?? 't0') as String;
          _pendingOfferHash = (msg['fileHash'] ?? '') as String;
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
          // segments follow; write sink already open from accept
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
    final fileHash = await NativeSha256.hashFile(file.path); // native, ~1 GB/s
    _channel!.sink.add(jsonEncode({
      'type': 'file-offer',
      'transferId': 't${DateTime.now().millisecondsSinceEpoch}',
      'name': _pendingSendName,
      'size': _pendingSendSize,
      'chunkSize': chunkSize,
      'chunkCount': _pendingSendSize == 0 ? 0 : (_pendingSendSize / chunkSize).ceil(),
      'fileHash': fileHash,
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
    _resendQueue.clear();

    _channel!.sink.add(jsonEncode({'type': 'file-start', 'name': _pendingSendName, 'size': size}));

    int nextIndex = 0;
    int activeWorkers = 0;
    int targetWorkers = count == 0 ? 1 : (count < startWorkers ? count : startWorkers);
    int ackedBytes = 0;
    int lastSampleBytes = 0;
    int lastSampleMs = DateTime.now().millisecondsSinceEpoch;
    double lastRate = 0;
    final List<Future<void>> workers = [];
    Timer? monitor;

    void spawnWorker() {
      activeWorkers++;
      workers.add(() async {
        final wraf = await file.open(mode: FileMode.read);
        try {
          while (!_sendAborted && _channel != null) {
            if (_resendQueue.isEmpty && nextIndex >= count) break;
            if (activeWorkers > targetWorkers && _resendQueue.isEmpty) break;
            final i = _resendQueue.isNotEmpty ? _resendQueue.removeAt(0) : nextIndex++;
            final offset = i * chunkSize;
            final len = offset + chunkSize > size ? size - offset : chunkSize;
            await wraf.setPosition(offset);
            final chunk = await wraf.read(len);
            final segHash = await NativeSha256.hashBytes(chunk); // native per-segment hash

            final headerBytes = utf8.encode(jsonEncode({'i': i, 'o': offset, 'l': chunk.length, 'h': segHash}));
            final bb = BytesBuilder();
            bb.add((ByteData(4)..setUint32(0, headerBytes.length)).buffer.asUint8List());
            bb.add(headerBytes);
            bb.add(chunk);

            final waiter = Completer<void>();
            _ackWaiters[i] = waiter;
            _channel!.sink.add(bb.toBytes());
            await waiter.future;
            if (_sendAborted || _channel == null) break;
            ackedBytes += chunk.length;
            _sentBytes += chunk.length;
            _progressCtrl.add(chunk.length);
          }
        } finally {
          await wraf.close();
          activeWorkers--;
        }
      }());
    }

    monitor = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastSampleMs) / 1000.0;
      if (dt <= 0) return;
      final rate = (ackedBytes - lastSampleBytes) / dt;
      lastSampleBytes = ackedBytes;
      lastSampleMs = now;
      if (lastRate > 0 && rate > 0) {
        if (rate > lastRate * 1.05 && targetWorkers < maxWorkers) {
          targetWorkers++;
          spawnWorker();
        } else if (rate < lastRate * 0.7 && targetWorkers > minWorkers) {
          targetWorkers = targetWorkers ~/ 2;
          if (targetWorkers < minWorkers) targetWorkers = minWorkers;
        }
      }
      lastRate = rate;
    });

    for (var w = 0; w < targetWorkers; w++) spawnWorker();

    var awaited = 0;
    while (awaited < workers.length) {
      final batch = workers.sublist(awaited);
      awaited = workers.length;
      await Future.wait(batch);
    }
    monitor.cancel();
    while (awaited < workers.length) {
      final batch = workers.sublist(awaited);
      awaited = workers.length;
      await Future.wait(batch);
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
    _recvExpectedHash = (_pendingOfferHash == null || _pendingOfferHash!.isEmpty) ? null : _pendingOfferHash;
    _recvReceived.clear();
    _receivedBytes = 0;

    _channel?.sink.add(jsonEncode({'type': 'file-accept'}));
    _pendingOfferName = null; _pendingOfferSize = 0; _pendingOfferId = null; _pendingOfferHash = null;
  }

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

      // native verify BEFORE touching the disk
      final expected = header['h'] as String?;
      if (expected != null) {
        final actual = await NativeSha256.hashBytes(payload);
        if (actual != expected) {
          _channel?.sink.add(jsonEncode({'type': 'chunk-nack', 'i': index}));
          return;
        }
      }

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
    await _writeQueue;
    final part = _recvPartFile; final dir = _recvSaveDir; final finalName = _recvFinalName;
    if (part == null || dir == null || finalName == null) return;

    // native whole-file verdict: ~1s per GB instead of ~30s
    var ok = true;
    final expected = _recvExpectedHash;
    if (expected != null) {
      final actual = await NativeSha256.hashFile(part.path);
      ok = actual == expected;
    }

    if (!ok) {
      try { await part.delete(); } catch (_) {}
      _recvPartFile = null; _recvFinalName = null; _recvTransferId = null; _recvExpectedHash = null;
      _fileEventCtrl.add(FileEvent(name: finalName, size: _recvSize, isDone: true, ok: false));
      return;
    }

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
      _fileEventCtrl.add(FileEvent(name: finalPath.split(Platform.pathSeparator).last, size: _recvSize, isDone: true, ok: true));
    } catch (_) {}
    _recvPartFile = null; _recvFinalName = null; _recvTransferId = null; _recvExpectedHash = null;
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