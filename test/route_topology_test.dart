/// Verifies the route-topology queries the underground engine depends on,
/// using the Northern line's Kennington split as the fixture — the exact case
/// that motivated mandatory route pre-selection.
///
/// Fixture geometry (inbound), two branches sharing a trunk then diverging:
///
///   branch 0:  Morden → Oval → Kennington → Waterloo → Charing Cross
///   branch 1:  Morden → Oval → Kennington → Elephant & Castle → Bank
///
/// Kennington is therefore the last shared station, and a user heading to Bank
/// versus Charing Cross must be asked which way they are going.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _stops = <List<Object>>[
  ['MOR', 'Morden Underground Station', 51.4023, -0.1948],
  ['OVL', 'Oval Underground Station', 51.4819, -0.1128],
  ['KEN', 'Kennington Underground Station', 51.4884, -0.1053],
  ['WLO', 'Waterloo Underground Station', 51.5036, -0.1143],
  ['CHX', 'Charing Cross Underground Station', 51.5074, -0.1278],
  ['EAC', 'Elephant & Castle Underground Station', 51.4943, -0.1001],
  ['BNK', 'Bank Underground Station', 51.5133, -0.0886],
];

const _branch0 = ['MOR', 'OVL', 'KEN', 'WLO', 'CHX'];
const _branch1 = ['MOR', 'OVL', 'KEN', 'EAC', 'BNK'];

