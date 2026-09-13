/// WORKFLOW OF THIS FILE:
/// 1. Manages WebSocket connection and multi-file transfer protocol.
/// 2. Files are received one at a time with offer/accept handshake.
/// 3. Each file gets its own .part file with offset writes.
/// 4. Progress events include file ID for per-file tracking.
/// 5. Supports accepting/declining incoming file offers.
///
/// FUNCTIONS:
///  - connect()           : establish WebSocket connection.
///  - acceptIncoming()    : accept a file offer and prepare to receive.
///  - declineIncoming()   : reject a file offer.
///  - _processQueue()     : receive files sequentially.
///  - _receiveFile()      : handle single file transfer with chunks.
///  - _verifyAndComplete(): verify hash and finalize file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_sha256.dart';

enum TransportState { idle, connecting, connected, disconnected }

class TransportClient {
  WebSocketChannel? _channel;
  TransportState _state = TransportState.idle;
  String? _peerName;

  // Event streams
  final _stateController = StreamController<TransportState>.broadcast();
  final _progressController = StreamController<({String id, int bytes, bool isSending})>.broadcast();
  final _transferStartController = StreamController<({String id, String name, int size, bool isSending})>.broadcast();
  final _doneController = StreamController<({String id, String name, bool isSending, bool verified})>.broadcast();
  final _offerController = StreamController<({String id, String name, int size})>.broadcast();
  final _acceptedController = StreamController<String>.broadcast();
  final _declinedController = StreamController<String>.broadcast();

  Stream<TransportState> get stateStream => _stateController.stream;
  Stream<({String id, int bytes, bool isSending})> get progressStream => _progressController.stream;
  Stream<({String id, String name, int size, bool isSending})> get transferStartStream => _transferStartController.stream;
  Stream<({String id, String name, bool isSending, bool verified})> get doneStream => _doneController.stream;
  Stream<({String id, String name, int size})> get offerStream => _offerController.stream;
  Stream<String> get acceptedStream => _acceptedController.stream;
  Stream<String> get declinedStream => _declinedController.stream;

  TransportState get state => _state;
  String? get peerName => _peerName;

  // Active receive state
  Map<String, _ActiveRecv> _activeReceives = {};
  ({String id, String name, int size, String hash, int chunkSize, int chunkCount})? _pendingOffer;

