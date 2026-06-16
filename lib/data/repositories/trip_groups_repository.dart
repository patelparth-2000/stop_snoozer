import 'dart:convert';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/trip_group.dart';

class TripGroupsRepository {
  TripGroupsRepository._();
  static final TripGroupsRepository instance = TripGroupsRepository._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(dir.path, 'trip_groups.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE groups (
          id        TEXT PRIMARY KEY,
          name      TEXT NOT NULL,
          legs_json TEXT NOT NULL
        )
      '''),
    );
    return _db!;
  }

  Future<List<TripGroup>> loadAll() async {
    final db   = await _open();
    final rows = await db.query('groups', orderBy: 'name ASC');
    return rows.map((r) {
      final legsJson = r['legs_json'] as String;
      final legs     = jsonDecode(legsJson) as List<dynamic>;
      return TripGroup.fromJson({
        'id':   r['id'],
        'name': r['name'],
        'legs': legs,
      });
    }).toList();
  }

  Future<void> save(TripGroup group) async {
    final db = await _open();
    await db.insert(
      'groups',
      {
        'id':        group.id,
        'name':      group.name,
        'legs_json': jsonEncode(group.toJson()['legs']),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TripGroup?> findById(String id) async {
    final db   = await _open();
    final rows = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r        = rows.first;
    final legsJson = r['legs_json'] as String;
    final legs     = jsonDecode(legsJson) as List<dynamic>;
    return TripGroup.fromJson({'id': r['id'], 'name': r['name'], 'legs': legs});
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }
}
