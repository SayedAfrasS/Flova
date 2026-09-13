/// WORKFLOW OF THIS FILE:
/// 1. Owns the WebSocket and the symmetric offer/accept handshake.
/// 2. OFFER PEEK: a received file-offer is kept in pending state until it is
///    accepted or declined, so a ReceiveScreen that mounts late can still
///    read it (peekPendingOffer) instead of showing "Waiting for file...".
/// 3. VERDICT: after file-end the receiver hashes the file and sends
///    verify-result {ok} back; a SENDING transfer waits for that verdict
///    (20s timeout) and only then emits its done event, so both devices
///    always agree on success or failure.
/// 4. RESUME: send + recv sidecars survive crashes/relaunches; resume-offer /
///    resume-accept replay only missing segments with seeded progress.
/// 5. Integrity: per-segment SHA-256 via NativeSha256 (nack + resend).
/// 6. Sending: adaptive worker pool (2-8) over a missing-index queue.
/// 7. Receiving: serialized offset writes into a pre-allocated .part file;
///    recv sidecar updated every 25 segments.
///
/// FUNCTIONS:
///  - peekPendingOffer()  : current un-accepted offer, without consuming it.
///  - sendFile()          : hash + save sidecar + send offer.
///  - _maybeOfferResume() : after hello, propose resuming an interrupted send.
///  - _streamFile()       : worker pool, then await receiver verdict.
///  - acceptIncomingFile(): pre-allocate .part, reply file-accept.
///  - _handleResumeOffer(): match sidecar, reopen .part, reply resume-accept.
///  - _writeFrame()       : verify hash -> write at offset -> ack or nack.
///  - _finishIncomingFile(): verify, send verify-result, rename or delete.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_sha256.dart';
import 'session_store.dart';

enum TransportState { idle, connecting, connected, paired, reconnecting, disconnected, error }
enum SendState { idle, waitingAccept, accepted, declined }

class FileEvent {
  final String name;
  final int size;
  final bool isOffer;
  final bool isDone;
  final bool ok;
  final bool sending;
  final bool isResume;
  const FileEvent({
    required this.name, required this.size,
    this.isOffer = false, this.isDone = false, this.ok = true,
    this.sending = false, this.isResume = false,
  });
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
  static const Duration verifyTimeout = Duration(seconds: 20);

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
  Map<String, dynamic>? _resumeState;
  int _sentBytes = 0;
  bool _sendAborted = false;
  final Map<int, Completer<void>> _ackWaiters = {};
  final List<int> _resendQueue = [];
  Completer<bool>? _verifyCompleter;

  FileEvent? _lastResumeEvent;
  FileEvent? takeLastResumeEvent() {
    final e = _lastResumeEvent;
    _lastResumeEvent = null;
    return e;
  }

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

  // the offer stays pending until accept/decline so late UI can read it
  FileEvent? peekPendingOffer() {
    if (_pendingOfferName == null) return null;
    return FileEvent(name: _pendingOfferName!, size: _pendingOfferSize, isOffer: true);
  }

