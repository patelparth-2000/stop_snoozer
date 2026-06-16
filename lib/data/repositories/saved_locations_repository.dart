import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/saved_location.dart';

class SavedLocationsRepository {
  SavedLocationsRepository._();
  static final SavedLocationsRepository instance = SavedLocationsRepository._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(dir.path, 'saved_locations.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE locations (
          id        TEXT PRIMARY KEY,
          stop_id   TEXT NOT NULL,
          stop_name TEXT NOT NULL,
          latitude  REAL NOT NULL,
          longitude REAL NOT NULL,
          mode      TEXT NOT NULL,
          wifi_ssid TEXT,
          radius    REAL NOT NULL DEFAULT 500.0,
          is_active INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
    return _db!;
  }

  Future<List<SavedLocation>> loadAll() async {
    final db   = await _open();
    final rows = await db.query('locations', orderBy: 'stop_name ASC');
    return rows.map(SavedLocation.fromMap).toList();
  }

  Future<void> upsert(SavedLocation loc) async {
    final db = await _open();
    await db.insert('locations', loc.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(SavedLocation loc) async {
    final db = await _open();
    await db.update('locations', loc.toMap(),
        where: 'id = ?', whereArgs: [loc.id]);
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete('locations', where: 'id = ?', whereArgs: [id]);
  }

  /// Deactivates all locations (call before activating a new one).
  Future<void> deactivateAll() async {
    final db = await _open();
    await db.update('locations', {'is_active': 0});
  }
}
