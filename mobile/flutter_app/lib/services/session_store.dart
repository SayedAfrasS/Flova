/// WORKFLOW OF THIS FILE:
/// 1. Persists the last successful pairing (laptop host, port, peer name)
///    to a small JSON file in the app documents folder.
/// 2. After an app relaunch the welcome screen reads this file and offers a
///    one-tap "Reconnect" instead of forcing a new QR scan.
/// 3. The file is overwritten on every new pairing; a failed load simply
///    means "no saved session", which is a valid state.
///
/// FUNCTIONS:
///  - save() : writes host/port/peerName after a successful hello-ack.
///  - load() : returns the saved session, or null when none exists.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SessionInfo {
  final String host;
  final int port;
  final String peerName;
  const SessionInfo({required this.host, required this.port, required this.peerName});
}

class SessionStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/flova-session.json');
  }

  static Future<void> save({required String host, required int port, required String peerName}) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({'host': host, 'port': port, 'peerName': peerName}));
    } catch (_) {}
  }

  static Future<SessionInfo?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final host = m['host'] as String?;
      final port = m['port'] as num?;
      if (host == null || port == null) return null;
      return SessionInfo(host: host, port: port.toInt(), peerName: m['peerName'] as String? ?? 'Laptop');
    } catch (_) {
      return null;
    }
  }
}