Future<Database> _openTopologyDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE StopPoints (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, transit_type TEXT NOT NULL,
      latitude REAL NOT NULL, longitude REAL NOT NULL,
      wifi_ssid TEXT, indicator TEXT)
  ''');
  await db.execute('''
    CREATE TABLE Lines (line_id TEXT PRIMARY KEY, name TEXT NOT NULL,
      mode TEXT NOT NULL, colour TEXT)
  ''');
  await db.execute('''
    CREATE TABLE RouteSequences (
      line_id TEXT NOT NULL, direction TEXT NOT NULL,
      branch_id INTEGER NOT NULL DEFAULT 0,
      seq_index INTEGER NOT NULL, stop_id TEXT NOT NULL,
      PRIMARY KEY (line_id, direction, branch_id, seq_index))
  ''');
  await db.execute('''
    CREATE TABLE Branches (line_id TEXT NOT NULL, direction TEXT NOT NULL,
      stop_id TEXT NOT NULL, branch_id INTEGER NOT NULL, branch_label TEXT,
      PRIMARY KEY (line_id, direction, stop_id, branch_id))
  ''');
  await db.execute('''
    CREATE TABLE RunTimes (line_id TEXT NOT NULL, from_stop TEXT NOT NULL,
      to_stop TEXT NOT NULL, seconds INTEGER NOT NULL,
      source TEXT NOT NULL DEFAULT 'estimate',
      PRIMARY KEY (line_id, from_stop, to_stop))
  ''');
  await db.execute('''
    CREATE TABLE StationDepths (stop_id TEXT PRIMARY KEY,
      depth_metres REAL NOT NULL, source TEXT NOT NULL DEFAULT 'estimate')
  ''');
  await db.execute('''
    CREATE TABLE Fingerprints (
      stop_id TEXT NOT NULL, kind TEXT NOT NULL, identifier TEXT NOT NULL,
      observations INTEGER NOT NULL DEFAULT 1, last_seen_ms INTEGER NOT NULL,
      PRIMARY KEY (stop_id, kind, identifier))
  ''');

  final b = db.batch();
  for (final s in _stops) {
    b.insert('StopPoints', {
      'id': s[0], 'name': s[1], 'transit_type': 'underground',
      'latitude': s[2], 'longitude': s[3],
    });
  }
  b.insert('Lines', {
    'line_id': 'northern', 'name': 'Northern', 'mode': 'tube',
  });
  for (final (branchId, seq) in [(0, _branch0), (1, _branch1)]) {
    for (var i = 0; i < seq.length; i++) {
      b.insert('RouteSequences', {
        'line_id': 'northern', 'direction': 'inbound',
        'branch_id': branchId, 'seq_index': i, 'stop_id': seq[i],
      });
      if (i > 0) {
        // RunTimes is keyed by (line, from, to) with no branch_id, because a
        // leg's duration does not depend on which branch traverses it. The
        // shared trunk (Morden→Oval→Kennington) is therefore inserted twice and
        // must be deduplicated — build_naptan_db.py uses INSERT OR IGNORE for
        // exactly this reason.
        b.insert(
          'RunTimes',
          {
            'line_id': 'northern', 'from_stop': seq[i - 1], 'to_stop': seq[i],
            'seconds': 120, 'source': 'estimate',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }
  b.insert('Branches', {
    'line_id': 'northern', 'direction': 'inbound', 'stop_id': 'KEN',
    'branch_id': 0, 'branch_label': 'via Waterloo',
  });
  b.insert('Branches', {
    'line_id': 'northern', 'direction': 'inbound', 'stop_id': 'KEN',
    'branch_id': 1, 'branch_label': 'via Elephant & Castle',
  });
  b.insert('StationDepths', {'stop_id': 'KEN', 'depth_metres': 22.0});
  b.insert('StationDepths', {'stop_id': 'BNK', 'depth_metres': 27.0});
  await b.commit(noResult: true);
  return db;
}

// Mirrors RouteTopologyRepository.viableRoutes().
Future<List<(String, int)>> _viableRoutes(
    Database db, String origin, String dest) async {
  final rows = await db.rawQuery(
    'SELECT o.direction, o.branch_id FROM RouteSequences o '
    'JOIN RouteSequences d ON o.line_id=d.line_id AND o.direction=d.direction '
    ' AND o.branch_id=d.branch_id '
    'WHERE o.line_id=? AND o.stop_id=? AND d.stop_id=? AND o.seq_index<d.seq_index '
    'ORDER BY o.direction, o.branch_id',
    ['northern', origin, dest],
  );
  return rows
      .map((r) => (r['direction'] as String, (r['branch_id'] as num).toInt()))
      .toList();
}

// Mirrors RouteTopologyRepository.buildPlan().
Future<List<String>> _planStops(
    Database db, int branchId, String origin, String dest) async {
  final bounds = await db.rawQuery(
    'SELECT (SELECT seq_index FROM RouteSequences WHERE line_id=? AND '
    'direction=? AND branch_id=? AND stop_id=?) AS a, '
    '(SELECT seq_index FROM RouteSequences WHERE line_id=? AND direction=? '
    'AND branch_id=? AND stop_id=?) AS b',
    ['northern', 'inbound', branchId, origin,
     'northern', 'inbound', branchId, dest],
  );
  final a = bounds.first['a'] as int?;
  final bIdx = bounds.first['b'] as int?;
  if (a == null || bIdx == null || bIdx <= a) return const [];
  final rows = await db.rawQuery(
    'SELECT s.stop_id FROM RouteSequences s '
    'WHERE s.line_id=? AND s.direction=? AND s.branch_id=? '
    'AND s.seq_index BETWEEN ? AND ? ORDER BY s.seq_index',
    ['northern', 'inbound', branchId, a, bIdx],
  );
  return rows.map((r) => r['stop_id'] as String).toList();
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  setUp(() async => db = await _openTopologyDb());
  tearDown(() async => db.close());

  group('viable route resolution', () {
    test('destination on one branch yields exactly that branch', () async {
      expect(await _viableRoutes(db, 'MOR', 'BNK'), [('inbound', 1)]);
      expect(await _viableRoutes(db, 'MOR', 'CHX'), [('inbound', 0)]);
    });

    test('shared-trunk destination is reachable on both branches', () async {
      // This is the ambiguity pre-selection exists to resolve: Kennington is on
      // both, so the app cannot infer the branch from the destination alone.
      expect(await _viableRoutes(db, 'MOR', 'KEN'),
          [('inbound', 0), ('inbound', 1)]);
    });

    test('reversed pair yields nothing — direction matters', () async {
      expect(await _viableRoutes(db, 'BNK', 'MOR'), isEmpty);
    });

    test('stops on different branches are not connected', () async {
      expect(await _viableRoutes(db, 'CHX', 'BNK'), isEmpty);
    });
  });

  group('run times', () {
    test('shared-trunk legs are stored once, not per branch', () async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM RunTimes WHERE from_stop=? AND to_stop=?',
        ['MOR', 'OVL'],
      );
      expect(rows.first['c'], 1,
          reason: 'a leg duration is independent of the branch traversing it');
    });

    test('every leg of a plan has a timing prior', () async {
      // The timing gate is what rejects mid-tunnel holds. A missing prior
      // silently weakens the fusion test, so verify full coverage.
      final plan = await _planStops(db, 1, 'MOR', 'BNK');
      for (var i = 1; i < plan.length; i++) {
        final rows = await db.rawQuery(
          'SELECT seconds FROM RunTimes WHERE line_id=? AND from_stop=? AND to_stop=?',
          ['northern', plan[i - 1], plan[i]],
        );
        expect(rows, isNotEmpty, reason: 'no run time for ${plan[i - 1]}→${plan[i]}');
      }
    });
  });

  group('journey plan assembly', () {
    test('includes every intermediate stop in order', () async {
      expect(await _planStops(db, 1, 'OVL', 'BNK'),
          ['OVL', 'KEN', 'EAC', 'BNK']);
    });

    test('does not leak the other branch', () async {
      final plan = await _planStops(db, 1, 'MOR', 'BNK');
      expect(plan, isNot(contains('WLO')));
      expect(plan, isNot(contains('CHX')));
    });

    test('returns empty for an unreachable pair rather than a partial plan',
        () async {
      // Must be empty, not partial: a truncated plan would make the engine
      // believe the journey ends early and alarm at the wrong station.
      expect(await _planStops(db, 0, 'BNK', 'CHX'), isEmpty);
    });
  });

  group('branch prompt', () {
    test('Kennington offers both labelled alternatives', () async {
      final rows = await db.rawQuery(
        'SELECT branch_id, branch_label FROM Branches '
        'WHERE line_id=? AND direction=? AND stop_id=? ORDER BY branch_id',
        ['northern', 'inbound', 'KEN'],
      );
      expect(rows.map((r) => r['branch_label']),
          ['via Waterloo', 'via Elephant & Castle']);
    });

    test('non-branching stations offer no choice', () async {
      final rows = await db.rawQuery(
        'SELECT 1 FROM Branches WHERE stop_id=?', ['OVL'],
      );
      expect(rows, isEmpty);
    });
  });

  group('fingerprints (U13)', () {
    Future<void> record(String stop, List<String> ids) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final b = db.batch();
      for (final id in ids) {
        b.rawInsert(
          'INSERT INTO Fingerprints(stop_id,kind,identifier,observations,last_seen_ms) '
          'VALUES (?,?,?,1,?) ON CONFLICT(stop_id,kind,identifier) DO UPDATE SET '
          'observations = observations + 1, last_seen_ms = excluded.last_seen_ms',
          [stop, 'bssid', id, now],
        );
      }
      await b.commit(noResult: true);
    }

    test('repeat sightings accumulate rather than duplicate', () async {
      await record('KEN', ['aa:bb', 'cc:dd']);
      await record('KEN', ['aa:bb']);
      final rows = await db.rawQuery(
        'SELECT identifier, observations FROM Fingerprints '
        'WHERE stop_id=? ORDER BY identifier',
        ['KEN'],
      );
      expect(rows.length, 2);
      expect(rows.first['observations'], 2);
    });

    test('a single coincidental sighting does not relocate the user', () async {
      await record('KEN', ['aa:bb']);
      final rows = await db.rawQuery(
        'SELECT stop_id, SUM(observations) AS score FROM Fingerprints '
        'WHERE kind=? AND identifier IN (?) GROUP BY stop_id HAVING score >= ?',
        ['bssid', 'aa:bb', 2],
      );
      expect(rows, isEmpty, reason: 'below minObservations threshold');
    });

    test('repeated sightings do match', () async {
      await record('KEN', ['aa:bb']);
      await record('KEN', ['aa:bb']);
      final rows = await db.rawQuery(
        'SELECT stop_id, SUM(observations) AS score FROM Fingerprints '
        'WHERE kind=? AND identifier IN (?) GROUP BY stop_id HAVING score >= ? '
        'ORDER BY score DESC LIMIT 1',
        ['bssid', 'aa:bb', 2],
      );
      expect(rows.first['stop_id'], 'KEN');
    });
  });
}
