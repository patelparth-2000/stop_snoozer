import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/stop_point.dart';
import '../../core/utils/distance_utils.dart';
import '../../core/constants/app_constants.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize({void Function(double)? onProgress}) async {
    if (_ready) return;
    onProgress?.call(0.1);
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'stop_snoozer.db');
    onProgress?.call(0.3);
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
    onProgress?.call(0.7);
    await _seedIfEmpty();
    onProgress?.call(1.0);
    _ready = true;
  }

  Future<void> _onCreate(Database db, int _) async {
    await db.execute('''
      CREATE TABLE stops (
        id       TEXT PRIMARY KEY,
        name     TEXT NOT NULL,
        lat      REAL NOT NULL,
        lng      REAL NOT NULL,
        mode     TEXT NOT NULL,
        wifi_ssid TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_lat  ON stops (lat)');
    await db.execute('CREATE INDEX idx_lng  ON stops (lng)');
    await db.execute('CREATE INDEX idx_wifi ON stops (wifi_ssid)');
  }

  Future<void> _seedIfEmpty() async {
    final db = _db!;
    if ((await db.query('stops', limit: 1)).isNotEmpty) return;
    final rows = [
      {'id': 'UK01', 'name': 'Camden Town Underground Station',   'lat': 51.5392, 'lng': -0.1426, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK02', 'name': 'London Euston Rail Station',        'lat': 51.5281, 'lng': -0.1339, 'mode': 'rail', 'wifi_ssid': null},
      {'id': 'UK03', 'name': 'Stratford Underground Station',     'lat': 51.5416, 'lng': -0.0042, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK04', 'name': 'Stratford Bus Station',             'lat': 51.5413, 'lng': -0.0030, 'mode': 'bus',  'wifi_ssid': null},
      {'id': 'UK05', 'name': 'Stratford International Rail',      'lat': 51.5456, 'lng': -0.0054, 'mode': 'rail', 'wifi_ssid': null},
      {'id': 'UK06', 'name': 'Stratford DLR Station',             'lat': 51.5412, 'lng': -0.0038, 'mode': 'dlr',  'wifi_ssid': null},
      {'id': 'UK07', 'name': 'London Waterloo Station',           'lat': 51.5036, 'lng': -0.1143, 'mode': 'rail', 'wifi_ssid': null},
      {'id': 'UK08', 'name': 'Victoria Underground Station',      'lat': 51.4965, 'lng': -0.1447, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK09', 'name': 'Paddington Rail Station',           'lat': 51.5154, 'lng': -0.1755, 'mode': 'rail', 'wifi_ssid': null},
      {'id': 'UK10', 'name': "King's Cross St Pancras Station",   'lat': 51.5308, 'lng': -0.1238, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK11', 'name': 'London Bridge Station',             'lat': 51.5054, 'lng': -0.0864, 'mode': 'rail', 'wifi_ssid': null},
      {'id': 'UK12', 'name': 'Canary Wharf Underground Station',  'lat': 51.5051, 'lng': -0.0209, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK13', 'name': 'Canary Wharf DLR Station',          'lat': 51.5050, 'lng': -0.0200, 'mode': 'dlr',  'wifi_ssid': null},
      {'id': 'UK14', 'name': 'Brixton Underground Station',       'lat': 51.4627, 'lng': -0.1145, 'mode': 'tube', 'wifi_ssid': 'LUL-Free-Wifi'},
      {'id': 'UK15', 'name': 'Liverpool Street Station',          'lat': 51.5179, 'lng': -0.0823, 'mode': 'rail', 'wifi_ssid': null},
    ];
    final batch = db.batch();
    for (final r in rows) {
      batch.insert('stops', r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<StopPoint>> searchStops(String query) async {
    if (_db == null || query.trim().isEmpty) return [];
    final rows = await _db!.query(
      'stops',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      limit: AppConstants.searchMaxResults,
      orderBy: 'name ASC',
    );
    return rows.map(StopPoint.fromMap).toList();
  }

  Future<List<StopPoint>> getClosestStops(
    double lat, double lon, {
    double radiusKm = AppConstants.searchRadiusKm,
    int limit = 10,
  }) async {
    if (_db == null) return [];
    final box = DistanceUtils.boundingBox(lat: lat, lon: lon, radiusKm: radiusKm);
    final rows = await _db!.query(
      'stops',
      where: 'lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?',
      whereArgs: [box.minLat, box.maxLat, box.minLon, box.maxLon],
    );
    final stops = rows.map(StopPoint.fromMap).toList()
      ..sort((a, b) {
        final dA = DistanceUtils.haversineKm(lat, lon, a.latitude, a.longitude);
        final dB = DistanceUtils.haversineKm(lat, lon, b.latitude, b.longitude);
        return dA.compareTo(dB);
      });
    return stops.take(limit).map((s) => s.copyWith(
          distanceKm: DistanceUtils.haversineKm(lat, lon, s.latitude, s.longitude),
        )).toList();
  }

  Future<StopPoint?> findByWifiSsid(String ssid) async {
    if (_db == null) return null;
    final rows = await _db!.query('stops', where: 'wifi_ssid = ?', whereArgs: [ssid], limit: 1);
    return rows.isEmpty ? null : StopPoint.fromMap(rows.first);
  }
}
