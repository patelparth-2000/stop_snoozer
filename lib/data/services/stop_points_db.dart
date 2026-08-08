import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/stop_point.dart';
import '../../core/utils/distance_utils.dart';
import '../../core/constants/app_constants.dart';

// ── Isolate message types ─────────────────────────────────────────────────────

class _ProgressMsg {
  const _ProgressMsg(this.value);
  final double value;
}

class _DoneMsg {
  const _DoneMsg();
}

class _ErrorMsg {
  const _ErrorMsg(this.error);
  final String error;
}

class _DecompressParams {
  const _DecompressParams({
    required this.compressedBytes,
    required this.targetPath,
    required this.sendPort,
  });
  final Uint8List compressedBytes;
  final String targetPath;
  final SendPort sendPort;
}

// ── Top-level isolate entry (must NOT be a class method) ─────────────────────

void _decompressIsolateEntry(_DecompressParams params) {
  try {
    params.sendPort.send(const _ProgressMsg(0.25));
    final decompressed = gzip.decode(params.compressedBytes);
    params.sendPort.send(const _ProgressMsg(0.70));
    File(params.targetPath).writeAsBytesSync(Uint8List.fromList(decompressed));
    params.sendPort.send(const _ProgressMsg(0.90));
    params.sendPort.send(const _DoneMsg());
  } catch (e) {
    params.sendPort.send(_ErrorMsg(e.toString()));
  }
}

/// Live statistics about the on-device database, for the diagnostics screen.
class DbStats {
  const DbStats({
    required this.available,
    this.stopCount = 0,
    this.pageSizeBytes = 0,
    this.schemaVersion = 0,
    this.fileSizeBytes = 0,
    this.routeSequenceCount = 0,
    this.runTimeCount = 0,
    this.stationDepthCount = 0,
    this.hasFtsIndex = false,
  });

  final bool available;
  final int stopCount;
  final int pageSizeBytes;
  final int schemaVersion;
  final int fileSizeBytes;

  /// Zero means no topology data — underground tracking is unavailable and the
  /// app falls back to GPS. Worth surfacing, since it is invisible otherwise.
  final int routeSequenceCount;
  final int runTimeCount;
  final int stationDepthCount;
  final bool hasFtsIndex;

  bool get hasTopology => routeSequenceCount > 0;

  static const unavailable = DbStats(available: false);
}

// ── StopPointsDb singleton ────────────────────────────────────────────────────

/// SQLite singleton for the UK NaPTAN stop-points database.
///
/// First boot: decompresses [_assetPath] via a background Flutter Isolate
/// (no UI jank), then opens the resulting [_dbFileName].  Subsequent boots
/// skip decompression and open the cached file directly.
class StopPointsDb {
  StopPointsDb._();
  static final StopPointsDb instance = StopPointsDb._();

  static const String _assetPath   = 'assets/uk.db.gz';
  static const String _dbFileName  = 'uk.db';
  // Matches SCHEMA_VERSION in tools/build_naptan_db.py. An on-device database
  // below this is migrated in place by _migrate() — see the note there on why
  // this does not trigger re-extraction.
  //   v3 — StopPointsFts full-text index
  //   v4 — route topology + runtime Fingerprints table
  //   v5 — StationDepths keyed by (stop_id, line_id); RunTimes.peak_seconds
  //   v6 — StationDepths.platform_level_asl_m + Elevation table: the barometer
  //        matches altitude differences, which depth below a local street
  //        cannot express
  static const int _requiredVersion = 6;

  Database? _db;

  bool get isReady => _db != null;

  /// Direct handle for repositories that query tables beyond StopPoints
  /// (route topology, fingerprints). Null until [initialize] completes.
  Database? get rawDb => _db;

  /// Live database statistics for the diagnostics screen.
  ///
  /// Queried rather than hardcoded: the previous screen displayed fixed strings
  /// which silently became wrong as soon as the bundled asset was regenerated.
  Future<DbStats> stats() async {
    final db = _db;
    if (db == null) return DbStats.unavailable;
    try {
      Future<int> count(String sql) async {
        final r = await db.rawQuery(sql);
        return (r.first.values.first as num?)?.toInt() ?? 0;
      }

      final stops = await count('SELECT COUNT(*) FROM StopPoints');
      final pageSize = await count('PRAGMA page_size');
      final version = await count('PRAGMA user_version');

      // Topology tables exist from v4 but may legitimately be empty.
      int sequences = 0, runTimes = 0, depths = 0;
      try {
        sequences = await count('SELECT COUNT(*) FROM RouteSequences');
        runTimes = await count('SELECT COUNT(*) FROM RunTimes');
        depths = await count('SELECT COUNT(*) FROM StationDepths');
      } catch (_) {/* pre-v4 database */}

      int bytes = 0;
      try {
        final path = db.path;
        final f = File(path);
        if (f.existsSync()) bytes = f.lengthSync();
      } catch (_) {}

      return DbStats(
        available: true,
        stopCount: stops,
        pageSizeBytes: pageSize,
        schemaVersion: version,
        fileSizeBytes: bytes,
        routeSequenceCount: sequences,
        runTimeCount: runTimes,
        stationDepthCount: depths,
        hasFtsIndex: await _hasFts(),
      );
    } catch (_) {
      return DbStats.unavailable;
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> initialize({void Function(double)? onProgress}) async {
    if (_db != null) return;

    final dir    = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbFileName);

    if (!File(dbPath).existsSync()) {
      await _decompressAsset(dbPath, onProgress: onProgress);
    } else if (await _isUnreadable(dbPath)) {
      // Corrupt or truncated (interrupted first-run extraction) — start over.
      await File(dbPath).delete();
      await _decompressAsset(dbPath, onProgress: onProgress);
    } else {
      onProgress?.call(0.85);
    }

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onOpen: (db) async {
        await _migrate(db);
        onProgress?.call(1.0);
      },
    );
  }

  /// Brings an existing database up to [_requiredVersion] in place.
  ///
  /// Migration rather than re-extraction, deliberately: the bundled asset may
  /// itself predate the current schema (it is regenerated by a separate tooling
  /// step, not on every code change). Keying re-extraction off `user_version`
  /// would then delete and re-unpack the asset on *every* launch while never
  /// actually gaining the new tables. Creating what is missing is both cheaper
  /// and correct regardless of which asset revision shipped.
  ///
  /// Every statement is idempotent, so running this on an already-current
  /// database costs a few `IF NOT EXISTS` checks.
  Future<void> _migrate(Database db) async {
    final version = await _userVersion(db);
    if (version >= _requiredVersion) return;

    // v3 — full-text search index
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_name ON StopPoints(name);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_type ON StopPoints(transit_type);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_latlon '
      'ON StopPoints(latitude, longitude);',
    );
    await _createFtsIndex(db);

    // v5 — StationDepths gained a line_id primary-key component and RunTimes a
    // peak_seconds column. `CREATE TABLE IF NOT EXISTS` cannot alter an
    // existing table, so a v4 database needs these dropped first.
    //
    // Safe to drop: both are read-only reference data sourced from the bundled
    // asset, never user-generated. Fingerprints is deliberately NOT dropped —
    // that one *is* user data, learned on their journeys.
    if (version >= 4 && version < 5) {
      await db.execute('DROP TABLE IF EXISTS StationDepths');
      await db.execute('DROP TABLE IF EXISTS RunTimes');
    }

    // v6 — StationDepths gained platform_level_asl_m. Same reasoning as the v5
    // drop above: reference data from the bundled asset, never user-generated,
    // so recreating it is safe. An asset older than v6 has no altitudes to
    // carry over anyway, and the engine falls back to depth matching until a
    // v6 asset ships.
    if (version >= 5 && version < 6) {
      await db.execute('DROP TABLE IF EXISTS StationDepths');
    }

    // v4 — route topology. Created empty when the asset has no topology data;
    // the underground engine treats an empty sequence as "no plan available"
    // and the app falls back to GPS geofencing.
    await _createTopologySchema(db);

