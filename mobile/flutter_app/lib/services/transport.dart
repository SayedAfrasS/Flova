/// WORKFLOW OF THIS FILE:
/// 1. Opens a WebSocket to the desktop server at ws://host:port.
/// 2. Waits for the connection to be ready, then sends a "hello" JSON message.
/// 3. Listens for a "hello-ack" reply and records the peer's name.
/// 4. Emits a stream of TransportState values so the UI can react.
/// 5. Handles errors and remote close by emitting "error" / "disconnected".
///
/// CLASSES / FUNCTIONS:
///  - TransportClient         : owns the channel, peer name and state stream.
///  - TransportClient.connect : opens the socket and sends hello.
///  - TransportClient.disconnect : closes the socket.
///  - TransportState          : the list of possible connection states.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum TransportState { idle, connecting, connected, paired, disconnected, error }

class TransportClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? peerName;

  final StreamController<TransportState> _stateCtrl = StreamController<TransportState>.broadcast();
  Stream<TransportState> get stateStream => _stateCtrl.stream;

  Future<void> connect({
    required String host,
    required int port,
    required String selfName,
    required String platform,
  }) async {
    disconnect();
    _stateCtrl.add(TransportState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      await _channel!.ready;
      _stateCtrl.add(TransportState.connected);

      _channel!.sink.add(jsonEncode({
        'type': 'hello',
        'name': selfName,
        'platform': platform,
      }));

      _sub = _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'hello-ack') {
              peerName = msg['name'] as String?;
              _stateCtrl.add(TransportState.paired);
            }
          } catch (_) {
            // ignore malformed frames
          }
        },
        onDone: () => _stateCtrl.add(TransportState.disconnected),
        onError: (_) => _stateCtrl.add(TransportState.error),
      );
    } catch (_) {
      _stateCtrl.add(TransportState.error);
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
  }
}