  Future<void> connect(String host, int port) async {
    _state = TransportState.connecting;
    _stateController.add(_state);

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _state = TransportState.connected;
      _stateController.add(_state);

      _channel!.stream.listen(_handleMessage, onDone: _handleDisconnect, onError: _handleError);
    } catch (e) {
      _state = TransportState.disconnected;
      _stateController.add(_state);
      rethrow;
    }
  }

  void _handleMessage(dynamic data) {
    if (data is String) {
      _handleTextMessage(data);
    } else if (data is List<int>) {
      _handleBinaryMessage(data);
    }
  }

  void _handleTextMessage(String data) {
    try {
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final type = msg['type'] as String;

      switch (type) {
        case 'hello-ack':
          // Connection established
          break;

        case 'ping':
          _channel?.sink.add(jsonEncode({'type': 'pong'}));
          break;

        case 'file-offer':
          _pendingOffer = (
            id: msg['id'] as String,
            name: msg['name'] as String,
            size: msg['size'] as int,
            hash: msg['hash'] as String,
            chunkSize: msg['chunkSize'] as int,
            chunkCount: msg['chunkCount'] as int,
          );
          _offerController.add((
            id: _pendingOffer!.id,
            name: _pendingOffer!.name,
            size: _pendingOffer!.size,
          ));
          break;

        case 'file-end':
          final id = msg['id'] as String;
          _finalizeReceive(id);
          break;

        case 'file-decline':
          final id = msg['id'] as String;
          _declinedController.add(id);
          break;
      }
    } catch (e) {
      print('[transport] Invalid message: $e');
    }
  }

  void _handleBinaryMessage(List<int> data) {
    try {
      final bytes = Uint8List.fromList(data);
      final headerLen = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      final headerBytes = bytes.sublist(4, 4 + headerLen);
      final chunk = bytes.sublist(4 + headerLen);

      final header = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
      if (header['type'] != 'chunk') return;

      final id = header['id'] as String;
      final index = header['index'] as int;
      final hash = header['hash'] as String;

      final active = _activeReceives[id];
      if (active == null) return;

      // Verify chunk hash
      final chunkHash = sha256.convert(chunk).toString();
      if (chunkHash != hash) {
        _channel?.sink.add(jsonEncode({'type': 'chunk-nack', 'id': id, 'index': index}));
        return;
      }

      // Write chunk at offset
      final offset = index * active.chunkSize;
      active.file.setPositionSync(offset);
      active.file.writeFromSync(chunk);

      active.received.add(index);
      _channel?.sink.add(jsonEncode({'type': 'chunk-ack', 'id': id, 'index': index}));
      _progressController.add((id: id, bytes: chunk.length, isSending: false));
    } catch (e) {
      print('[transport] Binary message error: $e');
    }
  }

  void acceptIncoming(String id) {
    if (_pendingOffer?.id != id) return;

    _channel?.sink.add(jsonEncode({'type': 'file-accept', 'id': id}));
    _acceptedController.add(id);

    final offer = _pendingOffer!;
    _pendingOffer = null;

    // Create .part file
    final downloadDir = Directory('/storage/emulated/0/Download/Flova');
    if (!downloadDir.existsSync()) {
      downloadDir.createSync(recursive: true);
    }

    final partPath = '${downloadDir.path}/${offer.name}.part';
    final file = File(partPath);
    file.createSync();
    file.truncateSync(offer.size);

    final raf = file.openSync(mode: FileMode.write);

    _activeReceives[id] = _ActiveRecv(
      file: raf,
      size: offer.size,
      expected: Set.from(List.generate(offer.chunkCount, (i) => i)),
      received: {},
      hash: offer.hash,
      chunkSize: offer.chunkSize,
      name: offer.name,
    );

    _transferStartController.add((
      id: id,
      name: offer.name,
      size: offer.size,
      isSending: false,
    ));
  }

  void declineIncoming(String id) {
    if (_pendingOffer?.id != id) return;
    _channel?.sink.add(jsonEncode({'type': 'file-decline', 'id': id}));
    _pendingOffer = null;
  }

  void _finalizeReceive(String id) {
    final active = _activeReceives.remove(id);
    if (active == null) return;

    active.file.closeSync();

    final downloadDir = Directory('/storage/emulated/0/Download/Flova');
    final partPath = '${downloadDir.path}/${active.name}.part';
    final finalPath = '${downloadDir.path}/${active.name}';

    if (active.received.length == active.expected.length) {
      // All chunks received, verify hash
      final file = File(partPath);
      final bytes = file.readAsBytesSync();
      final hash = sha256.convert(bytes).toString();

      if (hash == active.hash) {
        file.renameSync(finalPath);
        _channel?.sink.add(jsonEncode({'type': 'verify-result', 'id': id, 'ok': true}));
        _doneController.add((id: id, name: active.name, isSending: false, verified: true));
      } else {
        file.deleteSync();
        _channel?.sink.add(jsonEncode({'type': 'verify-result', 'id': id, 'ok': false}));
        _doneController.add((id: id, name: active.name, isSending: false, verified: false));
      }
    } else {
      // Incomplete transfer
      File(partPath).deleteSync();
      _channel?.sink.add(jsonEncode({'type': 'verify-result', 'id': id, 'ok': false}));
      _doneController.add((id: id, name: active.name, isSending: false, verified: false));
    }
  }

  void _handleDisconnect() {
    _state = TransportState.disconnected;
    _stateController.add(_state);
    _channel = null;

    // Clean up active receives
    for (final active in _activeReceives.values) {
      try {
        active.file.closeSync();
      } catch (_) {}
    }
    _activeReceives.clear();
  }

  void _handleError(dynamic error) {
    print('[transport] Error: $error');
    _handleDisconnect();
  }

  void disconnect() {
    _channel?.sink.close();
    _handleDisconnect();
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _progressController.close();
    _transferStartController.close();
    _doneController.close();
    _offerController.close();
    _acceptedController.close();
    _declinedController.close();
  }
}

class _ActiveRecv {
  final RandomAccessFile file;
  final int size;
  final Set<int> expected;
  final Set<int> received;
  final String hash;
  final int chunkSize;
  final String name;

  _ActiveRecv({
    required this.file,
    required this.size,
    required this.expected,
    required this.received,
    required this.hash,
    required this.chunkSize,
    required this.name,
  });
}