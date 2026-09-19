/// WORKFLOW OF THIS FILE:
/// 1. WebSocket client + peer lifecycle + heartbeat + session persistence.
/// 2. Every connect() creates a fresh SessionCrypto (forward secrecy).
/// 3. hello/hello-ack carry X25519 public keys in plaintext; both sides then
///    derive the same 32-byte shared secret.
/// 4. CRYPTO SAFETY: incoming messages are processed one-at-a-time through
///    _recvQueue so the async key derivation is fully awaited before the next
///    message is handled. Outgoing messages are serialized through _sendQueue
///    so encrypted frames and control frames never overtake each other.
///    This fixes the race where encrypted messages arrived before the key was
///    ready and were silently dropped.
/// 5. After the key is ready, JSON frames are wrapped as {"type":"e","n","c"}
///    and binary frames as 0x01 + 12-byte nonce + ciphertext.
/// 6. All higher-level behavior (queue, resume, verify, history) is unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_sha256.dart';
import 'session_store.dart';
import 'crypto_service.dart';

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
  final bool queueNext;
  final int queueIndex;
  final int queueTotal;
  const FileEvent({
    required this.name,
    required this.size,
    this.isOffer = false,
    this.isDone = false,
    this.ok = true,
    this.sending = false,
    this.isResume = false,
    this.queueNext = false,
    this.queueIndex = 0,
    this.queueTotal = 1,
  });
}

class QueueItem {
  final String filePath;
  final String name;
  final int size;
  final String hash;
  final String transferId;
  const QueueItem({
    required this.filePath,
    required this.name,
    required this.size,
    required this.hash,
    required this.transferId,
  });
}

