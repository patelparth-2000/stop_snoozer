import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/alarm_event.dart';

class AlarmHistoryRepository {
  AlarmHistoryRepository._();
  static final AlarmHistoryRepository instance = AlarmHistoryRepository._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(dir.path, 'alarm_history.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE alarm_events (
          id               TEXT PRIMARY KEY,
          stop_id          TEXT NOT NULL,
          stop_name        TEXT NOT NULL,
          fired_at         TEXT NOT NULL,
          distance_metres  REAL NOT NULL DEFAULT 0.0
        )
      '''),
    );
    return _db!;
  }

  Future<void> insert(AlarmEvent event) async {
    final db = await _open();
    await db.insert('alarm_events', event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AlarmEvent>> loadRecent({int limit = 30}) async {
    final db   = await _open();
    final rows = await db.query(
      'alarm_events',
      orderBy: 'fired_at DESC',
      limit: limit,
    );
    return rows.map(AlarmEvent.fromMap).toList();
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('alarm_events');
  }
}