  Future<File> _sendSidecarFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/flova-pending-send.json');
  }

  Future<Directory> _recvDir() async {
    Directory? baseDir;
    if (Platform.isAndroid) baseDir = await getExternalStorageDirectory();
    baseDir ??= await getApplicationDocumentsDirectory();
    final d = Directory('${baseDir.path}/Flova');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<bool> hasPendingResume() async {
    try {
      final sc = await _sendSidecarFile();
      if (await sc.exists()) return true;
      final dir = await _recvDir();
      return dir.listSync().any((e) => e.path.endsWith('.flova.json'));
    } catch (_) {
      return false;
    }
  }

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

  Future<bool> _waitVerify() async {
    final c = Completer<bool>();
    _verifyCompleter = c;
    Timer(verifyTimeout, () {
      if (!c.isCompleted) {
        _verifyCompleter = null;
        c.complete(true); // timeout: link delivered every ack, assume ok
      }
    });
    return c.future;
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
          if (_host != null && _port != null) {
            SessionStore.save(host: _host!, port: _port!, peerName: peerName ?? 'Laptop');
          }
          _maybeOfferResume();
        } else if (type == 'ping') {
          _channel?.sink.add(jsonEncode({'type': 'pong'}));
        } else if (type == 'pong') {
          _lastPongMs = DateTime.now().millisecondsSinceEpoch;
        } else if (type == 'verify-result') {
          final c = _verifyCompleter;
          _verifyCompleter = null;
          if (c != null && !c.isCompleted) c.complete(msg['ok'] == true);
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
            _streamFile(_pendingSendFile!, <int>{}, 0);
            _pendingSendFile = null;
          }
        } else if (type == 'file-decline') {
          _pendingSendFile = null;
          _clearSendSidecar();
          _sendStateCtrl.add(SendState.declined);
        } else if (type == 'resume-offer') {
          _handleResumeOffer(msg);
        } else if (type == 'resume-accept') {
          final received = (msg['received'] as List? ?? []).map((e) => (e as num).toInt()).toSet();
          final file = _pendingSendFile;
          if (file != null && _resumeState != null) {
            int resumed = 0;
            for (final i in received) {
              final off = i * chunkSize;
              resumed += off + chunkSize > _pendingSendSize ? _pendingSendSize - off : chunkSize;
            }
            _sentBytes = resumed;
            _sendStateCtrl.add(SendState.accepted);
            final ev = FileEvent(name: _pendingSendName, size: _pendingSendSize, sending: true, isResume: true);
            _lastResumeEvent = ev;
            _fileEventCtrl.add(ev);
            _streamFile(file, received, resumed);
            _pendingSendFile = null;
          }
        } else if (type == 'resume-decline') {
          _clearSendSidecar();
          _resumeState = null;
          _pendingSendFile = null;
        } else if (type == 'file-start') {
          // segments follow; write sink already open
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
    final fileHash = await NativeSha256.hashFile(file.path);
    final transferId = 't${DateTime.now().millisecondsSinceEpoch}';
    try {
      final sc = await _sendSidecarFile();
      await sc.writeAsString(jsonEncode({
        'transferId': transferId, 'filePath': file.path, 'name': _pendingSendName,
        'size': _pendingSendSize, 'chunkSize': chunkSize,
        'chunkCount': _pendingSendSize == 0 ? 0 : (_pendingSendSize / chunkSize).ceil(),
        'fileHash': fileHash,
      }));
    } catch (_) {}
    _channel!.sink.add(jsonEncode({
      'type': 'file-offer',
      'transferId': transferId,
      'name': _pendingSendName,
      'size': _pendingSendSize,
      'chunkSize': chunkSize,
      'chunkCount': _pendingSendSize == 0 ? 0 : (_pendingSendSize / chunkSize).ceil(),
      'fileHash': fileHash,
    }));
    _sendStateCtrl.add(SendState.waitingAccept);
  }

  Future<void> _clearSendSidecar() async {
    try {
      final sc = await _sendSidecarFile();
      if (await sc.exists()) await sc.delete();
    } catch (_) {}
  }

  Future<void> _maybeOfferResume() async {
    try {
      final sc = await _sendSidecarFile();
      if (!await sc.exists()) return;
      final s = jsonDecode(await sc.readAsString()) as Map<String, dynamic>;
      final file = File(s['filePath'] as String);
      if (!await file.exists() || await file.length() != (s['size'] as num).toInt()) {
        await _clearSendSidecar();
        return;
      }
      _pendingSendFile = file;
      _pendingSendName = s['name'] as String;
      _pendingSendSize = (s['size'] as num).toInt();
      _resumeState = s;
      _channel?.sink.add(jsonEncode({
        'type': 'resume-offer',
        'transferId': s['transferId'],
        'name': s['name'],
        'size': s['size'],
        'chunkSize': s['chunkSize'],
        'chunkCount': s['chunkCount'],
        'fileHash': s['fileHash'],
      }));
    } catch (_) {
      await _clearSendSidecar();
    }
  }

  Future<void> _streamFile(File file, Set<int> skip, int resumedBytes) async {
    final size = _pendingSendSize;
    final count = size == 0 ? 0 : (size / chunkSize).ceil();
    _sendAborted = false;
    _resendQueue.clear();

    _channel!.sink.add(jsonEncode({'type': 'file-start', 'name': _pendingSendName, 'size': size}));

    final missing = <int>[];
    for (var i = 0; i < count; i++) {
      if (!skip.contains(i)) missing.add(i);
    }
    int queuePos = 0;
    int activeWorkers = 0;
    int targetWorkers = missing.isEmpty ? 1 : (missing.length < startWorkers ? missing.length : startWorkers);
    int ackedBytes = resumedBytes;
    int lastSampleBytes = resumedBytes;
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
            int i;
            if (_resendQueue.isNotEmpty) {
              i = _resendQueue.removeAt(0);
            } else if (queuePos < missing.length) {
              i = missing[queuePos++];
            } else {
              break;
            }
            if (activeWorkers > targetWorkers && _resendQueue.isEmpty) break;
            final offset = i * chunkSize;
            final len = offset + chunkSize > size ? size - offset : chunkSize;
            await wraf.setPosition(offset);
            final chunk = await wraf.read(len);
            final segHash = await NativeSha256.hashBytes(chunk);

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
      // wait for the receiver's hash verdict before declaring success
      final ok = await _waitVerify();
      await _clearSendSidecar();
      _fileEventCtrl.add(FileEvent(name: _pendingSendName, size: size, isDone: true, ok: ok, sending: true));
    }
    _resumeState = null;
  }

  // ---------- receiving ----------
  void declineIncoming() {
    if (_pendingOfferName == null || _channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'file-decline'}));
    _pendingOfferName = null;
    _pendingOfferSize = 0;
    _pendingOfferId = null;
    _pendingOfferHash = null;
  }

  // ---------- receiving ----------
  Future<void> acceptIncomingFile() async {
    if (_pendingOfferName == null) return;
    final saveDir = await _recvDir();

    final entries = await saveDir.list().toList(); // snapshot, then delete
    for (final e in entries) {
      if (e.path.endsWith('.flova.json') && !e.path.contains(_pendingOfferId!)) {
        try {
          final sc = jsonDecode(await File(e.path).readAsString()) as Map<String, dynamic>;
          final nm = sc['name'] as String?;
          if (nm != null) {
            final part = File('${saveDir.path}/$nm.part');
            if (await part.exists()) await part.delete();
          }
          await File(e.path).delete();
        } catch (_) {}
      }
    }

    if (_recvRaf != null) { try { await _recvRaf!.close(); } catch (_) {} _recvRaf = null; }

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

  Future<void> _handleResumeOffer(Map<String, dynamic> msg) async {
    final transferId = (msg['transferId'] ?? '') as String;
    final size = (msg['size'] as num).toInt();
    final name = (msg['name'] as String).split(Platform.pathSeparator).last;
    if (transferId.isEmpty) {
      _channel?.sink.add(jsonEncode({'type': 'resume-decline', 'transferId': transferId}));
      return;
    }
    try {
      final saveDir = await _recvDir();
      final sidecar = File('${saveDir.path}/.$transferId.flova.json');
      final partFile = File('${saveDir.path}/$name.part');
      if (!await sidecar.exists() || !await partFile.exists()) {
        _channel?.sink.add(jsonEncode({'type': 'resume-decline', 'transferId': transferId}));
        return;
      }
      final sc = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
      if ((sc['size'] as num).toInt() != size) throw Exception('size mismatch');

      final received = (sc['received'] as List? ?? []).map((e) => (e as num).toInt()).toSet();
      if (_recvRaf != null) { try { await _recvRaf!.close(); } catch (_) {} _recvRaf = null; }
      final raf = await partFile.open(mode: FileMode.write);
      _recvRaf = raf;
      _recvPartFile = partFile;
      _recvFinalName = name;
      _recvSize = size;
      _recvTransferId = transferId;
      _recvSaveDir = saveDir;
      _recvExpectedHash = (msg['fileHash'] as String? ?? '').isEmpty ? null : msg['fileHash'] as String;
      _recvReceived
        ..clear()
        ..addAll(received);
      int resumed = 0;
      for (final i in received) {
        final off = i * chunkSize;
        resumed += off + chunkSize > size ? size - off : chunkSize;
      }
      _receivedBytes = resumed;

      _channel?.sink.add(jsonEncode({'type': 'resume-accept', 'transferId': transferId, 'received': received.toList()}));
      final ev = FileEvent(name: name, size: size, sending: false, isResume: true);
      _lastResumeEvent = ev;
      _fileEventCtrl.add(ev);
    } catch (_) {
      _channel?.sink.add(jsonEncode({'type': 'resume-decline', 'transferId': transferId}));
    }
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

    var ok = true;
    final expected = _recvExpectedHash;
    if (expected != null) {
      final actual = await NativeSha256.hashFile(part.path);
      ok = actual == expected;
    }

    // tell the sender the truth first
    _channel?.sink.add(jsonEncode({'type': 'verify-result', 'ok': ok}));

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
    if (_verifyCompleter != null && !_verifyCompleter!.isCompleted) {
      _verifyCompleter!.complete(false);
      _verifyCompleter = null;
    }
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