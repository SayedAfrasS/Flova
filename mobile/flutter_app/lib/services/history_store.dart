/// WORKFLOW OF THIS FILE:
/// 1. Tiny SQLite helper for transfer history (sqflite, no codegen).
/// 2. Opens flova_history.db in the app databases directory.
/// 3. record() inserts one row per finished file (sent or received).
/// 4. list() returns rows newest-first for the merged Transfers page.
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class HistoryRow {
  final int id;
  final String name;
  final int size;
  final String direction;
  final bool ok;
  final int ts;

  HistoryRow({
    required this.id,
    required this.name,
    required this.size,
    required this.direction,
    required this.ok,
    required this.ts,
  });
}

class HistoryStore {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final file = p.join(dir, 'flova_history.db');
    _db = await openDatabase(file, version: 1, onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE transfers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, size INTEGER, direction TEXT, ok INTEGER, ts INTEGER)',
      );
    });
    return _db!;
  }

  static Future<void> record(String name, int size, String direction, bool ok) async {
    try {
      final db = await _open();
      await db.insert('transfers', {
        'name': name,
        'size': size,
        'direction': direction,
        'ok': ok ? 1 : 0,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static Future<List<HistoryRow>> list({int limit = 100}) async {
    final db = await _open();
    final rows = await db.query('transfers', orderBy: 'ts DESC', limit: limit);
    return rows
        .map((m) => HistoryRow(
              id: m['id'] as int,
              name: m['name'] as String,
              size: m['size'] as int,
              direction: m['direction'] as String,
              ok: (m['ok'] as int) == 1,
              ts: m['ts'] as int,
            ))
        .toList();
  }
}