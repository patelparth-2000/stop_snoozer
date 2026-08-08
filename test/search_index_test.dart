/// Verifies the FTS5 search contract that StopPointsDb.searchStops() relies on.
///
/// These tests build the same schema that tools/build_naptan_db.py emits and run
/// the same SQL, on a real SQLite engine via sqflite_common_ffi. The point is to
/// catch two classes of failure that a widget test cannot:
///
///   1. FTS5 query-syntax errors from user input (apostrophes, bare operators)
///   2. ranking regressions — a commuter typing "toot" must get Tooting
///      Broadway station, not a bus stop on Tooting High Street
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stop_snoozer/core/constants/app_constants.dart';
import 'package:stop_snoozer/data/services/stop_points_db.dart';

/// Mirrors _searchFts() in stop_points_db.dart. Kept in sync deliberately:
/// if that query changes, this must change with it.
const String _searchSql =
    'SELECT s.* FROM StopPointsFts f '
    'JOIN StopPoints s ON s.rowid = f.rowid '
    'WHERE StopPointsFts MATCH ? '
    'ORDER BY (CASE WHEN s.name LIKE ? THEN 0 ELSE 1 END), '
    '         (CASE s.transit_type '
    "            WHEN 'underground' THEN 0 WHEN 'train' THEN 0 "
    "            WHEN 'dlr' THEN 1 WHEN 'tram' THEN 1 "
    "            WHEN 'ferry' THEN 2 ELSE 3 END), "
    '         length(s.name) ASC, s.name ASC '
    'LIMIT ${AppConstants.searchMaxResults}';

const _fixtures = <List<String>>[
  ['a', 'Tooting Broadway Underground Station', 'underground'],
  ['b', 'Tooting Bec Underground Station', 'underground'],
  ['c', 'Euston Underground Station', 'underground'],
  ['d', 'Euston Square Underground Station', 'underground'],
  ["e", "St John's Wood Underground Station", 'underground'],
  ['f', 'Tooting High Street (Stop TB)', 'bus'],
  ['g', 'Broadway Market', 'bus'],
  ['h', 'Kennington Underground Station', 'underground'],
];

Future<Database> _openFixtureDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE StopPoints (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, transit_type TEXT NOT NULL,
      latitude REAL NOT NULL, longitude REAL NOT NULL,
      wifi_ssid TEXT, indicator TEXT
    )
  ''');
  final batch = db.batch();
  for (final f in _fixtures) {
    batch.insert('StopPoints', {
      'id': f[0], 'name': f[1], 'transit_type': f[2],
      'latitude': 51.5, 'longitude': -0.1,
    });
  }
  await batch.commit(noResult: true);
  await db.execute('''
    CREATE VIRTUAL TABLE StopPointsFts USING fts5(
      name, content='StopPoints', content_rowid='rowid',
      tokenize="unicode61 remove_diacritics 2", prefix='2 3 4'
    )
  ''');
  await db.execute(
    'INSERT INTO StopPointsFts(rowid, name) SELECT rowid, name FROM StopPoints',
  );
  return db;
}

Future<List<String>> _search(Database db, String input) async {
  final match = StopPointsDb.buildFtsMatchQuery(input);
  if (match.isEmpty) return const [];
  final rows = await db.rawQuery(_searchSql, [match, '$input%']);
  return rows.map((r) => r['name'] as String).toList();
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('buildFtsMatchQuery', () {
    test('prefix-matches every token', () {
      expect(StopPointsDb.buildFtsMatchQuery('toot bro'), '"toot"* "bro"*');
    });

    test('strips punctuation that would be FTS5 syntax', () {
      // A bare "-" or ":" is a syntax error inside a MATCH expression.
      expect(StopPointsDb.buildFtsMatchQuery('-'), isEmpty);
      expect(StopPointsDb.buildFtsMatchQuery('  :  '), isEmpty);
      expect(StopPointsDb.buildFtsMatchQuery("st john's"), '"st"* "john"* "s"*');
    });

    test('quotes operator keywords so they are literal, not syntax', () {
      expect(StopPointsDb.buildFtsMatchQuery('NOT OR'), '"NOT"* "OR"*');
    });

    test('escapes embedded double quotes', () {
      expect(StopPointsDb.buildFtsMatchQuery('a"b'), '"a"* "b"*');
    });
  });

  group('search against real SQLite', () {
    late Database db;
    setUp(() async => db = await _openFixtureDb());
    tearDown(() async => db.close());

    test('multi-token prefix search narrows correctly', () async {
      expect(await _search(db, 'toot bro'),
          ['Tooting Broadway Underground Station']);
    });

    test('ranks stations above bus stops for an ambiguous prefix', () async {
      // The regression this guards: length-only ordering put
      // "Tooting High Street (Stop TB)" first because it is the shortest name.
      // Which of the two Tooting *stations* leads is not specified — both are
      // equally valid for "toot", and length/alphabetical breaks the tie
      // deterministically. What matters is that neither loses to a bus stop.
      final results = await _search(db, 'toot');
      final busIndex = results.indexOf('Tooting High Street (Stop TB)');
      expect(busIndex, greaterThan(-1), reason: 'bus stop should still match');
      for (final station in const [
        'Tooting Broadway Underground Station',
        'Tooting Bec Underground Station',
      ]) {
        expect(results.indexOf(station), greaterThan(-1));
        expect(results.indexOf(station), lessThan(busIndex),
            reason: '$station must outrank the bus stop');
      }
    });

    test('prefers names starting with the query', () async {
      expect((await _search(db, 'broadway')).first, 'Broadway Market');
    });

    test('exact station name resolves', () async {
      expect(await _search(db, 'kennington'),
          ['Kennington Underground Station']);
    });

    test('apostrophes do not raise a syntax error', () async {
      expect(await _search(db, "st john's"),
          ["St John's Wood Underground Station"]);
    });

    test('hostile input degrades to empty, never throws', () async {
      for (final q in ['-', '""', 'NOT', '*', '^:', '(((']) {
        await expectLater(_search(db, q), completes, reason: 'query: $q');
      }
    });

    test('no match returns empty', () async {
      expect(await _search(db, 'zzzznotarealstop'), isEmpty);
    });
  });
}