    await db.execute('PRAGMA user_version = $_requiredVersion');
  }

  Future<int> _userVersion(Database db) async {
    try {
      final rows = await db.rawQuery('PRAGMA user_version');
      return rows.first.values.first as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// True when the file cannot be opened or has no StopPoints table at all.
  Future<bool> _isUnreadable(String dbPath) async {
    Database? db;
    try {
      db = await openDatabase(dbPath);
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='StopPoints'",
      );
      return rows.isEmpty;
    } catch (_) {
      return true;
    } finally {
      await db?.close();
    }
  }

  /// Full-text stop search. [transitTypes] narrows by `transit_type` column.
  ///
  /// Uses the FTS5 prefix index built by tools/build_naptan_db.py. Falls back to
  /// a LIKE scan only when that index is absent (a pre-v3 extracted database, or
  /// a build of SQLite without FTS5) — correct but slow on 500k rows, so the
  /// fallback is a safety net, not a supported path.
  Future<List<StopPoint>> searchStops(
    String query, {
    List<String>? transitTypes,
  }) async {
    final db = _db;
    if (db == null) return const [];
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty) return const [];

    if (await _hasFts()) {
      try {
        return await _searchFts(db, q, transitTypes);
      } on DatabaseException {
        // Corrupt or partially-built index — degrade rather than fail the search.
        _ftsAvailable = false;
      }
    }
    return _searchLike(db, q, transitTypes);
  }

  /// Builds an FTS5 MATCH expression that prefix-matches every token, so
  /// "toot bro" finds "Tooting Broadway" while the user is still typing.
  ///
  /// Each token is double-quoted (embedded quotes doubled) so that FTS5
  /// operators the user happens to type — NOT, OR, NEAR, ^, : — are treated as
  /// literal text instead of syntax. Without this, a query like "St. John's"
  /// or a bare "-" raises a syntax error mid-keystroke.
  static String buildFtsMatchQuery(String input) {
    final tokens = input
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty);
    return tokens.map((t) => '"${t.replaceAll('"', '""')}"*').join(' ');
  }

  Future<List<StopPoint>> _searchFts(
    Database db,
    String q,
    List<String>? transitTypes,
  ) async {
    final match = buildFtsMatchQuery(q);
    if (match.isEmpty) return const [];

    final filterByType = transitTypes != null && transitTypes.isNotEmpty;
    final typeClause = filterByType
        ? 'AND s.transit_type IN (${List.filled(transitTypes.length, '?').join(',')})'
        : '';

    // Ordering, in priority order:
    //   1. names that *start with* the query — almost always what was meant
    //   2. rail/underground before bus: for "toot" a commuter wants Tooting
    //      Broadway station, not "Tooting High Street (Stop TB)"
    //   3. shorter names, then alphabetical, so results are stable
    // The LIKE is evaluated only against the FTS candidate set, never the table.
    final rows = await db.rawQuery(
      'SELECT s.* FROM StopPointsFts f '
      'JOIN StopPoints s ON s.rowid = f.rowid '
      'WHERE StopPointsFts MATCH ? $typeClause '
      'ORDER BY (CASE WHEN s.name LIKE ? THEN 0 ELSE 1 END), '
      '         (CASE s.transit_type '
      "            WHEN 'underground' THEN 0 WHEN 'train' THEN 0 "
      "            WHEN 'dlr' THEN 1 WHEN 'tram' THEN 1 "
      "            WHEN 'ferry' THEN 2 ELSE 3 END), "
      '         length(s.name) ASC, s.name ASC '
      'LIMIT ${AppConstants.searchMaxResults}',
      [match, ...?(filterByType ? transitTypes : null), '$q%'],
    );
    return rows.map(StopPoint.fromMap).toList();
  }

  Future<List<StopPoint>> _searchLike(
    Database db,
    String q,
    List<String>? transitTypes,
  ) async {
    if (transitTypes == null || transitTypes.isEmpty) {
      final rows = await db.query(
        'StopPoints',
        where: 'name LIKE ?',
        whereArgs: ['%$q%'],
        limit: AppConstants.searchMaxResults,
        orderBy: 'name ASC',
      );
      return rows.map(StopPoint.fromMap).toList();
    }

    final ph = List.filled(transitTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM StopPoints '
      'WHERE name LIKE ? AND transit_type IN ($ph) '
      'ORDER BY name ASC LIMIT ${AppConstants.searchMaxResults}',
      ['%$q%', ...transitTypes],
    );
    return rows.map(StopPoint.fromMap).toList();
  }

  /// Cached probe for the FTS5 index. Checked once per app run.
  bool? _ftsAvailable;

  Future<bool> _hasFts() async {
    final cached = _ftsAvailable;
    if (cached != null) return cached;
    final db = _db;
    if (db == null) return false;
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name='StopPointsFts' LIMIT 1",
      );
      return _ftsAvailable = rows.isNotEmpty;
    } catch (_) {
      return _ftsAvailable = false;
    }
  }

  Future<List<StopPoint>> getClosestStops(
    double lat,
    double lon, {
    double radiusKm = AppConstants.searchRadiusKm,
    int limit = 10,
    List<String>? transitTypes,
  }) async {
    final db = _db;
    if (db == null) return const [];
    final box = DistanceUtils.boundingBox(lat: lat, lon: lon, radiusKm: radiusKm);

    late final List<Map<String, Object?>> rows;
    if (transitTypes == null || transitTypes.isEmpty) {
      rows = await db.query(
        'StopPoints',
        where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
        whereArgs: [box.minLat, box.maxLat, box.minLon, box.maxLon],
      );
    } else {
      final ph = List.filled(transitTypes.length, '?').join(',');
      rows = await db.rawQuery(
        'SELECT * FROM StopPoints '
        'WHERE latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ? '
        'AND transit_type IN ($ph)',
        [box.minLat, box.maxLat, box.minLon, box.maxLon, ...transitTypes],
      );
    }

    final stops = rows.map(StopPoint.fromMap).toList()
      ..sort((a, b) {
        final dA = DistanceUtils.haversineKm(lat, lon, a.latitude, a.longitude);
        final dB = DistanceUtils.haversineKm(lat, lon, b.latitude, b.longitude);
        return dA.compareTo(dB);
      });
    return stops
        .take(limit)
        .map((s) => s.copyWith(
              distanceKm: DistanceUtils.haversineKm(lat, lon, s.latitude, s.longitude),
            ))
        .toList();
  }

  Future<StopPoint?> findByWifiSsid(String ssid) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      'StopPoints',
      where: 'wifi_ssid = ?',
      whereArgs: [ssid],
      limit: 1,
    );
    return rows.isEmpty ? null : StopPoint.fromMap(rows.first);
  }

  // ── Decompression ─────────────────────────────────────────────────────────

  // rootBundle.load() MUST run on the main thread; Isolate handles the
  // CPU-intensive gzip.decode() + file write.
  Future<void> _decompressAsset(
    String targetPath, {
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(0.05);

    late Uint8List compressedBytes;
    try {
      final bd = await rootBundle.load(_assetPath);
      compressedBytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      onProgress?.call(0.10);
    } catch (_) {
      // Asset not bundled (dev mode without uk.db.gz) — use seed database.
      await _openWithSeed(targetPath, onProgress: onProgress);
      return;
    }

    final receivePort = ReceivePort();
    final completer   = Completer<void>();

    receivePort.listen((msg) {
      if (msg is _ProgressMsg) {
        onProgress?.call(msg.value);
      } else if (msg is _DoneMsg) {
        receivePort.close();
        completer.complete();
      } else if (msg is _ErrorMsg) {
        receivePort.close();
        completer.completeError(Exception(msg.error));
      }
    });

    await Isolate.spawn(
      _decompressIsolateEntry,
      _DecompressParams(
        compressedBytes: compressedBytes,
        targetPath: targetPath,
        sendPort: receivePort.sendPort,
      ),
    );

    await completer.future;
  }

  // ── Schema (fallback / seed path) ────────────────────────────────────────

  Future<void> _onCreate(Database db, int _) async {
    // 16 KB page-size for Android 16 KB segment-size compatibility.
    await db.execute('PRAGMA page_size = 16384;');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS StopPoints (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        transit_type TEXT NOT NULL,
        latitude     REAL NOT NULL,
        longitude    REAL NOT NULL,
        wifi_ssid    TEXT,
        indicator    TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_name ON StopPoints(name);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_type ON StopPoints(transit_type);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stop_latlon '
      'ON StopPoints(latitude, longitude);',
    );
  }

  /// Mirrors build_search_index() in tools/build_naptan_db.py so the dev-seed
  /// path exercises the same FTS5 query code as the shipped asset. Without this,
  /// search would silently take the LIKE fallback in every dev build and the
  /// real query would go untested until release.
  Future<void> _createFtsIndex(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS StopPointsFts USING fts5(
          name,
          content='StopPoints',
          content_rowid='rowid',
          tokenize="unicode61 remove_diacritics 2",
          prefix='2 3 4'
        )
      ''');
      final counts = await db.rawQuery('SELECT count(*) AS c FROM StopPointsFts');
      if ((counts.first['c'] as int? ?? 0) == 0) {
        await db.execute(
          'INSERT INTO StopPointsFts(rowid, name) SELECT rowid, name FROM StopPoints',
        );
      }
    } catch (_) {
      // No FTS5 in this SQLite build — searchStops() falls back to LIKE.
      _ftsAvailable = false;
    }
  }

  /// Mirrors create_topology_schema() in tools/build_naptan_db.py.
  ///
  /// Kept in sync by hand. If these diverge, the app will read columns the
  /// generated asset does not have, so treat any change here as requiring the
  /// same change there (and a SCHEMA_VERSION bump in both).
  Future<void> _createTopologySchema(Database db) async {
    const statements = [
      '''
      CREATE TABLE IF NOT EXISTS Lines (
        line_id TEXT PRIMARY KEY, name TEXT NOT NULL,
        mode TEXT NOT NULL, colour TEXT
      )''',
      '''
      CREATE TABLE IF NOT EXISTS RouteSequences (
        line_id   TEXT NOT NULL, direction TEXT NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        seq_index INTEGER NOT NULL, stop_id TEXT NOT NULL,
        PRIMARY KEY (line_id, direction, branch_id, seq_index)
      )''',
      'CREATE INDEX IF NOT EXISTS idx_seq_stop ON RouteSequences(stop_id)',
      'CREATE INDEX IF NOT EXISTS idx_seq_line_dir '
          'ON RouteSequences(line_id, direction, branch_id, seq_index)',
      '''
      CREATE TABLE IF NOT EXISTS Branches (
        line_id TEXT NOT NULL, direction TEXT NOT NULL,
        stop_id TEXT NOT NULL, branch_id INTEGER NOT NULL,
        branch_label TEXT,
        PRIMARY KEY (line_id, direction, stop_id, branch_id)
      )''',
      // `seconds` is the UNIMPEDED run time (train moving, no holds) — a
      // physical floor, used as the timing gate's lower bound. `peak_seconds`
      // informs the upper bound only, so congestion widens the window without
      // raising the floor and rejecting legitimate fast off-peak runs.
      '''
      CREATE TABLE IF NOT EXISTS RunTimes (
        line_id TEXT NOT NULL, from_stop TEXT NOT NULL, to_stop TEXT NOT NULL,
        seconds INTEGER NOT NULL, peak_seconds INTEGER,
        source TEXT NOT NULL DEFAULT 'estimate',
        PRIMARY KEY (line_id, from_stop, to_stop)
      )''',
      // Keyed by (stop_id, line_id): depth is a property of the platform, not
      // the station. Bank is 20.5 m on the Central line and 29.6 m on the
      // Northern — a station-level average would be ~9 m wrong at exactly the
      // interchanges where the barometer needs to be precise.
      //
      // platform_level_asl_m is what the barometer is actually matched
      // against. A barometer reads a *change* in altitude, so the expected
      // reading between two stations is the difference of their platform
      // altitudes. depth_metres cannot express that — it is measured from each
      // station's own street, and streets differ by up to ~76 m across the
      // network against a 12 m tolerance. Depth is kept for display.
      '''
      CREATE TABLE IF NOT EXISTS StationDepths (
        stop_id TEXT NOT NULL, line_id TEXT NOT NULL DEFAULT '',
        depth_metres REAL NOT NULL,
        platform_level_asl_m REAL,
        source TEXT NOT NULL DEFAULT 'estimate',
        PRIMARY KEY (stop_id, line_id)
      )''',
      // Ground elevation, metres above Ordnance Datum, from OS Terrain 50.
      // For Underground stations it converts a published depth into an
      // altitude; for the DLR, Elizabeth line and Overground — where no open
      // dataset publishes platform depths at all — it *is* the platform
      // altitude, and the only barometric prior those lines get.
      '''
      CREATE TABLE IF NOT EXISTS Elevation (
        stop_id TEXT PRIMARY KEY,
        ground_elev_m REAL NOT NULL,
        easting INTEGER, northing INTEGER,
        source TEXT NOT NULL DEFAULT 'os_terrain_50'
      )''',
      // U13 — self-learned fingerprints. Device-local and never uploaded; this
      // one is not in the shipped asset because it is written at runtime.
      '''
      CREATE TABLE IF NOT EXISTS Fingerprints (
        stop_id      TEXT NOT NULL,
        kind         TEXT NOT NULL,          -- 'bssid' | 'cell'
        identifier   TEXT NOT NULL,
        observations INTEGER NOT NULL DEFAULT 1,
        last_seen_ms INTEGER NOT NULL,
        PRIMARY KEY (stop_id, kind, identifier)
      )''',
      'CREATE INDEX IF NOT EXISTS idx_fp_lookup '
          'ON Fingerprints(kind, identifier)',
    ];
    for (final s in statements) {
      await db.execute(s);
    }
  }

  /// Creates a fresh seeded database when uk.db.gz is absent (dev builds).
  Future<void> _openWithSeed(
    String targetPath, {
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(0.20);
    _db = await openDatabase(
      targetPath,
      version: 1,
      onCreate: _onCreate,
    );
    onProgress?.call(0.50);
    await _seedData(_db!);
    // Must run after seeding: the FTS table is populated from StopPoints.
    await _createFtsIndex(_db!);
    await _createTopologySchema(_db!);
    await _db!.execute('PRAGMA user_version = $_requiredVersion');
    onProgress?.call(1.00);
  }

  // ── Seed data (~430 UK stops) ─────────────────────────────────────────────

  Future<void> _seedData(Database db) async {
    if ((await db.query('StopPoints', limit: 1)).isNotEmpty) return;
    final batch = db.batch();
    for (final r in _kSeedStops) {
      batch.insert('StopPoints', r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}

// ── Seed dataset ─────────────────────────────────────────────────────────────
// Covers all London Underground lines, Elizabeth Line, DLR, Overground,
// and major UK National Rail termini — ~430 unique stops.

const _w = 'LUL-Free-Wifi';

const List<Map<String, Object?>> _kSeedStops = [
  // ── Northern Line ─────────────────────────────────────────────────────────
  {'id':'NL01','name':'Morden Underground Station',              'transit_type':'underground','latitude':51.4023,'longitude':-0.1948,'wifi_ssid':_w},
  {'id':'NL02','name':'South Wimbledon Underground Station',     'transit_type':'underground','latitude':51.4108,'longitude':-0.1921,'wifi_ssid':_w},
  {'id':'NL03','name':'Colliers Wood Underground Station',       'transit_type':'underground','latitude':51.4193,'longitude':-0.1886,'wifi_ssid':_w},
  {'id':'NL04','name':'Tooting Broadway Underground Station',    'transit_type':'underground','latitude':51.4272,'longitude':-0.1680,'wifi_ssid':_w},
  {'id':'NL05','name':'Tooting Bec Underground Station',         'transit_type':'underground','latitude':51.4354,'longitude':-0.1610,'wifi_ssid':_w},
  {'id':'NL06','name':'Balham Underground Station',              'transit_type':'underground','latitude':51.4430,'longitude':-0.1527,'wifi_ssid':_w},
  {'id':'NL07','name':'Clapham South Underground Station',       'transit_type':'underground','latitude':51.4523,'longitude':-0.1480,'wifi_ssid':_w},
  {'id':'NL08','name':'Clapham Common Underground Station',      'transit_type':'underground','latitude':51.4611,'longitude':-0.1398,'wifi_ssid':_w},
  {'id':'NL09','name':'Clapham North Underground Station',       'transit_type':'underground','latitude':51.4650,'longitude':-0.1304,'wifi_ssid':_w},
  {'id':'NL10','name':'Stockwell Underground Station',           'transit_type':'underground','latitude':51.4722,'longitude':-0.1227,'wifi_ssid':_w},
  {'id':'NL11','name':'Oval Underground Station',                'transit_type':'underground','latitude':51.4823,'longitude':-0.1131,'wifi_ssid':_w},
  {'id':'NL12','name':'Kennington Underground Station',          'transit_type':'underground','latitude':51.4884,'longitude':-0.1051,'wifi_ssid':_w},
  {'id':'NL13','name':'Elephant & Castle Underground Station',   'transit_type':'underground','latitude':51.4948,'longitude':-0.1001,'wifi_ssid':_w},
  {'id':'NL14','name':'Borough Underground Station',             'transit_type':'underground','latitude':51.5011,'longitude':-0.0945,'wifi_ssid':_w},
  {'id':'NL15','name':'London Bridge Underground Station',       'transit_type':'underground','latitude':51.5054,'longitude':-0.0864,'wifi_ssid':_w},
  {'id':'NL16','name':'Bank Underground Station',                'transit_type':'underground','latitude':51.5133,'longitude':-0.0886,'wifi_ssid':_w},
  {'id':'NL17','name':'Moorgate Underground Station',            'transit_type':'underground','latitude':51.5186,'longitude':-0.0885,'wifi_ssid':_w},
  {'id':'NL18','name':'Old Street Underground Station',          'transit_type':'underground','latitude':51.5255,'longitude':-0.0875,'wifi_ssid':_w},
  {'id':'NL19','name':'Angel Underground Station',               'transit_type':'underground','latitude':51.5324,'longitude':-0.1059,'wifi_ssid':_w},
  {'id':'NL20','name':"King's Cross St Pancras Underground Station",'transit_type':'underground','latitude':51.5308,'longitude':-0.1238,'wifi_ssid':_w},
  {'id':'NL21','name':'Euston Underground Station',              'transit_type':'underground','latitude':51.5281,'longitude':-0.1339,'wifi_ssid':_w},
  {'id':'NL22','name':'Warren Street Underground Station',       'transit_type':'underground','latitude':51.5242,'longitude':-0.1384,'wifi_ssid':_w},
  {'id':'NL23','name':'Goodge Street Underground Station',       'transit_type':'underground','latitude':51.5200,'longitude':-0.1350,'wifi_ssid':_w},
  {'id':'NL24','name':'Tottenham Court Road Underground Station','transit_type':'underground','latitude':51.5165,'longitude':-0.1300,'wifi_ssid':_w},
  {'id':'NL25','name':'Leicester Square Underground Station',    'transit_type':'underground','latitude':51.5113,'longitude':-0.1281,'wifi_ssid':_w},
  {'id':'NL26','name':'Charing Cross Underground Station',       'transit_type':'underground','latitude':51.5080,'longitude':-0.1247,'wifi_ssid':_w},
  {'id':'NL27','name':'Embankment Underground Station',          'transit_type':'underground','latitude':51.5073,'longitude':-0.1223,'wifi_ssid':_w},
  {'id':'NL28','name':'Waterloo Underground Station',            'transit_type':'underground','latitude':51.5036,'longitude':-0.1143,'wifi_ssid':_w},
  {'id':'NL29','name':'Camden Town Underground Station',         'transit_type':'underground','latitude':51.5392,'longitude':-0.1426,'wifi_ssid':_w},
  {'id':'NL30','name':'Chalk Farm Underground Station',          'transit_type':'underground','latitude':51.5443,'longitude':-0.1497,'wifi_ssid':_w},
  {'id':'NL31','name':'Belsize Park Underground Station',        'transit_type':'underground','latitude':51.5503,'longitude':-0.1642,'wifi_ssid':_w},
  {'id':'NL32','name':'Hampstead Underground Station',           'transit_type':'underground','latitude':51.5568,'longitude':-0.1778,'wifi_ssid':_w},
  {'id':'NL33','name':'Golders Green Underground Station',       'transit_type':'underground','latitude':51.5720,'longitude':-0.1943,'wifi_ssid':_w},
  {'id':'NL34','name':'Brent Cross Underground Station',         'transit_type':'underground','latitude':51.5765,'longitude':-0.2133,'wifi_ssid':_w},
  {'id':'NL35','name':'Hendon Central Underground Station',      'transit_type':'underground','latitude':51.5840,'longitude':-0.2261,'wifi_ssid':_w},
  {'id':'NL36','name':'Mill Hill East Underground Station',      'transit_type':'underground','latitude':51.6085,'longitude':-0.2044,'wifi_ssid':_w},
  {'id':'NL37','name':'Edgware Underground Station',             'transit_type':'underground','latitude':51.6135,'longitude':-0.2752,'wifi_ssid':_w},
  {'id':'NL38','name':'Kentish Town Underground Station',        'transit_type':'underground','latitude':51.5502,'longitude':-0.1408,'wifi_ssid':_w},
  {'id':'NL39','name':'Tufnell Park Underground Station',        'transit_type':'underground','latitude':51.5565,'longitude':-0.1380,'wifi_ssid':_w},
  {'id':'NL40','name':'Archway Underground Station',             'transit_type':'underground','latitude':51.5654,'longitude':-0.1353,'wifi_ssid':_w},
  {'id':'NL41','name':'Highgate Underground Station',            'transit_type':'underground','latitude':51.5777,'longitude':-0.1488,'wifi_ssid':_w},
  {'id':'NL42','name':'East Finchley Underground Station',       'transit_type':'underground','latitude':51.5873,'longitude':-0.1659,'wifi_ssid':_w},
  {'id':'NL43','name':'Finchley Central Underground Station',    'transit_type':'underground','latitude':51.5988,'longitude':-0.1921,'wifi_ssid':_w},
  {'id':'NL44','name':'West Finchley Underground Station',       'transit_type':'underground','latitude':51.6099,'longitude':-0.1941,'wifi_ssid':_w},
  {'id':'NL45','name':'Woodside Park Underground Station',       'transit_type':'underground','latitude':51.6217,'longitude':-0.1849,'wifi_ssid':_w},
  {'id':'NL46','name':'Totteridge & Whetstone Underground Station','transit_type':'underground','latitude':51.6305,'longitude':-0.1804,'wifi_ssid':_w},
  {'id':'NL47','name':'High Barnet Underground Station',         'transit_type':'underground','latitude':51.6505,'longitude':-0.1949,'wifi_ssid':_w},
  {'id':'NL48','name':'Battersea Power Station Underground Station','transit_type':'underground','latitude':51.4824,'longitude':-0.1419,'wifi_ssid':_w},
  {'id':'NL49','name':'Nine Elms Underground Station',           'transit_type':'underground','latitude':51.4871,'longitude':-0.1268,'wifi_ssid':_w},

  // ── Victoria Line ─────────────────────────────────────────────────────────
  {'id':'VL01','name':'Walthamstow Central Underground Station', 'transit_type':'underground','latitude':51.5832,'longitude':-0.0196,'wifi_ssid':_w},
  {'id':'VL02','name':'Blackhorse Road Underground Station',     'transit_type':'underground','latitude':51.5866,'longitude':-0.0423,'wifi_ssid':_w},
  {'id':'VL03','name':'Tottenham Hale Underground Station',      'transit_type':'underground','latitude':51.5883,'longitude':-0.0596,'wifi_ssid':_w},
  {'id':'VL04','name':'Seven Sisters Underground Station',       'transit_type':'underground','latitude':51.5824,'longitude':-0.0726,'wifi_ssid':_w},
  {'id':'VL05','name':'Finsbury Park Underground Station',       'transit_type':'underground','latitude':51.5643,'longitude':-0.1059,'wifi_ssid':_w},
  {'id':'VL06','name':'Highbury & Islington Underground Station','transit_type':'underground','latitude':51.5463,'longitude':-0.1039,'wifi_ssid':_w},
  {'id':'VL07','name':'Oxford Circus Underground Station',       'transit_type':'underground','latitude':51.5154,'longitude':-0.1416,'wifi_ssid':_w},
  {'id':'VL08','name':'Green Park Underground Station',          'transit_type':'underground','latitude':51.5067,'longitude':-0.1428,'wifi_ssid':_w},
  {'id':'VL09','name':'Victoria Underground Station',            'transit_type':'underground','latitude':51.4965,'longitude':-0.1447,'wifi_ssid':_w},
  {'id':'VL10','name':'Pimlico Underground Station',             'transit_type':'underground','latitude':51.4893,'longitude':-0.1334,'wifi_ssid':_w},
  {'id':'VL11','name':'Vauxhall Underground Station',            'transit_type':'underground','latitude':51.4859,'longitude':-0.1226,'wifi_ssid':_w},
  {'id':'VL12','name':'Brixton Underground Station',             'transit_type':'underground','latitude':51.4627,'longitude':-0.1145,'wifi_ssid':_w},

  // ── Jubilee Line ──────────────────────────────────────────────────────────
  {'id':'JL01','name':'Stanmore Underground Station',            'transit_type':'underground','latitude':51.6195,'longitude':-0.3026,'wifi_ssid':_w},
  {'id':'JL02','name':'Canons Park Underground Station',         'transit_type':'underground','latitude':51.6079,'longitude':-0.2948,'wifi_ssid':_w},
  {'id':'JL03','name':'Queensbury Underground Station',          'transit_type':'underground','latitude':51.5942,'longitude':-0.2861,'wifi_ssid':_w},
  {'id':'JL04','name':'Kingsbury Underground Station',           'transit_type':'underground','latitude':51.5847,'longitude':-0.2787,'wifi_ssid':_w},
  {'id':'JL05','name':'Wembley Park Underground Station',        'transit_type':'underground','latitude':51.5631,'longitude':-0.2793,'wifi_ssid':_w},
  {'id':'JL06','name':'Neasden Underground Station',             'transit_type':'underground','latitude':51.5548,'longitude':-0.2550,'wifi_ssid':_w},
  {'id':'JL07','name':'Dollis Hill Underground Station',         'transit_type':'underground','latitude':51.5519,'longitude':-0.2351,'wifi_ssid':_w},
  {'id':'JL08','name':'Willesden Green Underground Station',     'transit_type':'underground','latitude':51.5490,'longitude':-0.2195,'wifi_ssid':_w},
  {'id':'JL09','name':'Kilburn Underground Station',             'transit_type':'underground','latitude':51.5458,'longitude':-0.2042,'wifi_ssid':_w},
  {'id':'JL10','name':'West Hampstead Underground Station',      'transit_type':'underground','latitude':51.5477,'longitude':-0.1907,'wifi_ssid':_w},
  {'id':'JL11','name':'Finchley Road Underground Station',       'transit_type':'underground','latitude':51.5475,'longitude':-0.1800,'wifi_ssid':_w},
  {'id':'JL12','name':'Swiss Cottage Underground Station',       'transit_type':'underground','latitude':51.5432,'longitude':-0.1738,'wifi_ssid':_w},
  {'id':'JL13','name':"St John's Wood Underground Station",      'transit_type':'underground','latitude':51.5349,'longitude':-0.1737,'wifi_ssid':_w},
  {'id':'JL14','name':'Baker Street Underground Station',        'transit_type':'underground','latitude':51.5226,'longitude':-0.1571,'wifi_ssid':_w},
  {'id':'JL15','name':'Bond Street Underground Station',         'transit_type':'underground','latitude':51.5142,'longitude':-0.1493,'wifi_ssid':_w},
  {'id':'JL16','name':'Westminster Underground Station',         'transit_type':'underground','latitude':51.5010,'longitude':-0.1248,'wifi_ssid':_w},
  {'id':'JL17','name':'Southwark Underground Station',           'transit_type':'underground','latitude':51.5040,'longitude':-0.1050,'wifi_ssid':_w},
  {'id':'JL18','name':'Bermondsey Underground Station',          'transit_type':'underground','latitude':51.4994,'longitude':-0.0640,'wifi_ssid':_w},
  {'id':'JL19','name':'Canada Water Underground Station',        'transit_type':'underground','latitude':51.4979,'longitude':-0.0491,'wifi_ssid':_w},
  {'id':'JL20','name':'Canary Wharf Underground Station',        'transit_type':'underground','latitude':51.5051,'longitude':-0.0209,'wifi_ssid':_w},
  {'id':'JL21','name':'North Greenwich Underground Station',     'transit_type':'underground','latitude':51.5003,'longitude': 0.0040,'wifi_ssid':_w},
  {'id':'JL22','name':'Canning Town Underground Station',        'transit_type':'underground','latitude':51.5145,'longitude': 0.0082,'wifi_ssid':_w},
  {'id':'JL23','name':'West Ham Underground Station',            'transit_type':'underground','latitude':51.5287,'longitude': 0.0054,'wifi_ssid':_w},
  {'id':'JL24','name':'Stratford Underground Station',           'transit_type':'underground','latitude':51.5416,'longitude':-0.0042,'wifi_ssid':_w},

  // ── Bakerloo Line ─────────────────────────────────────────────────────────
  {'id':'BL01','name':'Harrow & Wealdstone Underground Station', 'transit_type':'underground','latitude':51.5793,'longitude':-0.3352,'wifi_ssid':_w},
  {'id':'BL02','name':'Kenton Underground Station',              'transit_type':'underground','latitude':51.5810,'longitude':-0.3168,'wifi_ssid':_w},
  {'id':'BL03','name':'South Kenton Underground Station',        'transit_type':'underground','latitude':51.5710,'longitude':-0.3079,'wifi_ssid':_w},
  {'id':'BL04','name':'North Wembley Underground Station',       'transit_type':'underground','latitude':51.5630,'longitude':-0.3042,'wifi_ssid':_w},
  {'id':'BL05','name':'Wembley Central Underground Station',     'transit_type':'underground','latitude':51.5522,'longitude':-0.2963,'wifi_ssid':_w},
  {'id':'BL06','name':'Stonebridge Park Underground Station',    'transit_type':'underground','latitude':51.5449,'longitude':-0.2759,'wifi_ssid':_w},
  {'id':'BL07','name':'Harlesden Underground Station',           'transit_type':'underground','latitude':51.5361,'longitude':-0.2578,'wifi_ssid':_w},
  {'id':'BL08','name':'Willesden Junction Underground Station',  'transit_type':'underground','latitude':51.5323,'longitude':-0.2474,'wifi_ssid':_w},
  {'id':'BL09','name':'Kensal Green Underground Station',        'transit_type':'underground','latitude':51.5278,'longitude':-0.2251,'wifi_ssid':_w},
  {'id':'BL10','name':"Queen's Park Underground Station",        'transit_type':'underground','latitude':51.5344,'longitude':-0.2047,'wifi_ssid':_w},
  {'id':'BL11','name':'Kilburn Park Underground Station',        'transit_type':'underground','latitude':51.5353,'longitude':-0.1942,'wifi_ssid':_w},
  {'id':'BL12','name':'Maida Vale Underground Station',          'transit_type':'underground','latitude':51.5301,'longitude':-0.1856,'wifi_ssid':_w},
  {'id':'BL13','name':'Warwick Avenue Underground Station',      'transit_type':'underground','latitude':51.5233,'longitude':-0.1841,'wifi_ssid':_w},
  {'id':'BL14','name':'Paddington Underground Station',          'transit_type':'underground','latitude':51.5154,'longitude':-0.1755,'wifi_ssid':_w},
  {'id':'BL15','name':'Edgware Road Underground Station',        'transit_type':'underground','latitude':51.5201,'longitude':-0.1672,'wifi_ssid':_w},
  {'id':'BL16','name':'Marylebone Underground Station',          'transit_type':'underground','latitude':51.5226,'longitude':-0.1631,'wifi_ssid':_w},
  {'id':'BL17','name':"Regent's Park Underground Station",       'transit_type':'underground','latitude':51.5234,'longitude':-0.1465,'wifi_ssid':_w},
  {'id':'BL18','name':'Piccadilly Circus Underground Station',   'transit_type':'underground','latitude':51.5100,'longitude':-0.1340,'wifi_ssid':_w},
  {'id':'BL19','name':'Lambeth North Underground Station',       'transit_type':'underground','latitude':51.4990,'longitude':-0.1118,'wifi_ssid':_w},

  // ── Central Line ──────────────────────────────────────────────────────────
  {'id':'CL01','name':'Ealing Broadway Underground Station',     'transit_type':'underground','latitude':51.5150,'longitude':-0.3012,'wifi_ssid':_w},
  {'id':'CL02','name':'West Acton Underground Station',          'transit_type':'underground','latitude':51.5158,'longitude':-0.2800,'wifi_ssid':_w},
  {'id':'CL03','name':'North Acton Underground Station',         'transit_type':'underground','latitude':51.5233,'longitude':-0.2675,'wifi_ssid':_w},
  {'id':'CL04','name':'East Acton Underground Station',          'transit_type':'underground','latitude':51.5168,'longitude':-0.2558,'wifi_ssid':_w},
  {'id':'CL05','name':'White City Underground Station',          'transit_type':'underground','latitude':51.5116,'longitude':-0.2270,'wifi_ssid':_w},
  {'id':'CL06','name':"Shepherd's Bush Underground Station",     'transit_type':'underground','latitude':51.5051,'longitude':-0.2187,'wifi_ssid':_w},
  {'id':'CL07','name':'Holland Park Underground Station',        'transit_type':'underground','latitude':51.5070,'longitude':-0.2063,'wifi_ssid':_w},
  {'id':'CL08','name':'Notting Hill Gate Underground Station',   'transit_type':'underground','latitude':51.5093,'longitude':-0.1965,'wifi_ssid':_w},
  {'id':'CL09','name':'Queensway Underground Station',           'transit_type':'underground','latitude':51.5109,'longitude':-0.1871,'wifi_ssid':_w},
  {'id':'CL10','name':'Lancaster Gate Underground Station',      'transit_type':'underground','latitude':51.5121,'longitude':-0.1755,'wifi_ssid':_w},
  {'id':'CL11','name':'Marble Arch Underground Station',         'transit_type':'underground','latitude':51.5135,'longitude':-0.1589,'wifi_ssid':_w},
  {'id':'CL12','name':'Holborn Underground Station',             'transit_type':'underground','latitude':51.5174,'longitude':-0.1205,'wifi_ssid':_w},
  {'id':'CL13','name':'Chancery Lane Underground Station',       'transit_type':'underground','latitude':51.5175,'longitude':-0.1112,'wifi_ssid':_w},
  {'id':'CL14','name':"St Paul's Underground Station",           'transit_type':'underground','latitude':51.5152,'longitude':-0.0975,'wifi_ssid':_w},
  {'id':'CL15','name':'Liverpool Street Underground Station',    'transit_type':'underground','latitude':51.5179,'longitude':-0.0823,'wifi_ssid':_w},
  {'id':'CL16','name':'Bethnal Green Underground Station',       'transit_type':'underground','latitude':51.5268,'longitude':-0.0553,'wifi_ssid':_w},
  {'id':'CL17','name':'Mile End Underground Station',            'transit_type':'underground','latitude':51.5250,'longitude':-0.0334,'wifi_ssid':_w},
  {'id':'CL18','name':'Leyton Underground Station',              'transit_type':'underground','latitude':51.5564,'longitude':-0.0059,'wifi_ssid':_w},
  {'id':'CL19','name':'Leytonstone Underground Station',         'transit_type':'underground','latitude':51.5681,'longitude': 0.0085,'wifi_ssid':_w},
  {'id':'CL20','name':'Snaresbrook Underground Station',         'transit_type':'underground','latitude':51.5803,'longitude': 0.0207,'wifi_ssid':_w},
  {'id':'CL21','name':'South Woodford Underground Station',      'transit_type':'underground','latitude':51.5918,'longitude': 0.0275,'wifi_ssid':_w},
  {'id':'CL22','name':'Woodford Underground Station',            'transit_type':'underground','latitude':51.6076,'longitude': 0.0274,'wifi_ssid':_w},
  {'id':'CL23','name':'Buckhurst Hill Underground Station',      'transit_type':'underground','latitude':51.6279,'longitude': 0.0471,'wifi_ssid':_w},
  {'id':'CL24','name':'Loughton Underground Station',            'transit_type':'underground','latitude':51.6413,'longitude': 0.0569,'wifi_ssid':_w},
  {'id':'CL25','name':'Debden Underground Station',              'transit_type':'underground','latitude':51.6463,'longitude': 0.0838,'wifi_ssid':_w},
  {'id':'CL26','name':'Theydon Bois Underground Station',        'transit_type':'underground','latitude':51.6718,'longitude': 0.1031,'wifi_ssid':_w},
  {'id':'CL27','name':'Epping Underground Station',              'transit_type':'underground','latitude':51.6937,'longitude': 0.1138,'wifi_ssid':_w},
  {'id':'CL28','name':'Wanstead Underground Station',            'transit_type':'underground','latitude':51.5775,'longitude': 0.0285,'wifi_ssid':_w},
  {'id':'CL29','name':'Redbridge Underground Station',           'transit_type':'underground','latitude':51.5774,'longitude': 0.0504,'wifi_ssid':_w},
  {'id':'CL30','name':'Gants Hill Underground Station',          'transit_type':'underground','latitude':51.5767,'longitude': 0.0716,'wifi_ssid':_w},
  {'id':'CL31','name':'Newbury Park Underground Station',        'transit_type':'underground','latitude':51.5765,'longitude': 0.0901,'wifi_ssid':_w},
  {'id':'CL32','name':'Barkingside Underground Station',         'transit_type':'underground','latitude':51.5851,'longitude': 0.0972,'wifi_ssid':_w},
  {'id':'CL33','name':'Fairlop Underground Station',             'transit_type':'underground','latitude':51.5943,'longitude': 0.0889,'wifi_ssid':_w},
  {'id':'CL34','name':'Hainault Underground Station',            'transit_type':'underground','latitude':51.6017,'longitude': 0.0920,'wifi_ssid':_w},
  {'id':'CL35','name':'Grange Hill Underground Station',         'transit_type':'underground','latitude':51.6009,'longitude': 0.0862,'wifi_ssid':_w},
  {'id':'CL36','name':'Chigwell Underground Station',            'transit_type':'underground','latitude':51.6358,'longitude': 0.0680,'wifi_ssid':_w},
  {'id':'CL37','name':'Roding Valley Underground Station',       'transit_type':'underground','latitude':51.6291,'longitude': 0.0403,'wifi_ssid':_w},
  {'id':'CL38','name':'West Ruislip Underground Station',        'transit_type':'underground','latitude':51.5701,'longitude':-0.4396,'wifi_ssid':_w},
  {'id':'CL39','name':'Ruislip Gardens Underground Station',     'transit_type':'underground','latitude':51.5614,'longitude':-0.4198,'wifi_ssid':_w},
  {'id':'CL40','name':'South Ruislip Underground Station',       'transit_type':'underground','latitude':51.5561,'longitude':-0.3994,'wifi_ssid':_w},
  {'id':'CL41','name':'Northolt Underground Station',            'transit_type':'underground','latitude':51.5483,'longitude':-0.3686,'wifi_ssid':_w},
  {'id':'CL42','name':'Greenford Underground Station',           'transit_type':'underground','latitude':51.5421,'longitude':-0.3464,'wifi_ssid':_w},
  {'id':'CL43','name':'Perivale Underground Station',            'transit_type':'underground','latitude':51.5390,'longitude':-0.3215,'wifi_ssid':_w},
  {'id':'CL44','name':'Hanger Lane Underground Station',         'transit_type':'underground','latitude':51.5303,'longitude':-0.2967,'wifi_ssid':_w},

  // ── District Line ─────────────────────────────────────────────────────────
  {'id':'DT01','name':'Richmond Underground Station',            'transit_type':'underground','latitude':51.4627,'longitude':-0.3012,'wifi_ssid':_w},
  {'id':'DT02','name':'Kew Gardens Underground Station',         'transit_type':'underground','latitude':51.4773,'longitude':-0.2849,'wifi_ssid':_w},
  {'id':'DT03','name':'Gunnersbury Underground Station',         'transit_type':'underground','latitude':51.4918,'longitude':-0.2393,'wifi_ssid':_w},
  {'id':'DT04','name':'Turnham Green Underground Station',       'transit_type':'underground','latitude':51.4952,'longitude':-0.2545,'wifi_ssid':_w},
  {'id':'DT05','name':'Stamford Brook Underground Station',      'transit_type':'underground','latitude':51.4948,'longitude':-0.2441,'wifi_ssid':_w},
  {'id':'DT06','name':'Ravenscourt Park Underground Station',    'transit_type':'underground','latitude':51.4925,'longitude':-0.2350,'wifi_ssid':_w},
  {'id':'DT07','name':'Hammersmith Underground Station',         'transit_type':'underground','latitude':51.4924,'longitude':-0.2242,'wifi_ssid':_w},
  {'id':'DT08','name':'Barons Court Underground Station',        'transit_type':'underground','latitude':51.4899,'longitude':-0.2134,'wifi_ssid':_w},
  {'id':'DT09','name':'West Kensington Underground Station',     'transit_type':'underground','latitude':51.4904,'longitude':-0.2072,'wifi_ssid':_w},
  {'id':'DT10','name':"Earl's Court Underground Station",        'transit_type':'underground','latitude':51.4922,'longitude':-0.1937,'wifi_ssid':_w},
  {'id':'DT11','name':'High Street Kensington Underground Station','transit_type':'underground','latitude':51.5010,'longitude':-0.1921,'wifi_ssid':_w},
  {'id':'DT12','name':'Bayswater Underground Station',           'transit_type':'underground','latitude':51.5122,'longitude':-0.1874,'wifi_ssid':_w},
  {'id':'DT13','name':'Sloane Square Underground Station',       'transit_type':'underground','latitude':51.4923,'longitude':-0.1568,'wifi_ssid':_w},
  {'id':'DT14','name':'South Kensington Underground Station',    'transit_type':'underground','latitude':51.4941,'longitude':-0.1738,'wifi_ssid':_w},
  {'id':'DT15','name':'Gloucester Road Underground Station',     'transit_type':'underground','latitude':51.4942,'longitude':-0.1831,'wifi_ssid':_w},
  {'id':'DT16','name':'West Brompton Underground Station',       'transit_type':'underground','latitude':51.4867,'longitude':-0.1952,'wifi_ssid':_w},
  {'id':'DT17','name':'Fulham Broadway Underground Station',     'transit_type':'underground','latitude':51.4803,'longitude':-0.1961,'wifi_ssid':_w},
  {'id':'DT18','name':'Parsons Green Underground Station',       'transit_type':'underground','latitude':51.4752,'longitude':-0.2005,'wifi_ssid':_w},
  {'id':'DT19','name':'Putney Bridge Underground Station',       'transit_type':'underground','latitude':51.4665,'longitude':-0.2094,'wifi_ssid':_w},
  {'id':'DT20','name':'East Putney Underground Station',         'transit_type':'underground','latitude':51.4620,'longitude':-0.2122,'wifi_ssid':_w},
  {'id':'DT21','name':'Southfields Underground Station',         'transit_type':'underground','latitude':51.4438,'longitude':-0.2068,'wifi_ssid':_w},
  {'id':'DT22','name':'Wimbledon Park Underground Station',      'transit_type':'underground','latitude':51.4346,'longitude':-0.2054,'wifi_ssid':_w},
  {'id':'DT23','name':'Wimbledon Underground Station',           'transit_type':'underground','latitude':51.4213,'longitude':-0.2068,'wifi_ssid':_w},
  {'id':'DT24','name':"St James's Park Underground Station",     'transit_type':'underground','latitude':51.4993,'longitude':-0.1342,'wifi_ssid':_w},
  {'id':'DT25','name':'Temple Underground Station',              'transit_type':'underground','latitude':51.5113,'longitude':-0.1138,'wifi_ssid':_w},
  {'id':'DT26','name':'Blackfriars Underground Station',         'transit_type':'underground','latitude':51.5121,'longitude':-0.1040,'wifi_ssid':_w},
  {'id':'DT27','name':'Mansion House Underground Station',       'transit_type':'underground','latitude':51.5124,'longitude':-0.0945,'wifi_ssid':_w},
  {'id':'DT28','name':'Cannon Street Underground Station',       'transit_type':'underground','latitude':51.5114,'longitude':-0.0906,'wifi_ssid':_w},
  {'id':'DT29','name':'Monument Underground Station',            'transit_type':'underground','latitude':51.5104,'longitude':-0.0862,'wifi_ssid':_w},
  {'id':'DT30','name':'Tower Hill Underground Station',          'transit_type':'underground','latitude':51.5098,'longitude':-0.0766,'wifi_ssid':_w},
  {'id':'DT31','name':'Aldgate East Underground Station',        'transit_type':'underground','latitude':51.5148,'longitude':-0.0719,'wifi_ssid':_w},
  {'id':'DT32','name':'Whitechapel Underground Station',         'transit_type':'underground','latitude':51.5194,'longitude':-0.0594,'wifi_ssid':_w},
  {'id':'DT33','name':'Stepney Green Underground Station',       'transit_type':'underground','latitude':51.5224,'longitude':-0.0467,'wifi_ssid':_w},
  {'id':'DT34','name':'Bow Road Underground Station',            'transit_type':'underground','latitude':51.5272,'longitude':-0.0248,'wifi_ssid':_w},
  {'id':'DT35','name':'Bromley-by-Bow Underground Station',      'transit_type':'underground','latitude':51.5234,'longitude':-0.0101,'wifi_ssid':_w},
  {'id':'DT36','name':'Plaistow Underground Station',            'transit_type':'underground','latitude':51.5316,'longitude': 0.0205,'wifi_ssid':_w},
  {'id':'DT37','name':'Upton Park Underground Station',          'transit_type':'underground','latitude':51.5354,'longitude': 0.0349,'wifi_ssid':_w},
  {'id':'DT38','name':'East Ham Underground Station',            'transit_type':'underground','latitude':51.5401,'longitude': 0.0477,'wifi_ssid':_w},
  {'id':'DT39','name':'Barking Underground Station',             'transit_type':'underground','latitude':51.5397,'longitude': 0.0814,'wifi_ssid':_w},
  {'id':'DT40','name':'Upney Underground Station',               'transit_type':'underground','latitude':51.5381,'longitude': 0.0991,'wifi_ssid':_w},
  {'id':'DT41','name':'Becontree Underground Station',           'transit_type':'underground','latitude':51.5397,'longitude': 0.1138,'wifi_ssid':_w},
  {'id':'DT42','name':'Dagenham Heathway Underground Station',   'transit_type':'underground','latitude':51.5401,'longitude': 0.1387,'wifi_ssid':_w},
  {'id':'DT43','name':'Dagenham East Underground Station',       'transit_type':'underground','latitude':51.5449,'longitude': 0.1666,'wifi_ssid':_w},
  {'id':'DT44','name':'Elm Park Underground Station',            'transit_type':'underground','latitude':51.5485,'longitude': 0.1898,'wifi_ssid':_w},
  {'id':'DT45','name':'Hornchurch Underground Station',          'transit_type':'underground','latitude':51.5534,'longitude': 0.2152,'wifi_ssid':_w},
  {'id':'DT46','name':'Upminster Bridge Underground Station',    'transit_type':'underground','latitude':51.5568,'longitude': 0.2360,'wifi_ssid':_w},
  {'id':'DT47','name':'Upminster Underground Station',           'transit_type':'underground','latitude':51.5591,'longitude': 0.2511,'wifi_ssid':_w},

  // ── Piccadilly Line ───────────────────────────────────────────────────────
  {'id':'PL01','name':'Heathrow Terminals 2 & 3 Underground Station','transit_type':'underground','latitude':51.4773,'longitude':-0.4614,'wifi_ssid':_w},
  {'id':'PL02','name':'Heathrow Terminal 4 Underground Station',  'transit_type':'underground','latitude':51.4588,'longitude':-0.4482,'wifi_ssid':_w},
  {'id':'PL03','name':'Heathrow Terminal 5 Underground Station',  'transit_type':'underground','latitude':51.4724,'longitude':-0.4890,'wifi_ssid':_w},
  {'id':'PL04','name':'Hatton Cross Underground Station',          'transit_type':'underground','latitude':51.4677,'longitude':-0.4233,'wifi_ssid':_w},
  {'id':'PL05','name':'Hounslow West Underground Station',         'transit_type':'underground','latitude':51.4734,'longitude':-0.3862,'wifi_ssid':_w},
  {'id':'PL06','name':'Hounslow Central Underground Station',      'transit_type':'underground','latitude':51.4726,'longitude':-0.3679,'wifi_ssid':_w},
  {'id':'PL07','name':'Hounslow East Underground Station',         'transit_type':'underground','latitude':51.4722,'longitude':-0.3479,'wifi_ssid':_w},
  {'id':'PL08','name':'Osterley Underground Station',              'transit_type':'underground','latitude':51.4804,'longitude':-0.3508,'wifi_ssid':_w},
  {'id':'PL09','name':'Boston Manor Underground Station',          'transit_type':'underground','latitude':51.4990,'longitude':-0.3331,'wifi_ssid':_w},
  {'id':'PL10','name':'Northfields Underground Station',           'transit_type':'underground','latitude':51.4997,'longitude':-0.3147,'wifi_ssid':_w},
  {'id':'PL11','name':'South Ealing Underground Station',          'transit_type':'underground','latitude':51.5007,'longitude':-0.3071,'wifi_ssid':_w},
  {'id':'PL12','name':'Ealing Common Underground Station',         'transit_type':'underground','latitude':51.5100,'longitude':-0.2876,'wifi_ssid':_w},
  {'id':'PL13','name':'Acton Town Underground Station',            'transit_type':'underground','latitude':51.5030,'longitude':-0.2804,'wifi_ssid':_w},
  {'id':'PL14','name':'Hyde Park Corner Underground Station',      'transit_type':'underground','latitude':51.5025,'longitude':-0.1526,'wifi_ssid':_w},
  {'id':'PL15','name':'Knightsbridge Underground Station',         'transit_type':'underground','latitude':51.5014,'longitude':-0.1608,'wifi_ssid':_w},
  {'id':'PL16','name':'Covent Garden Underground Station',         'transit_type':'underground','latitude':51.5129,'longitude':-0.1243,'wifi_ssid':_w},
  {'id':'PL17','name':'Russell Square Underground Station',        'transit_type':'underground','latitude':51.5234,'longitude':-0.1244,'wifi_ssid':_w},
  {'id':'PL18','name':'Caledonian Road Underground Station',       'transit_type':'underground','latitude':51.5430,'longitude':-0.1190,'wifi_ssid':_w},
  {'id':'PL19','name':'Holloway Road Underground Station',         'transit_type':'underground','latitude':51.5522,'longitude':-0.1153,'wifi_ssid':_w},
  {'id':'PL20','name':'Arsenal Underground Station',               'transit_type':'underground','latitude':51.5578,'longitude':-0.1051,'wifi_ssid':_w},
  {'id':'PL21','name':'Manor House Underground Station',           'transit_type':'underground','latitude':51.5706,'longitude':-0.0944,'wifi_ssid':_w},
  {'id':'PL22','name':'Turnpike Lane Underground Station',         'transit_type':'underground','latitude':51.5906,'longitude':-0.1028,'wifi_ssid':_w},
  {'id':'PL23','name':'Wood Green Underground Station',            'transit_type':'underground','latitude':51.6018,'longitude':-0.1096,'wifi_ssid':_w},
  {'id':'PL24','name':'Bounds Green Underground Station',          'transit_type':'underground','latitude':51.6065,'longitude':-0.1234,'wifi_ssid':_w},
  {'id':'PL25','name':'Arnos Grove Underground Station',           'transit_type':'underground','latitude':51.6161,'longitude':-0.1336,'wifi_ssid':_w},
  {'id':'PL26','name':'Southgate Underground Station',             'transit_type':'underground','latitude':51.6322,'longitude':-0.1274,'wifi_ssid':_w},
  {'id':'PL27','name':'Oakwood Underground Station',               'transit_type':'underground','latitude':51.6470,'longitude':-0.1323,'wifi_ssid':_w},
  {'id':'PL28','name':'Cockfosters Underground Station',           'transit_type':'underground','latitude':51.6517,'longitude':-0.1496,'wifi_ssid':_w},
  {'id':'PL29','name':'Rayners Lane Underground Station',          'transit_type':'underground','latitude':51.5753,'longitude':-0.3715,'wifi_ssid':_w},
  {'id':'PL30','name':'South Harrow Underground Station',          'transit_type':'underground','latitude':51.5641,'longitude':-0.3490,'wifi_ssid':_w},
  {'id':'PL31','name':'Sudbury Hill Underground Station',          'transit_type':'underground','latitude':51.5568,'longitude':-0.3335,'wifi_ssid':_w},
  {'id':'PL32','name':'Sudbury Town Underground Station',          'transit_type':'underground','latitude':51.5497,'longitude':-0.3154,'wifi_ssid':_w},
  {'id':'PL33','name':'Alperton Underground Station',              'transit_type':'underground','latitude':51.5398,'longitude':-0.2990,'wifi_ssid':_w},
  {'id':'PL34','name':'Park Royal Underground Station',            'transit_type':'underground','latitude':51.5267,'longitude':-0.2870,'wifi_ssid':_w},
  {'id':'PL35','name':'North Ealing Underground Station',          'transit_type':'underground','latitude':51.5227,'longitude':-0.3026,'wifi_ssid':_w},

  // ── Circle / H&C ──────────────────────────────────────────────────────────
  {'id':'HC01','name':'Great Portland Street Underground Station', 'transit_type':'underground','latitude':51.5243,'longitude':-0.1436,'wifi_ssid':_w},
  {'id':'HC02','name':'Euston Square Underground Station',         'transit_type':'underground','latitude':51.5261,'longitude':-0.1355,'wifi_ssid':_w},
  {'id':'HC03','name':'Farringdon Underground Station',            'transit_type':'underground','latitude':51.5203,'longitude':-0.1053,'wifi_ssid':_w},
  {'id':'HC04','name':'Barbican Underground Station',              'transit_type':'underground','latitude':51.5204,'longitude':-0.0977,'wifi_ssid':_w},
  {'id':'HC05','name':'Aldgate Underground Station',               'transit_type':'underground','latitude':51.5141,'longitude':-0.0756,'wifi_ssid':_w},
  {'id':'HC06','name':'Goldhawk Road Underground Station',         'transit_type':'underground','latitude':51.5020,'longitude':-0.2272,'wifi_ssid':_w},
  {'id':'HC07','name':"Shepherd's Bush Market Underground Station",'transit_type':'underground','latitude':51.5052,'longitude':-0.2271,'wifi_ssid':_w},
  {'id':'HC08','name':'Wood Lane Underground Station',             'transit_type':'underground','latitude':51.5088,'longitude':-0.2249,'wifi_ssid':_w},
  {'id':'HC09','name':'Latimer Road Underground Station',          'transit_type':'underground','latitude':51.5112,'longitude':-0.2218,'wifi_ssid':_w},
  {'id':'HC10','name':'Westbourne Park Underground Station',       'transit_type':'underground','latitude':51.5212,'longitude':-0.2021,'wifi_ssid':_w},
  {'id':'HC11','name':'Royal Oak Underground Station',             'transit_type':'underground','latitude':51.5179,'longitude':-0.1878,'wifi_ssid':_w},

  // ── Metropolitan Line ─────────────────────────────────────────────────────
  {'id':'MT01','name':'Preston Road Underground Station',          'transit_type':'underground','latitude':51.5720,'longitude':-0.2957,'wifi_ssid':_w},
  {'id':'MT02','name':'Northwick Park Underground Station',        'transit_type':'underground','latitude':51.5793,'longitude':-0.3057,'wifi_ssid':_w},
  {'id':'MT03','name':'Harrow-on-the-Hill Underground Station',    'transit_type':'underground','latitude':51.5793,'longitude':-0.3352,'wifi_ssid':_w},
  {'id':'MT04','name':'North Harrow Underground Station',          'transit_type':'underground','latitude':51.5978,'longitude':-0.3640,'wifi_ssid':_w},
  {'id':'MT05','name':'Pinner Underground Station',                'transit_type':'underground','latitude':51.5927,'longitude':-0.3791,'wifi_ssid':_w},
  {'id':'MT06','name':'Northwood Hills Underground Station',       'transit_type':'underground','latitude':51.6041,'longitude':-0.3929,'wifi_ssid':_w},
  {'id':'MT07','name':'Northwood Underground Station',             'transit_type':'underground','latitude':51.6107,'longitude':-0.4262,'wifi_ssid':_w},
  {'id':'MT08','name':'Moor Park Underground Station',             'transit_type':'underground','latitude':51.6340,'longitude':-0.4367,'wifi_ssid':_w},
  {'id':'MT09','name':'Watford Underground Station',               'transit_type':'underground','latitude':51.6573,'longitude':-0.3949,'wifi_ssid':_w},
  {'id':'MT10','name':'Rickmansworth Underground Station',         'transit_type':'underground','latitude':51.6393,'longitude':-0.4677,'wifi_ssid':_w},
  {'id':'MT11','name':'Chorleywood Underground Station',           'transit_type':'underground','latitude':51.6526,'longitude':-0.5129,'wifi_ssid':_w},
  {'id':'MT12','name':'Chalfont & Latimer Underground Station',    'transit_type':'underground','latitude':51.6680,'longitude':-0.5614,'wifi_ssid':_w},
  {'id':'MT13','name':'Chesham Underground Station',               'transit_type':'underground','latitude':51.7058,'longitude':-0.6099,'wifi_ssid':_w},
  {'id':'MT14','name':'Amersham Underground Station',              'transit_type':'underground','latitude':51.6741,'longitude':-0.6074,'wifi_ssid':_w},
  {'id':'MT15','name':'Uxbridge Underground Station',              'transit_type':'underground','latitude':51.5468,'longitude':-0.4779,'wifi_ssid':_w},
  {'id':'MT16','name':'Ickenham Underground Station',              'transit_type':'underground','latitude':51.5619,'longitude':-0.4402,'wifi_ssid':_w},
  {'id':'MT17','name':'Hillingdon Underground Station',            'transit_type':'underground','latitude':51.5561,'longitude':-0.4498,'wifi_ssid':_w},
  {'id':'MT18','name':'Ruislip Underground Station',               'transit_type':'underground','latitude':51.5719,'longitude':-0.4226,'wifi_ssid':_w},
  {'id':'MT19','name':'Ruislip Manor Underground Station',         'transit_type':'underground','latitude':51.5740,'longitude':-0.4124,'wifi_ssid':_w},
  {'id':'MT20','name':'Eastcote Underground Station',              'transit_type':'underground','latitude':51.5793,'longitude':-0.3954,'wifi_ssid':_w},

  // ── Elizabeth Line (cross-London) ─────────────────────────────────────────
  {'id':'EL01','name':'Shenfield Rail Station',                    'transit_type':'train','latitude':51.6379,'longitude': 0.3217,'wifi_ssid':null},
  {'id':'EL02','name':'Brentwood Rail Station',                    'transit_type':'train','latitude':51.6204,'longitude': 0.3016,'wifi_ssid':null},
  {'id':'EL03','name':'Harold Wood Rail Station',                  'transit_type':'train','latitude':51.5948,'longitude': 0.2382,'wifi_ssid':null},
  {'id':'EL04','name':'Gidea Park Rail Station',                   'transit_type':'train','latitude':51.5832,'longitude': 0.2137,'wifi_ssid':null},
  {'id':'EL05','name':'Romford Rail Station',                      'transit_type':'train','latitude':51.5751,'longitude': 0.1851,'wifi_ssid':null},
  {'id':'EL06','name':'Chadwell Heath Rail Station',               'transit_type':'train','latitude':51.5660,'longitude': 0.1310,'wifi_ssid':null},
  {'id':'EL07','name':'Goodmayes Rail Station',                    'transit_type':'train','latitude':51.5634,'longitude': 0.1063,'wifi_ssid':null},
  {'id':'EL08','name':'Seven Kings Rail Station',                  'transit_type':'train','latitude':51.5628,'longitude': 0.0887,'wifi_ssid':null},
  {'id':'EL09','name':'Ilford Rail Station',                       'transit_type':'train','latitude':51.5593,'longitude': 0.0684,'wifi_ssid':null},
  {'id':'EL10','name':'Manor Park Rail Station',                   'transit_type':'train','latitude':51.5500,'longitude': 0.0467,'wifi_ssid':null},
  {'id':'EL11','name':'Forest Gate Rail Station',                  'transit_type':'train','latitude':51.5494,'longitude': 0.0310,'wifi_ssid':null},
  {'id':'EL12','name':'Maryland Rail Station',                     'transit_type':'train','latitude':51.5526,'longitude': 0.0041,'wifi_ssid':null},
  {'id':'EL13','name':'Woolwich Rail Station',                     'transit_type':'train','latitude':51.4913,'longitude': 0.0720,'wifi_ssid':null},
  {'id':'EL14','name':'Abbey Wood Rail Station',                   'transit_type':'train','latitude':51.4905,'longitude': 0.1209,'wifi_ssid':null},
  {'id':'EL15','name':'Acton Main Line Rail Station',              'transit_type':'train','latitude':51.5100,'longitude':-0.2674,'wifi_ssid':null},
  {'id':'EL16','name':'West Ealing Rail Station',                  'transit_type':'train','latitude':51.5105,'longitude':-0.3180,'wifi_ssid':null},
  {'id':'EL17','name':'Hanwell Rail Station',                      'transit_type':'train','latitude':51.5093,'longitude':-0.3392,'wifi_ssid':null},
  {'id':'EL18','name':'Southall Rail Station',                     'transit_type':'train','latitude':51.5062,'longitude':-0.3764,'wifi_ssid':null},
  {'id':'EL19','name':'Hayes & Harlington Rail Station',           'transit_type':'train','latitude':51.5063,'longitude':-0.4259,'wifi_ssid':null},
  {'id':'EL20','name':'West Drayton Rail Station',                 'transit_type':'train','latitude':51.5097,'longitude':-0.4729,'wifi_ssid':null},
  {'id':'EL21','name':'Iver Rail Station',                         'transit_type':'train','latitude':51.5119,'longitude':-0.5079,'wifi_ssid':null},
  {'id':'EL22','name':'Langley Rail Station',                      'transit_type':'train','latitude':51.5110,'longitude':-0.5462,'wifi_ssid':null},
  {'id':'EL23','name':'Slough Rail Station',                       'transit_type':'train','latitude':51.5107,'longitude':-0.5950,'wifi_ssid':null},
  {'id':'EL24','name':'Burnham Rail Station',                      'transit_type':'train','latitude':51.5155,'longitude':-0.6498,'wifi_ssid':null},
  {'id':'EL25','name':'Taplow Rail Station',                       'transit_type':'train','latitude':51.5172,'longitude':-0.6838,'wifi_ssid':null},
  {'id':'EL26','name':'Maidenhead Rail Station',                   'transit_type':'train','latitude':51.5228,'longitude':-0.7195,'wifi_ssid':null},
  {'id':'EL27','name':'Twyford Rail Station',                      'transit_type':'train','latitude':51.4758,'longitude':-0.8614,'wifi_ssid':null},
  {'id':'EL28','name':'Reading Rail Station',                      'transit_type':'train','latitude':51.4565,'longitude':-0.9715,'wifi_ssid':null},

  // ── DLR ───────────────────────────────────────────────────────────────────
  {'id':'DR01','name':'Tower Gateway DLR Station',                 'transit_type':'dlr','latitude':51.5104,'longitude':-0.0720,'wifi_ssid':null},
  {'id':'DR02','name':'Shadwell DLR Station',                      'transit_type':'dlr','latitude':51.5118,'longitude':-0.0561,'wifi_ssid':null},
  {'id':'DR03','name':'Limehouse DLR Station',                     'transit_type':'dlr','latitude':51.5131,'longitude':-0.0374,'wifi_ssid':null},
  {'id':'DR04','name':'Westferry DLR Station',                     'transit_type':'dlr','latitude':51.5085,'longitude':-0.0249,'wifi_ssid':null},
  {'id':'DR05','name':'Poplar DLR Station',                        'transit_type':'dlr','latitude':51.5076,'longitude':-0.0172,'wifi_ssid':null},
  {'id':'DR06','name':'All Saints DLR Station',                    'transit_type':'dlr','latitude':51.5100,'longitude':-0.0115,'wifi_ssid':null},
  {'id':'DR07','name':'Langdon Park DLR Station',                  'transit_type':'dlr','latitude':51.5146,'longitude':-0.0053,'wifi_ssid':null},
  {'id':'DR08','name':'Devons Road DLR Station',                   'transit_type':'dlr','latitude':51.5198,'longitude':-0.0153,'wifi_ssid':null},
  {'id':'DR09','name':'Bow Church DLR Station',                    'transit_type':'dlr','latitude':51.5268,'longitude':-0.0190,'wifi_ssid':null},
  {'id':'DR10','name':'Stratford International DLR Station',       'transit_type':'dlr','latitude':51.5456,'longitude':-0.0054,'wifi_ssid':null},
  {'id':'DR11','name':'Star Lane DLR Station',                     'transit_type':'dlr','latitude':51.5149,'longitude': 0.0183,'wifi_ssid':null},
  {'id':'DR12','name':'Abbey Road DLR Station',                    'transit_type':'dlr','latitude':51.5133,'longitude': 0.0391,'wifi_ssid':null},
  {'id':'DR13','name':'Beckton Park DLR Station',                  'transit_type':'dlr','latitude':51.5073,'longitude': 0.0590,'wifi_ssid':null},
  {'id':'DR14','name':'Cyprus DLR Station',                        'transit_type':'dlr','latitude':51.5089,'longitude': 0.0664,'wifi_ssid':null},
  {'id':'DR15','name':'Gallions Reach DLR Station',                'transit_type':'dlr','latitude':51.5098,'longitude': 0.0777,'wifi_ssid':null},
  {'id':'DR16','name':'Beckton DLR Station',                       'transit_type':'dlr','latitude':51.5147,'longitude': 0.0637,'wifi_ssid':null},
  {'id':'DR17','name':'King George V DLR Station',                 'transit_type':'dlr','latitude':51.5024,'longitude': 0.0558,'wifi_ssid':null},
  {'id':'DR18','name':'London City Airport DLR Station',           'transit_type':'dlr','latitude':51.5038,'longitude': 0.0493,'wifi_ssid':null},
  {'id':'DR19','name':'Pontoon Dock DLR Station',                  'transit_type':'dlr','latitude':51.5016,'longitude': 0.0469,'wifi_ssid':null},
  {'id':'DR20','name':'West Silvertown DLR Station',               'transit_type':'dlr','latitude':51.5007,'longitude': 0.0287,'wifi_ssid':null},
  {'id':'DR21','name':'Royal Victoria DLR Station',                'transit_type':'dlr','latitude':51.5073,'longitude': 0.0297,'wifi_ssid':null},
  {'id':'DR22','name':'Custom House DLR Station',                  'transit_type':'dlr','latitude':51.5090,'longitude': 0.0298,'wifi_ssid':null},
  {'id':'DR23','name':'Prince Regent DLR Station',                 'transit_type':'dlr','latitude':51.5108,'longitude': 0.0361,'wifi_ssid':null},
  {'id':'DR24','name':'Royal Albert DLR Station',                  'transit_type':'dlr','latitude':51.5108,'longitude': 0.0427,'wifi_ssid':null},
  {'id':'DR25','name':'Crossharbour DLR Station',                  'transit_type':'dlr','latitude':51.4985,'longitude':-0.0170,'wifi_ssid':null},
  {'id':'DR26','name':'Mudchute DLR Station',                      'transit_type':'dlr','latitude':51.4930,'longitude':-0.0191,'wifi_ssid':null},
  {'id':'DR27','name':'Island Gardens DLR Station',                'transit_type':'dlr','latitude':51.4882,'longitude':-0.0187,'wifi_ssid':null},
  {'id':'DR28','name':'Cutty Sark DLR Station',                    'transit_type':'dlr','latitude':51.4831,'longitude':-0.0122,'wifi_ssid':null},
  {'id':'DR29','name':'Greenwich DLR Station',                     'transit_type':'dlr','latitude':51.4778,'longitude':-0.0099,'wifi_ssid':null},
  {'id':'DR30','name':'Deptford Bridge DLR Station',               'transit_type':'dlr','latitude':51.4738,'longitude':-0.0193,'wifi_ssid':null},
  {'id':'DR31','name':'Elverson Road DLR Station',                 'transit_type':'dlr','latitude':51.4702,'longitude':-0.0213,'wifi_ssid':null},
  {'id':'DR32','name':'Lewisham DLR Station',                      'transit_type':'dlr','latitude':51.4654,'longitude':-0.0138,'wifi_ssid':null},
  {'id':'DR33','name':'Heron Quays DLR Station',                   'transit_type':'dlr','latitude':51.5029,'longitude':-0.0210,'wifi_ssid':null},
  {'id':'DR34','name':'South Quay DLR Station',                    'transit_type':'dlr','latitude':51.5007,'longitude':-0.0191,'wifi_ssid':null},
  {'id':'DR35','name':'Canary Wharf DLR Station',                  'transit_type':'dlr','latitude':51.5050,'longitude':-0.0200,'wifi_ssid':null},

  // ── London Overground ─────────────────────────────────────────────────────
  {'id':'OG01','name':'Dalston Junction Overground Station',       'transit_type':'overground','latitude':51.5460,'longitude':-0.0747,'wifi_ssid':null},
  {'id':'OG02','name':'Dalston Kingsland Overground Station',      'transit_type':'overground','latitude':51.5478,'longitude':-0.0755,'wifi_ssid':null},
  {'id':'OG03','name':'Hackney Central Overground Station',        'transit_type':'overground','latitude':51.5465,'longitude':-0.0561,'wifi_ssid':null},
  {'id':'OG04','name':'Hackney Downs Overground Station',          'transit_type':'overground','latitude':51.5501,'longitude':-0.0566,'wifi_ssid':null},
  {'id':'OG05','name':'Homerton Overground Station',               'transit_type':'overground','latitude':51.5447,'longitude':-0.0430,'wifi_ssid':null},
  {'id':'OG06','name':'Hackney Wick Overground Station',           'transit_type':'overground','latitude':51.5431,'longitude':-0.0194,'wifi_ssid':null},
  {'id':'OG07','name':'Clapham Junction Rail Station',             'transit_type':'overground','latitude':51.4643,'longitude':-0.1703,'wifi_ssid':null},
  {'id':'OG08','name':"Shepherd's Bush Overground Station",        'transit_type':'overground','latitude':51.5044,'longitude':-0.2175,'wifi_ssid':null},
  {'id':'OG09','name':'Kensington Olympia Rail Station',           'transit_type':'overground','latitude':51.4984,'longitude':-0.2101,'wifi_ssid':null},
  {'id':'OG10','name':'West Croydon Rail Station',                 'transit_type':'overground','latitude':51.3765,'longitude':-0.1027,'wifi_ssid':null},
  {'id':'OG11','name':'Sydenham Rail Station',                     'transit_type':'overground','latitude':51.4264,'longitude':-0.0539,'wifi_ssid':null},
  {'id':'OG12','name':'Crystal Palace Rail Station',               'transit_type':'overground','latitude':51.4177,'longitude':-0.0712,'wifi_ssid':null},
  {'id':'OG13','name':'Norwood Junction Rail Station',             'transit_type':'overground','latitude':51.4009,'longitude':-0.0822,'wifi_ssid':null},
  {'id':'OG14','name':'Penge West Rail Station',                   'transit_type':'overground','latitude':51.4115,'longitude':-0.0545,'wifi_ssid':null},
  {'id':'OG15','name':'Anerley Rail Station',                      'transit_type':'overground','latitude':51.4044,'longitude':-0.0559,'wifi_ssid':null},
  {'id':'OG16','name':'Shoreditch High Street Overground Station', 'transit_type':'overground','latitude':51.5231,'longitude':-0.0750,'wifi_ssid':null},
  {'id':'OG17','name':'Hoxton Overground Station',                 'transit_type':'overground','latitude':51.5297,'longitude':-0.0793,'wifi_ssid':null},
  {'id':'OG18','name':'Haggerston Overground Station',             'transit_type':'overground','latitude':51.5376,'longitude':-0.0763,'wifi_ssid':null},
  {'id':'OG19','name':'Canonbury Overground Station',              'transit_type':'overground','latitude':51.5518,'longitude':-0.0904,'wifi_ssid':null},
  {'id':'OG20','name':'Caledonian Road & Barnsbury Overground Station','transit_type':'overground','latitude':51.5490,'longitude':-0.1134,'wifi_ssid':null},
  {'id':'OG21','name':'Camden Road Overground Station',            'transit_type':'overground','latitude':51.5436,'longitude':-0.1297,'wifi_ssid':null},
  {'id':'OG22','name':'Kentish Town West Overground Station',      'transit_type':'overground','latitude':51.5491,'longitude':-0.1460,'wifi_ssid':null},
  {'id':'OG23','name':'Gospel Oak Overground Station',             'transit_type':'overground','latitude':51.5555,'longitude':-0.1488,'wifi_ssid':null},
  {'id':'OG24','name':'Hampstead Heath Overground Station',        'transit_type':'overground','latitude':51.5562,'longitude':-0.1682,'wifi_ssid':null},
  {'id':'OG25','name':'Finchley Road & Frognal Overground Station','transit_type':'overground','latitude':51.5488,'longitude':-0.1807,'wifi_ssid':null},
  {'id':'OG26','name':'West Hampstead Overground Station',         'transit_type':'overground','latitude':51.5482,'longitude':-0.1905,'wifi_ssid':null},
  {'id':'OG27','name':'Brondesbury Overground Station',            'transit_type':'overground','latitude':51.5437,'longitude':-0.2011,'wifi_ssid':null},
  {'id':'OG28','name':'Brondesbury Park Overground Station',       'transit_type':'overground','latitude':51.5408,'longitude':-0.2128,'wifi_ssid':null},
  {'id':'OG29','name':'Kensal Rise Overground Station',            'transit_type':'overground','latitude':51.5355,'longitude':-0.2245,'wifi_ssid':null},
  {'id':'OG30','name':'Surrey Quays Overground Station',           'transit_type':'overground','latitude':51.4923,'longitude':-0.0499,'wifi_ssid':null},
  {'id':'OG31','name':'New Cross Gate Rail Station',               'transit_type':'overground','latitude':51.4756,'longitude':-0.0396,'wifi_ssid':null},
  {'id':'OG32','name':'New Cross Rail Station',                    'transit_type':'overground','latitude':51.4754,'longitude':-0.0362,'wifi_ssid':null},
  {'id':'OG33','name':'East Croydon Rail Station',                 'transit_type':'overground','latitude':51.3765,'longitude':-0.0924,'wifi_ssid':null},

  // ── Major UK National Rail ────────────────────────────────────────────────
  {'id':'UR01','name':'London Euston Rail Station',                'transit_type':'train','latitude':51.5281,'longitude':-0.1339,'wifi_ssid':null},
  {'id':'UR02','name':'London Waterloo Rail Station',              'transit_type':'train','latitude':51.5031,'longitude':-0.1132,'wifi_ssid':null},
  {'id':'UR03','name':'London Victoria Rail Station',              'transit_type':'train','latitude':51.4952,'longitude':-0.1441,'wifi_ssid':null},
  {'id':'UR04','name':'London Paddington Rail Station',            'transit_type':'train','latitude':51.5154,'longitude':-0.1755,'wifi_ssid':null},
  {'id':'UR05','name':"London King's Cross Rail Station",          'transit_type':'train','latitude':51.5308,'longitude':-0.1238,'wifi_ssid':null},
  {'id':'UR06','name':'London St Pancras International Rail Station','transit_type':'train','latitude':51.5320,'longitude':-0.1233,'wifi_ssid':null},
  {'id':'UR07','name':'London Liverpool Street Rail Station',      'transit_type':'train','latitude':51.5179,'longitude':-0.0823,'wifi_ssid':null},
  {'id':'UR08','name':'London Bridge Rail Station',                'transit_type':'train','latitude':51.5054,'longitude':-0.0864,'wifi_ssid':null},
  {'id':'UR09','name':'London Cannon Street Rail Station',         'transit_type':'train','latitude':51.5114,'longitude':-0.0906,'wifi_ssid':null},
  {'id':'UR10','name':'London Charing Cross Rail Station',         'transit_type':'train','latitude':51.5077,'longitude':-0.1245,'wifi_ssid':null},
  {'id':'UR11','name':'London Fenchurch Street Rail Station',      'transit_type':'train','latitude':51.5118,'longitude':-0.0781,'wifi_ssid':null},
  {'id':'UR12','name':'London Marylebone Rail Station',            'transit_type':'train','latitude':51.5226,'longitude':-0.1631,'wifi_ssid':null},
  {'id':'UR13','name':'Manchester Piccadilly Rail Station',        'transit_type':'train','latitude':53.4774,'longitude':-2.2309,'wifi_ssid':null},
  {'id':'UR14','name':'Manchester Victoria Rail Station',          'transit_type':'train','latitude':53.4852,'longitude':-2.2414,'wifi_ssid':null},
  {'id':'UR15','name':'Manchester Oxford Road Rail Station',       'transit_type':'train','latitude':53.4745,'longitude':-2.2388,'wifi_ssid':null},
  {'id':'UR16','name':'Birmingham New Street Rail Station',        'transit_type':'train','latitude':52.4773,'longitude':-1.9009,'wifi_ssid':null},
  {'id':'UR17','name':'Birmingham International Rail Station',     'transit_type':'train','latitude':52.4500,'longitude':-1.7265,'wifi_ssid':null},
  {'id':'UR18','name':'Birmingham Moor Street Rail Station',       'transit_type':'train','latitude':52.4787,'longitude':-1.8956,'wifi_ssid':null},
  {'id':'UR19','name':'Leeds Rail Station',                        'transit_type':'train','latitude':53.7955,'longitude':-1.5490,'wifi_ssid':null},
  {'id':'UR20','name':'Sheffield Rail Station',                    'transit_type':'train','latitude':53.3793,'longitude':-1.4620,'wifi_ssid':null},
  {'id':'UR21','name':'Bristol Temple Meads Rail Station',         'transit_type':'train','latitude':51.4493,'longitude':-2.5815,'wifi_ssid':null},
  {'id':'UR22','name':'Bristol Parkway Rail Station',              'transit_type':'train','latitude':51.5094,'longitude':-2.5433,'wifi_ssid':null},
  {'id':'UR23','name':'Edinburgh Waverley Rail Station',           'transit_type':'train','latitude':55.9521,'longitude':-3.1889,'wifi_ssid':null},
  {'id':'UR24','name':'Edinburgh Haymarket Rail Station',          'transit_type':'train','latitude':55.9456,'longitude':-3.2187,'wifi_ssid':null},
  {'id':'UR25','name':'Edinburgh Park Rail Station',               'transit_type':'train','latitude':55.9278,'longitude':-3.3074,'wifi_ssid':null},
  {'id':'UR26','name':'Glasgow Central Rail Station',              'transit_type':'train','latitude':55.8587,'longitude':-4.2583,'wifi_ssid':null},
  {'id':'UR27','name':'Glasgow Queen Street Rail Station',         'transit_type':'train','latitude':55.8637,'longitude':-4.2507,'wifi_ssid':null},
  {'id':'UR28','name':'Liverpool Lime Street Rail Station',        'transit_type':'train','latitude':53.4073,'longitude':-2.9775,'wifi_ssid':null},
  {'id':'UR29','name':'Liverpool Central Rail Station',            'transit_type':'train','latitude':53.4052,'longitude':-2.9853,'wifi_ssid':null},
  {'id':'UR30','name':'Nottingham Rail Station',                   'transit_type':'train','latitude':52.9471,'longitude':-1.1461,'wifi_ssid':null},
  {'id':'UR31','name':'Leicester Rail Station',                    'transit_type':'train','latitude':52.6304,'longitude':-1.1240,'wifi_ssid':null},
  {'id':'UR32','name':'Cardiff Central Rail Station',              'transit_type':'train','latitude':51.4756,'longitude':-3.1772,'wifi_ssid':null},
  {'id':'UR33','name':'Cardiff Queen Street Rail Station',         'transit_type':'train','latitude':51.4811,'longitude':-3.1733,'wifi_ssid':null},
  {'id':'UR34','name':'Swansea Rail Station',                      'transit_type':'train','latitude':51.6207,'longitude':-3.9464,'wifi_ssid':null},
  {'id':'UR35','name':'Newport Rail Station',                      'transit_type':'train','latitude':51.5870,'longitude':-2.9972,'wifi_ssid':null},
  {'id':'UR36','name':'Brighton Rail Station',                     'transit_type':'train','latitude':50.8292,'longitude':-0.1414,'wifi_ssid':null},
  {'id':'UR37','name':'Southampton Central Rail Station',          'transit_type':'train','latitude':50.9072,'longitude':-1.4070,'wifi_ssid':null},
  {'id':'UR38','name':'Portsmouth & Southsea Rail Station',        'transit_type':'train','latitude':50.7980,'longitude':-1.0909,'wifi_ssid':null},
  {'id':'UR39','name':'Portsmouth Harbour Rail Station',           'transit_type':'train','latitude':50.7959,'longitude':-1.1059,'wifi_ssid':null},
  {'id':'UR40','name':'Bournemouth Rail Station',                  'transit_type':'train','latitude':50.7225,'longitude':-1.8676,'wifi_ssid':null},
  {'id':'UR41','name':'Exeter St Davids Rail Station',             'transit_type':'train','latitude':50.7280,'longitude':-3.5366,'wifi_ssid':null},
  {'id':'UR42','name':'Plymouth Rail Station',                     'transit_type':'train','latitude':50.3786,'longitude':-4.1432,'wifi_ssid':null},
  {'id':'UR43','name':'Norwich Rail Station',                      'transit_type':'train','latitude':52.6289,'longitude': 1.2978,'wifi_ssid':null},
  {'id':'UR44','name':'Cambridge Rail Station',                    'transit_type':'train','latitude':52.1944,'longitude': 0.1388,'wifi_ssid':null},
  {'id':'UR45','name':'Oxford Rail Station',                       'transit_type':'train','latitude':51.7538,'longitude':-1.2698,'wifi_ssid':null},
  {'id':'UR46','name':'Bath Spa Rail Station',                     'transit_type':'train','latitude':51.3781,'longitude':-2.3591,'wifi_ssid':null},
  {'id':'UR47','name':'Cheltenham Spa Rail Station',               'transit_type':'train','latitude':51.8995,'longitude':-2.0966,'wifi_ssid':null},
  {'id':'UR48','name':'Gloucester Rail Station',                   'transit_type':'train','latitude':51.8647,'longitude':-2.2396,'wifi_ssid':null},
  {'id':'UR49','name':'Coventry Rail Station',                     'transit_type':'train','latitude':52.4003,'longitude':-1.5031,'wifi_ssid':null},
  {'id':'UR50','name':'Derby Rail Station',                        'transit_type':'train','latitude':52.9154,'longitude':-1.4725,'wifi_ssid':null},
  {'id':'UR51','name':'Wolverhampton Rail Station',                'transit_type':'train','latitude':52.5872,'longitude':-2.1224,'wifi_ssid':null},
  {'id':'UR52','name':'Preston Rail Station',                      'transit_type':'train','latitude':53.7527,'longitude':-2.7056,'wifi_ssid':null},
  {'id':'UR53','name':'Blackpool North Rail Station',              'transit_type':'train','latitude':53.8128,'longitude':-3.0530,'wifi_ssid':null},
  {'id':'UR54','name':'Lancaster Rail Station',                    'transit_type':'train','latitude':54.0478,'longitude':-2.8078,'wifi_ssid':null},
  {'id':'UR55','name':'Carlisle Rail Station',                     'transit_type':'train','latitude':54.8902,'longitude':-2.9313,'wifi_ssid':null},
  {'id':'UR56','name':'Newcastle Rail Station',                    'transit_type':'train','latitude':54.9683,'longitude':-1.6117,'wifi_ssid':null},
  {'id':'UR57','name':'Sunderland Rail Station',                   'transit_type':'train','latitude':54.9062,'longitude':-1.3834,'wifi_ssid':null},
  {'id':'UR58','name':'York Rail Station',                         'transit_type':'train','latitude':53.9580,'longitude':-1.0926,'wifi_ssid':null},
  {'id':'UR59','name':'Hull Rail Station',                         'transit_type':'train','latitude':53.7435,'longitude':-0.3446,'wifi_ssid':null},
  {'id':'UR60','name':'Doncaster Rail Station',                    'transit_type':'train','latitude':53.5221,'longitude':-1.1434,'wifi_ssid':null},
  {'id':'UR61','name':'Peterborough Rail Station',                 'transit_type':'train','latitude':52.5745,'longitude':-0.2437,'wifi_ssid':null},
  {'id':'UR62','name':'Stevenage Rail Station',                    'transit_type':'train','latitude':51.9021,'longitude':-0.2079,'wifi_ssid':null},
  {'id':'UR63','name':'St Albans City Rail Station',               'transit_type':'train','latitude':51.7450,'longitude':-0.3361,'wifi_ssid':null},
  {'id':'UR64','name':'Milton Keynes Central Rail Station',        'transit_type':'train','latitude':52.0334,'longitude':-0.7762,'wifi_ssid':null},
  {'id':'UR65','name':'Northampton Rail Station',                  'transit_type':'train','latitude':52.2354,'longitude':-0.9025,'wifi_ssid':null},
  {'id':'UR66','name':'Luton Airport Parkway Rail Station',        'transit_type':'train','latitude':51.8741,'longitude':-0.3939,'wifi_ssid':null},
  {'id':'UR67','name':'Luton Rail Station',                        'transit_type':'train','latitude':51.8838,'longitude':-0.4104,'wifi_ssid':null},
  {'id':'UR68','name':'Gatwick Airport Rail Station',              'transit_type':'train','latitude':51.1564,'longitude':-0.1612,'wifi_ssid':null},
  {'id':'UR69','name':'Guildford Rail Station',                    'transit_type':'train','latitude':51.2366,'longitude':-0.5673,'wifi_ssid':null},
  {'id':'UR70','name':'Woking Rail Station',                       'transit_type':'train','latitude':51.3194,'longitude':-0.5570,'wifi_ssid':null},
  {'id':'UR71','name':'Basingstoke Rail Station',                  'transit_type':'train','latitude':51.2661,'longitude':-1.0889,'wifi_ssid':null},
  {'id':'UR72','name':'Winchester Rail Station',                   'transit_type':'train','latitude':51.0649,'longitude':-1.3209,'wifi_ssid':null},
  {'id':'UR73','name':'Salisbury Rail Station',                    'transit_type':'train','latitude':51.0686,'longitude':-1.7975,'wifi_ssid':null},
  {'id':'UR74','name':'Swindon Rail Station',                      'transit_type':'train','latitude':51.5644,'longitude':-1.7854,'wifi_ssid':null},
  {'id':'UR75','name':'Didcot Parkway Rail Station',               'transit_type':'train','latitude':51.6069,'longitude':-1.2413,'wifi_ssid':null},
  {'id':'UR76','name':'Crewe Rail Station',                        'transit_type':'train','latitude':53.0886,'longitude':-2.4330,'wifi_ssid':null},
  {'id':'UR77','name':'Stockport Rail Station',                    'transit_type':'train','latitude':53.4103,'longitude':-2.1611,'wifi_ssid':null},
  {'id':'UR78','name':'Huddersfield Rail Station',                 'transit_type':'train','latitude':53.6464,'longitude':-1.7856,'wifi_ssid':null},
  {'id':'UR79','name':'Bradford Interchange Rail Station',         'transit_type':'train','latitude':53.7938,'longitude':-1.7501,'wifi_ssid':null},
  {'id':'UR80','name':'Harrogate Rail Station',                    'transit_type':'train','latitude':53.9928,'longitude':-1.5426,'wifi_ssid':null},
  {'id':'UR81','name':'Scarborough Rail Station',                  'transit_type':'train','latitude':54.2793,'longitude':-0.4021,'wifi_ssid':null},
  {'id':'UR82','name':'Grantham Rail Station',                     'transit_type':'train','latitude':52.9149,'longitude':-0.6398,'wifi_ssid':null},
  {'id':'UR83','name':'Wigan North Western Rail Station',          'transit_type':'train','latitude':53.5446,'longitude':-2.6344,'wifi_ssid':null},
  {'id':'UR84','name':'Chester Rail Station',                      'transit_type':'train','latitude':53.1918,'longitude':-2.8888,'wifi_ssid':null},
  {'id':'UR85','name':'Shrewsbury Rail Station',                   'transit_type':'train','latitude':52.7130,'longitude':-2.7455,'wifi_ssid':null},
  {'id':'UR86','name':'Ipswich Rail Station',                      'transit_type':'train','latitude':52.0474,'longitude': 1.1575,'wifi_ssid':null},
  {'id':'UR87','name':'Watford Junction Rail Station',             'transit_type':'train','latitude':51.6610,'longitude':-0.3975,'wifi_ssid':null},
  {'id':'UR88','name':'Stratford-upon-Avon Rail Station',          'transit_type':'train','latitude':52.1936,'longitude':-1.7178,'wifi_ssid':null},

  // ── Key London bus stops ──────────────────────────────────────────────────
  {'id':'BS01','name':'Victoria Bus Station',                      'transit_type':'bus','latitude':51.4943,'longitude':-0.1467,'wifi_ssid':null},
  {'id':'BS02','name':'Stratford Bus Station',                     'transit_type':'bus','latitude':51.5413,'longitude':-0.0030,'wifi_ssid':null},
  {'id':'BS03','name':'Elephant & Castle Bus Stop',                'transit_type':'bus','latitude':51.4946,'longitude':-0.1003,'wifi_ssid':null},
  {'id':'BS04','name':'London Bridge Bus Stop',                    'transit_type':'bus','latitude':51.5052,'longitude':-0.0875,'wifi_ssid':null},
  {'id':'BS05','name':'Brixton Bus Station',                       'transit_type':'bus','latitude':51.4619,'longitude':-0.1147,'wifi_ssid':null},
  {'id':'BS06','name':'Tooting Broadway Bus Stop',                 'transit_type':'bus','latitude':51.4274,'longitude':-0.1681,'wifi_ssid':null},
  {'id':'BS07','name':'Hammersmith Bus Station',                   'transit_type':'bus','latitude':51.4926,'longitude':-0.2234,'wifi_ssid':null},
  {'id':'BS08','name':'Ealing Broadway Bus Station',               'transit_type':'bus','latitude':51.5149,'longitude':-0.3013,'wifi_ssid':null},
];
