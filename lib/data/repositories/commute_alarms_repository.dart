import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/commute_alarm.dart';

class CommuteAlarmsRepository {
  CommuteAlarmsRepository._();
  static final CommuteAlarmsRepository instance = CommuteAlarmsRepository._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(dir.path, 'commute_alarms.db'),
      version: 3,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE alarms (
          id               TEXT PRIMARY KEY,
          departure_hour   INTEGER NOT NULL,
          departure_minute INTEGER NOT NULL,
          stop_id          TEXT NOT NULL,
          stop_name        TEXT NOT NULL,
          transit_mode     TEXT NOT NULL,
          route_label      TEXT NOT NULL,
          weekdays         TEXT NOT NULL,
          lat              REAL NOT NULL DEFAULT 0.0,
          lon              REAL NOT NULL DEFAULT 0.0,
          wifi_ssid        TEXT,
          specific_date    TEXT,
          is_active        INTEGER NOT NULL DEFAULT 1,
          trip_group_id    TEXT
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE alarms ADD COLUMN lat REAL NOT NULL DEFAULT 0.0');
          await db.execute(
              'ALTER TABLE alarms ADD COLUMN lon REAL NOT NULL DEFAULT 0.0');
          await db.execute('ALTER TABLE alarms ADD COLUMN wifi_ssid TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE alarms ADD COLUMN trip_group_id TEXT');
        }
      },
    );
    return _db!;
  }

  Future<List<CommuteAlarm>> loadAll() async {
    final db = await _open();
    final rows = await db.query(
      'alarms',
      orderBy: 'departure_hour ASC, departure_minute ASC',
    );
    return rows.map(CommuteAlarm.fromMap).toList();
  }

  Future<void> insert(CommuteAlarm alarm) async {
    final db = await _open();
    await db.insert('alarms', alarm.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(CommuteAlarm alarm) async {
    final db = await _open();
    await db.update('alarms', alarm.toMap(),
        where: 'id = ?', whereArgs: [alarm.id]);
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }
}
