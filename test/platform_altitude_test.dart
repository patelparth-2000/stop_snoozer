/// Verifies that a platform altitude reaches the native engine for every
/// station on a plan, through all three of its sources.
///
/// This is the query the barometric half of the fusion test depends on. If it
/// returns null the engine silently drops to two of its three conditions, and
/// nothing in the app reports that — so the fallback chain has to be asserted
/// rather than assumed.
///
/// Altitude, not depth, because a barometer reads a *change* in altitude.
/// Depth is measured from each station's own street and streets are not level
/// with one another, so descent-since-boarding and depth-below-street are
/// different quantities. On Tooting Broadway to Euston they differ by 21.8 m,
/// against a 12 m match tolerance.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stop_snoozer/data/repositories/route_topology_repository.dart';

/// Real values, so the numbers below mean something.
///   TOOT — its own Northern line row, from TfL FOI-0493
///   KEN  — no Northern row of its own; only another line's, so the
///          station-mean tier has to supply it
///   DLR  — no depth data at all; only OS Terrain 50 ground elevation, which
///          is the whole of the DLR, Elizabeth line and Overground's situation
const _stops = <List<Object>>[
  ['TOOT', 'Tooting Broadway Underground Station'],
  ['KEN', 'Kennington Underground Station'],
  ['DLR', 'Canning Town DLR Station'],
  ['NONE', 'No Data Station'],
];

const _order = ['TOOT', 'KEN', 'DLR', 'NONE'];

Future<Database> _open() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE StopPoints (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, transit_type TEXT NOT NULL,
      latitude REAL NOT NULL, longitude REAL NOT NULL,
      wifi_ssid TEXT, indicator TEXT)
  ''');
  await db.execute('''
    CREATE TABLE RouteSequences (
      line_id TEXT NOT NULL, direction TEXT NOT NULL,
      branch_id INTEGER NOT NULL DEFAULT 0,
      seq_index INTEGER NOT NULL, stop_id TEXT NOT NULL,
      PRIMARY KEY (line_id, direction, branch_id, seq_index))
  ''');
  await db.execute('''
    CREATE TABLE RunTimes (line_id TEXT NOT NULL, from_stop TEXT NOT NULL,
      to_stop TEXT NOT NULL, seconds INTEGER NOT NULL, peak_seconds INTEGER,
      source TEXT NOT NULL DEFAULT 'estimate',
      PRIMARY KEY (line_id, from_stop, to_stop))
  ''');
  await db.execute('''
    CREATE TABLE StationDepths (
      stop_id TEXT NOT NULL, line_id TEXT NOT NULL DEFAULT '',
      depth_metres REAL NOT NULL, platform_level_asl_m REAL,
      source TEXT NOT NULL DEFAULT 'estimate',
      PRIMARY KEY (stop_id, line_id))
  ''');
  await db.execute('''
    CREATE TABLE Elevation (stop_id TEXT PRIMARY KEY,
      ground_elev_m REAL NOT NULL, easting INTEGER, northing INTEGER,
      source TEXT NOT NULL DEFAULT 'os_terrain_50')
  ''');

  final b = db.batch();
  for (final s in _stops) {
    b.insert('StopPoints', {
      'id': s[0], 'name': s[1], 'transit_type': 'underground',
      'latitude': 51.5, 'longitude': -0.1,
    });
  }
  for (var i = 0; i < _order.length; i++) {
    b.insert('RouteSequences', {
      'line_id': 'northern', 'direction': 'inbound', 'branch_id': 0,
      'seq_index': i, 'stop_id': _order[i],
    });
  }
  // Tier 1: this line's own platform.
  b.insert('StationDepths', {
    'stop_id': 'TOOT', 'line_id': 'northern',
    'depth_metres': 12.8, 'platform_level_asl_m': 3.2, 'source': 'tfl_foi',
  });
  // Tier 2: a row for a different line at the same station.
  b.insert('StationDepths', {
    'stop_id': 'KEN', 'line_id': 'victoria',
    'depth_metres': 17.2, 'platform_level_asl_m': -14.2, 'source': 'tfl_foi',
  });
  // Tier 3: ground elevation only.
  b.insert('Elevation', {'stop_id': 'DLR', 'ground_elev_m': -2.3});
  await b.commit(noResult: true);
  return db;
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late RouteTopologyRepository repo;

  setUpAll(() async {
    db = await _open();
    repo = RouteTopologyRepository(database: db);
  });

  tearDownAll(() async => db.close());

  Future<List<PlannedStation>> plan() => repo.buildPlan(
        lineId: 'northern',
        direction: 'inbound',
        branchId: 0,
        originStopId: 'TOOT',
        destinationStopId: 'NONE',
      );

  group('platform altitude reaches the plan', () {
    test('tier 1 — the line\'s own platform wins', () async {
      final s = (await plan()).firstWhere((s) => s.stopId == 'TOOT');
      expect(s.platformLevelAslMetres, 3.2);
      expect(s.depthIsFallback, isFalse);
    });

    test('tier 2 — another line at the same station, flagged as fallback',
        () async {
      final s = (await plan()).firstWhere((s) => s.stopId == 'KEN');
      expect(s.platformLevelAslMetres, -14.2);
      // The engine widens its tolerance on a fallback, so this flag is not
      // cosmetic — losing it would make an imprecise value look precise.
      expect(s.depthIsFallback, isTrue);
    });

    test('tier 3 — ground elevation, the only prior surface lines get',
        () async {
      final s = (await plan()).firstWhere((s) => s.stopId == 'DLR');
      expect(s.platformLevelAslMetres, -2.3);
      expect(s.depthIsFallback, isTrue);
    });

    test('below-datum elevation is preserved, not clamped', () async {
      // Canning Town really does sit below Ordnance Datum. Clamping to zero
      // would put the expected descent 2.3 m out on every leg into it.
      final s = (await plan()).firstWhere((s) => s.stopId == 'DLR');
      expect(s.platformLevelAslMetres, lessThan(0));
    });

    test('no data anywhere yields null rather than a fabricated zero',
        () async {
      // Null disables the barometric condition for this station, which is
      // correct. A zero would assert "sea level" and be actively wrong.
      final s = (await plan()).firstWhere((s) => s.stopId == 'NONE');
      expect(s.platformLevelAslMetres, isNull);
    });
  });

  group('descent is what altitude buys us', () {
    test('a deep station reached from another deep station is a short drop',
        () async {
      final stations = await plan();
      final toot = stations.firstWhere((s) => s.stopId == 'TOOT');
      final ken = stations.firstWhere((s) => s.stopId == 'KEN');

      final expectedDescent =
          toot.platformLevelAslMetres! - ken.platformLevelAslMetres!;
      expect(expectedDescent, closeTo(17.4, 0.1));

      // Depth alone would have predicted 17.2 m here, which happens to agree
      // because both streets are near the same height — the model only breaks
      // when they are not, which is why altitude is stored rather than derived.
      expect(ken.depthMetres, closeTo(17.2, 0.1));
    });
  });
}