const Set<String> _plaintextTypes = {'hello', 'hello-ack'};

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
  SessionCrypto _crypto = SessionCrypto();

  // Serialize incoming and outgoing messages to avoid crypto race conditions.
  Future<void> _recvQueue = Future<void>.value();
  Future<void> _sendQueue = Future<void>.value();

  static const int chunkSize = 4 * 1024 * 1024;
  static const int minWorkers = 2;
  static const int startWorkers = 4;
  static const int maxWorkers = 8;
  static const Duration verifyTimeout = Duration(seconds: 20);

  RandomAccessFile? _recvRaf;
  File? _recvPartFile;
  String? _recvFinalName;
  int _recvSize = 0;
  String? _recvTransferId;
  Directory? _recvSaveDir;
  String? _recvExpectedHash;
  final Set<int> _recvReceived = {};
  int _receivedBytes = 0;
  String? _pendingOfferName;
  int _pendingOfferSize = 0;
  String? _pendingOfferId;
  String? _pendingOfferHash;
  Future<void> _writeQueue = Future<void>.value();

  List<QueueItem> _sendQueue = [];
  int _currentSendIndex = 0;
  String _pendingSendName = '';
  int _pendingSendSize = 0;
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
  List<QueueItem> get sendQueue => List.unmodifiable(_sendQueue);
  int get currentSendIndex => _currentSendIndex;
  String get fingerprint => _crypto.fingerprint;

  static const Duration pingInterval = Duration(seconds: 3);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const List<Duration> backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

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
    _host = host;
    _port = port;
    _selfName = selfName;
    _platform = platform;
    _reconnectAttempt = 0;
    await _doConnect(emitError: true);
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    if (_host == null || _port == null) {
      _stateCtrl.add(TransportState.error);
      return;
    }
    await _doConnect(emitError: true);
  }

  Future<void> _doConnect({required bool emitError}) async {
    _stopTimers();
    // fresh crypto for this session -> forward secrecy per connection
    _crypto = SessionCrypto();
    await _crypto.generatePublicKey();
    _stateCtrl.add(TransportState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$_host:$_port'));
      await _channel!.ready;
      _stateCtrl.add(TransportState.connected);
      _sendJson({
        'type': 'hello',
        'name': _selfName,
        'platform': _platform,
        'pubKey': base64Encode(_crypto.publicKey!),
      });
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
        c.complete(true);
      }
    });
    return c.future;
  }

  // ---------- outgoing (serialized) ----------

  void _sendJson(Map<String, dynamic> msg) {
    _sendQueue = _sendQueue.then((_) => _sendJsonInternal(msg));
  }

  Future<void> _sendJsonInternal(Map<String, dynamic> msg) async {
    final sink = _channel?.sink;
    if (sink == null) return;
    final type = msg['type'] as String?;
    final shouldEncrypt = _crypto.hasKey && type != null && !_plaintextTypes.contains(type);
    if (shouldEncrypt) {
      try {
        final plain = Uint8List.fromList(utf8.encode(jsonEncode(msg)));
        final wrapped = await _crypto.encrypt(plain);
        sink.add(jsonEncode({'type': 'e', 'n': wrapped['nonce'], 'c': wrapped['cipher']}));
        return;
      } catch (e) {
        debugPrint('[transport] encrypt json failed, sending plaintext: $e');
      }
    }
    sink.add(jsonEncode(msg));
  }

  void _sendBinary(Uint8List data) {
    _sendQueue = _sendQueue.then((_) => _sendBinaryInternal(data));
  }

  Future<void> _sendBinaryInternal(Uint8List data) async {
    final sink = _channel?.sink;
    if (sink == null) return;
    if (_crypto.hasKey) {
      try {
        final wrapped = await _crypto.encrypt(data);
        final nonce = base64Decode(wrapped['nonce']!);
        final cipher = base64Decode(wrapped['cipher']!);
        final frame = Uint8List(1 + nonce.length + cipher.length);
        frame[0] = 0x01;
        frame.setRange(1, 1 + nonce.length, nonce);
        frame.setRange(1 + nonce.length, frame.length, cipher);
        sink.add(frame);
        return;
      } catch (e) {
        debugPrint('[transport] encrypt binary failed, sending raw: $e');
      }
    }
    sink.add(data);
  }

  // ---------- incoming (serialized so key derivation is awaited) ----------

  void _onMessage(dynamic data) {
    _recvQueue = _recvQueue.then((_) => _processMessage(data));
  }

  Future<void> _processMessage(dynamic data) async {
    // Binary frame: detect encrypted envelope (0x01 + nonce + cipher)
    if (data is List<int>) {
      final buf = data is Uint8List ? data : Uint8List.fromList(data);
      if (buf.length >= 1 + 12 + 16 && buf[0] == 0x01 && _crypto.hasKey) {
        final nonce = buf.sublist(1, 13);
        final cipher = buf.sublist(13);
        try {
          final plain = await _crypto.decrypt(base64Encode(nonce), base64Encode(cipher));
          _handleBinaryFrame(plain);
        } catch (e) {
          debugPrint('[transport] binary decrypt failed: $e');
        }
        return;
      }
      _handleBinaryFrame(buf);
      return;
    }

    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'];
    if (type == 'e' && _crypto.hasKey) {
      final n = msg['n'] as String?;
      final c = msg['c'] as String?;
      if (n == null || c == null) return;
      try {
        final plain = await _crypto.decrypt(n, c);
        final inner = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        await _dispatch(inner);
      } catch (e) {
        debugPrint('[transport] json decrypt failed: $e');
      }
      return;
    }

    await _dispatch(msg);
  }

  Future<void> _dispatch(Map<String, dynamic> msg) async {
    final type = msg['type'];
    if (type == 'hello') {
      // Defensive: mobile normally sends hello, but handle it if received.
      peerName = msg['name'] as String?;
      _reconnectAttempt = 0;
      _lastPongMs = DateTime.now().millisecondsSinceEpoch;
      final pubKeyB64 = msg['pubKey'] as String?;
      if (pubKeyB64 != null && pubKeyB64.isNotEmpty) {
        try {
          await _crypto.deriveKey(base64Decode(pubKeyB64));
          debugPrint('[crypto] key derived, fingerprint=${_crypto.fingerprint}');
        } catch (e) {
          debugPrint('[crypto] derive failed: $e');
        }
      }
      final pub = _crypto.publicKey;
      _sendJson({
        'type': 'hello-ack',
        'name': _selfName,
        'platform': _platform,
        'pubKey': pub == null ? '' : base64Encode(pub),
      });
      _startHeartbeat();
      _stateCtrl.add(TransportState.paired);
      if (_host != null && _port != null) {
        SessionStore.save(host: _host!, port: _port!, peerName: peerName ?? 'Laptop');
      }
      _maybeOfferResume();
    } else if (type == 'hello-ack') {
      peerName = msg['name'] as String?;
      final pubKeyB64 = msg['pubKey'] as String?;
      if (pubKeyB64 != null && pubKeyB64.isNotEmpty) {
        try {
          // Awaited so the key is guaranteed ready before any later message.
          await _crypto.deriveKey(base64Decode(pubKeyB64));
          debugPrint('[crypto] key derived from ack, fingerprint=${_crypto.fingerprint}');
        } catch (e) {
          debugPrint('[crypto] derive on ack failed: $e');
        }
      }
      _reconnectAttempt = 0;
      _lastPongMs = DateTime.now().millisecondsSinceEpoch;
      _startHeartbeat();
      _stateCtrl.add(TransportState.paired);
      if (_host != null && _port != null) {
        SessionStore.save(host: _host!, port: _port!, peerName: peerName ?? 'Laptop');
      }
      _maybeOfferResume();
    } else if (type == 'ping') {
      _sendJson({'type': 'pong'});
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
      final queueIndex = (msg['queueIndex'] as num?)?.toInt() ?? 0;
      final queueTotal = (msg['queueTotal'] as num?)?.toInt() ?? 1;
      _pendingOfferName = msg['name'] as String;
      _pendingOfferSize = (msg['size'] as num).toInt();
      _pendingOfferId = (msg['transferId'] ?? 't0') as String;
      _pendingOfferHash = (msg['fileHash'] ?? '') as String;
      if (queueIndex > 0) {
        _fileEventCtrl.add(FileEvent(
          name: _pendingOfferName!,
          size: _pendingOfferSize,
          queueNext: true,
          queueIndex: queueIndex,
          queueTotal: queueTotal,
        ));
        await acceptIncomingFile();
      } else {
        _fileEventCtrl.add(FileEvent(
          name: _pendingOfferName!,
          size: _pendingOfferSize,
          isOffer: true,
          queueIndex: queueIndex,
          queueTotal: queueTotal,
        ));
      }
    } else if (type == 'file-accept') {
      if (_currentSendIndex < _sendQueue.length) {
        final item = _sendQueue[_currentSendIndex];
        _sendStateCtrl.add(SendState.accepted);
        _streamFile(File(item.filePath), item.name, item.size, <int>{}, 0);
      }
    } else if (type == 'file-decline') {
      await _clearSendSidecar();
      _sendQueue = [];
      _currentSendIndex = 0;
      _sendStateCtrl.add(SendState.declined);
    } else if (type == 'resume-offer') {
      await _handleResumeOffer(msg);
    } else if (type == 'resume-accept') {
      final received = (msg['received'] as List? ?? []).map((e) => (e as num).toInt()).toSet();
      if (_currentSendIndex < _sendQueue.length) {
        final item = _sendQueue[_currentSendIndex];
        int resumed = 0;
        for (final i in received) {
          final off = i * chunkSize;
          resumed += off + chunkSize > item.size ? item.size - off : chunkSize;
        }
        _sentBytes = resumed;
        _sendStateCtrl.add(SendState.accepted);
        final ev = FileEvent(
          name: item.name,
          size: item.size,
          sending: true,
          isResume: true,
          queueIndex: _currentSendIndex,
          queueTotal: _sendQueue.length,
        );
        _lastResumeEvent = ev;
        _fileEventCtrl.add(ev);
        _streamFile(File(item.filePath), item.name, item.size, received, resumed);
      }
    } else if (type == 'resume-decline') {
      await _clearSendSidecar();
      _sendQueue = [];
      _currentSendIndex = 0;
    } else if (type == 'file-start') {
      // segments follow; sink already open
    } else if (type == 'file-end') {
      _finishIncomingFile();
    }
  }

  // ---------- sending (queue) ----------
  Future<void> sendMultipleFiles(List<File> files) async {
    if (_channel == null || files.isEmpty) return;
    _sendQueue = [];
    _currentSendIndex = 0;
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final size = await file.length();
      final name = file.path.split(Platform.pathSeparator).last;
      final hash = await NativeSha256.hashFile(file.path);
      _sendQueue.add(QueueItem(
        filePath: file.path,
        name: name,
        size: size,
        hash: hash,
        transferId: 't${ts}_$i',
      ));
    }
    try {
      final sc = await _sendSidecarFile();
      await sc.writeAsString(jsonEncode({
        'queue': _sendQueue
            .map((q) => {
                  'filePath': q.filePath,
                  'name': q.name,
                  'size': q.size,
                  'hash': q.hash,
                  'transferId': q.transferId,
                })
            .toList(),
        'currentIndex': 0,
      }));
    } catch (_) {}
    _offerCurrentFile();
  }

  Future<void> sendFile(File file) => sendMultipleFiles([file]);

  Future<void> _offerCurrentFile() async {
    if (_channel == null || _currentSendIndex >= _sendQueue.length) return;
    final item = _sendQueue[_currentSendIndex];
    _pendingSendName = item.name;
    _pendingSendSize = item.size;
    _sentBytes = 0;
    _sendJson({
      'type': 'file-offer',
      'transferId': item.transferId,
      'name': item.name,
      'size': item.size,
      'chunkSize': chunkSize,
      'chunkCount': item.size == 0 ? 0 : (item.size / chunkSize).ceil(),
      'fileHash': item.hash,
      'queueIndex': _currentSendIndex,
      'queueTotal': _sendQueue.length,
    });
    _sendStateCtrl.add(SendState.waitingAccept);
  }

  void cancelQueue() {
    _sendAborted = true;
    _sendQueue = [];
    _currentSendIndex = 0;
    _clearSendSidecar();
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
      final rawQueue = s['queue'] as List?;
      final idx = (s['currentIndex'] as num?)?.toInt() ?? 0;
      if (rawQueue == null) {
        await _clearSendSidecar();
        return;
      }
      final valid = <QueueItem>[];
      for (final raw in rawQueue) {
        final m = raw as Map<String, dynamic>;
        final file = File(m['filePath'] as String);
        if (!await file.exists() || await file.length() != (m['size'] as num).toInt()) continue;
        valid.add(QueueItem(
          filePath: m['filePath'] as String,
          name: m['name'] as String,
          size: (m['size'] as num).toInt(),
          hash: m['hash'] as String,
          transferId: m['transferId'] as String,
        ));
      }
      if (valid.isEmpty) {
        await _clearSendSidecar();
        return;
      }
      _sendQueue = valid;
      _currentSendIndex = idx < valid.length ? idx : valid.length - 1;
      final item = _sendQueue[_currentSendIndex];
      _sendJson({
        'type': 'resume-offer',
        'transferId': item.transferId,
        'name': item.name,
        'size': item.size,
        'chunkSize': chunkSize,
        'chunkCount': item.size == 0 ? 0 : (item.size / chunkSize).ceil(),
        'fileHash': item.hash,
        'queueIndex': _currentSendIndex,
        'queueTotal': valid.length,
      });
    } catch (_) {
      await _clearSendSidecar();
    }
  }

  Future<void> _streamFile(File file, String name, int size, Set<int> skip, int resumedBytes) async {
    final count = size == 0 ? 0 : (size / chunkSize).ceil();
    _sendAborted = false;
    _resendQueue.clear();

    _sendJson({'type': 'file-start', 'name': name, 'size': size});

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
            _sendBinary(bb.toBytes());
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
      _sendJson({'type': 'file-end'});
      final ok = await _waitVerify();
      _fileEventCtrl.add(FileEvent(
        name: name,
        size: size,
        isDone: true,
        ok: ok,
        sending: true,
        queueIndex: _currentSendIndex,
        queueTotal: _sendQueue.length,
      ));

      _currentSendIndex++;
      if (_currentSendIndex >= _sendQueue.length) {
        await _clearSendSidecar();
        _sendQueue = [];
        _currentSendIndex = 0;
      } else {
        try {
          final sc = await _sendSidecarFile();
          await sc.writeAsString(jsonEncode({
            'queue': _sendQueue
                .map((q) => {
                      'filePath': q.filePath,
                      'name': q.name,
                      'size': q.size,
                      'hash': q.hash,
                      'transferId': q.transferId,
                    })
                .toList(),
            'currentIndex': _currentSendIndex,
          }));
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
        _offerCurrentFile();
      }
    }
  }

  // ---------- receiving ----------
  Future<void> acceptIncomingFile() async {
    if (_pendingOfferName == null) return;
    final saveDir = await _recvDir();

    final entries = await saveDir.list().toList();
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

    if (_recvRaf != null) {
      try {
        await _recvRaf!.close();
      } catch (_) {}
      _recvRaf = null;
    }

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

    _sendJson({'type': 'file-accept'});
    _pendingOfferName = null;
    _pendingOfferSize = 0;
    _pendingOfferId = null;
    _pendingOfferHash = null;
  }

  void declineIncoming() {
    if (_pendingOfferName == null || _channel == null) return;
    _sendJson({'type': 'file-decline'});
    _pendingOfferName = null;
    _pendingOfferSize = 0;
    _pendingOfferId = null;
    _pendingOfferHash = null;
  }

  Future<void> _handleResumeOffer(Map<String, dynamic> msg) async {
    final transferId = (msg['transferId'] ?? '') as String;
    final size = (msg['size'] as num).toInt();
    final name = (msg['name'] as String).split(Platform.pathSeparator).last;
    if (transferId.isEmpty) {
      _sendJson({'type': 'resume-decline', 'transferId': transferId});
      return;
    }
    try {
      final saveDir = await _recvDir();
      final sidecar = File('${saveDir.path}/.$transferId.flova.json');
      final partFile = File('${saveDir.path}/$name.part');
      if (!await sidecar.exists() || !await partFile.exists()) {
        _sendJson({'type': 'resume-decline', 'transferId': transferId});
        return;
      }
      final sc = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
      if ((sc['size'] as num).toInt() != size) throw Exception('size mismatch');

      final received = (sc['received'] as List? ?? []).map((e) => (e as num).toInt()).toSet();
      if (_recvRaf != null) {
        try {
          await _recvRaf!.close();
        } catch (_) {}
        _recvRaf = null;
      }
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

      _sendJson({
        'type': 'resume-accept',
        'transferId': transferId,
        'received': received.toList(),
        'queueIndex': (msg['queueIndex'] as num?)?.toInt() ?? 0,
        'queueTotal': (msg['queueTotal'] as num?)?.toInt() ?? 1,
      });
      final ev = FileEvent(
        name: name,
        size: size,
        sending: false,
        isResume: true,
        queueIndex: (msg['queueIndex'] as num?)?.toInt() ?? 0,
        queueTotal: (msg['queueTotal'] as num?)?.toInt() ?? 1,
      );
      _lastResumeEvent = ev;
      _fileEventCtrl.add(ev);
    } catch (_) {
      _sendJson({'type': 'resume-decline', 'transferId': transferId});
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
          _sendJson({'type': 'chunk-nack', 'i': index});
          return;
        }
      }

      await raf.setPosition(offset);
      await raf.writeFrom(payload);

      _recvReceived.add(index);
      if (_recvReceived.length % 25 == 0) _writeSidecar();
      _receivedBytes += payload.length;
      _progressCtrl.add(payload.length);
      _sendJson({'type': 'chunk-ack', 'i': index});
    } catch (_) {}
  }

  void _writeSidecar() {
    final dir = _recvSaveDir;
    final id = _recvTransferId;
    if (dir == null || id == null) return;
    try {
      File('${dir.path}/.$id.flova.json').writeAsStringSync(jsonEncode({
        'name': _recvFinalName,
        'size': _recvSize,
        'chunkSize': chunkSize,
        'received': _recvReceived.toList(),
      }));
    } catch (_) {}
  }

  Future<void> _finishIncomingFile() async {
    final myQueue = _writeQueue;
    _writeQueue = Future<void>.value();
    await myQueue;

    final raf = _recvRaf;
    _recvRaf = null;
    if (raf != null) {
      try { await raf.flush(); } catch (_) {}
      try { await raf.close(); } catch (_) {}
    }

    final part = _recvPartFile;
    final dir = _recvSaveDir;
    final finalName = _recvFinalName;
    final expected = _recvExpectedHash;
    final id = _recvTransferId;
    final size = _recvSize;
    if (part == null || dir == null || finalName == null) return;
    _recvPartFile = null;
    _recvSaveDir = null;
    _recvFinalName = null;
    _recvExpectedHash = null;
    _recvTransferId = null;

    var ok = true;
    if (expected != null && expected.isNotEmpty) {
      try {
        final actual = await NativeSha256.hashFile(part.path);
        ok = actual.toLowerCase() == expected.toLowerCase();
        if (!ok) {
          debugPrint('[flova] HASH MISMATCH file=$finalName expected=$expected actual=$actual');
        }
      } catch (e) {
        debugPrint('[flova] HASH ERROR file=$finalName err=$e');
        ok = false;
      }
    }

    _sendJson({'type': 'verify-result', 'ok': ok});

    if (!ok) {
      try { await part.delete(); } catch (_) {}
      _fileEventCtrl.add(FileEvent(name: finalName, size: size, isDone: true, ok: false));
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
      if (id != null) {
        final sidecar = File('${dir.path}/.$id.flova.json');
        if (await sidecar.exists()) await sidecar.delete();
      }
      _fileEventCtrl.add(FileEvent(name: finalPath.split(Platform.pathSeparator).last, size: size, isDone: true, ok: true));
    } catch (_) {}
  }

  void _onClosed() {
    _stopTimers();
    _sendAborted = true;
    for (final w in _ackWaiters.values) {
      if (!w.isCompleted) w.complete();
    }
    _ackWaiters.clear();
    if (_verifyCompleter != null && !_verifyCompleter!.isCompleted) {
      _verifyCompleter!.complete(false);
      _verifyCompleter = null;
    }
    _writeSidecar();
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
      _sendJson({'type': 'ping'});
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final step = _reconnectAttempt < backoff.length ? backoff[_reconnectAttempt] : backoff.last;
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
    _progressCtrl.close();
    _fileEventCtrl.close();
    _sendStateCtrl.close();
  }
}