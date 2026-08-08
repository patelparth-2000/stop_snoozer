import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../services/stop_points_db.dart';

/// A line the user can travel on.
class TransitLine {
  const TransitLine({required this.id, required this.name, required this.mode});
  final String id;
  final String name;
  final String mode;
}

/// One alternative at a branch point (e.g. Northern line at Kennington).
class BranchOption {
  const BranchOption({
    required this.branchId,
    required this.label,
    required this.nextStopName,
  });
  final int branchId;
  final String label;
  final String nextStopName;
}

/// A station within a resolved route, carrying everything the native fusion
/// engine needs to judge an arrival there.
class PlannedStation {
  const PlannedStation({
    required this.stopId,
    required this.stopName,
    required this.depthMetres,
    required this.runTimeSeconds,
    required this.isTarget,
    this.platformLevelAslMetres,
    this.peakRunTimeSeconds,
    this.depthIsFallback = false,
  });

  final String stopId;
  final String stopName;

  /// Platform depth in metres, or null when unknown.
  ///
  /// Retained for display and as the engine's fallback when altitudes are
  /// absent (a pre-v6 asset). It is NOT what the barometer is matched against
  /// — see [platformLevelAslMetres].
  final double? depthMetres;

  /// Platform altitude in metres above Ordnance Datum, or null when unknown.
  ///
  /// This is the quantity the barometer can actually corroborate. A barometer
  /// reads a change in altitude, so the expected reading between two stations
  /// is the difference of their platform altitudes — which depth below street
  /// cannot express, because streets are not level with one another. Tooting
  /// Broadway's is 16 m above sea level and Hampstead's is 108 m.
  ///
  /// Null disables the barometric half of the fusion test for this station:
  /// the engine leans on timing alone and carries lower confidence, which is
  /// correct, because we genuinely know less.
  final double? platformLevelAslMetres;

  /// True when [depthMetres] came from the mean of the station's other
  /// platforms rather than this line's own.
  ///
  /// Happens wherever the source data has no column for the line — the Circle
  /// line has none at all. The value is still usable, but is less precise at
  /// interchanges, so the engine should weight it slightly lower.
  final bool depthIsFallback;

  /// Unimpeded seconds from the previous station — the train moving with no
  /// holds, i.e. a physical floor. Null when unknown.
  final int? runTimeSeconds;

  /// AM-peak scheduled seconds for the same leg, when known. Used to widen the
  /// timing gate's *upper* bound only; the floor stays at [runTimeSeconds].
  final int? peakRunTimeSeconds;

  final bool isTarget;

  Map<String, Object?> toJson() => {
        'stopId': stopId,
        'stopName': stopName,
        if (depthMetres != null) 'depthMetres': depthMetres,
        if (platformLevelAslMetres != null)
          'platformLevelAslMetres': platformLevelAslMetres,
        if (depthIsFallback) 'depthIsFallback': true,
        'runTimeSeconds': runTimeSeconds ?? 0,
        if (peakRunTimeSeconds != null) 'peakRunTimeSeconds': peakRunTimeSeconds,
        'isTarget': isTarget,
      };
}

/// Reads the route topology tables (U1) and assembles journey plans.
///
/// This is the Dart half of the pre-selection design: the route is resolved
/// here, once, while the user is online and attentive. The native engine then
/// receives a single unambiguous sequence and never has to disambiguate
/// underground — which is the whole reason pre-selection is mandatory.
class RouteTopologyRepository {
  RouteTopologyRepository({StopPointsDb? db, Database? database})
      : _dbSource = db ?? StopPointsDb.instance,
        _override = database;

  final StopPointsDb _dbSource;

  /// Test seam. [StopPointsDb] is an asset-backed singleton, so without this
  /// the plan-assembly query below — which decides whether the barometric
  /// prior reaches the engine at all — cannot be exercised in a unit test.
  final Database? _override;

  Database? get _db => _override ?? _dbSource.rawDb;

  /// True when the database actually carries topology rows.
  ///
  /// The tables exist from v4 but may be empty, because populating them needs
  /// `build_naptan_db.py --with-topology`. Callers must check this and fall back
  /// to GPS geofencing rather than assuming a plan can be built.
  Future<bool> hasTopology() async {
    final db = _db;
    if (db == null) return false;
    try {
      final rows = await db.rawQuery(
        'SELECT 1 FROM RouteSequences LIMIT 1',
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Lines serving [stopId], for the pre-selection UI.
  Future<List<TransitLine>> linesServing(String stopId) async {
    final db = _db;
    if (db == null) return const [];
    final rows = await db.rawQuery(
      'SELECT DISTINCT l.line_id, l.name, l.mode '
      'FROM RouteSequences s JOIN Lines l ON l.line_id = s.line_id '
      'WHERE s.stop_id = ? ORDER BY l.name',
      [stopId],
    );
    return rows
        .map((r) => TransitLine(
              id: r['line_id'] as String,
              name: r['name'] as String,
              mode: r['mode'] as String,
            ))
        .toList();
  }

  /// Directions on [lineId] that contain both stops in the correct order.
  ///
  /// Returns the `(direction, branchId)` pairs where origin precedes
  /// destination. This is how direction is inferred rather than asked: if only
  /// one direction works, there is nothing to ask the user about.
  Future<List<({String direction, int branchId})>> viableRoutes({
    required String lineId,
    required String originStopId,
    required String destinationStopId,
  }) async {
    final db = _db;
    if (db == null) return const [];
    final rows = await db.rawQuery(
      'SELECT o.direction, o.branch_id '
      'FROM RouteSequences o JOIN RouteSequences d '
      '  ON o.line_id = d.line_id AND o.direction = d.direction '
      ' AND o.branch_id = d.branch_id '
      'WHERE o.line_id = ? AND o.stop_id = ? AND d.stop_id = ? '
      '  AND o.seq_index < d.seq_index '
      'ORDER BY o.direction, o.branch_id',
      [lineId, originStopId, destinationStopId],
    );
    return rows
        .map((r) => (
              direction: r['direction'] as String,
              branchId: (r['branch_id'] as num).toInt(),
            ))
        .toList();
  }

  /// Branch choices the user must resolve at [stopId], if any.
  ///
  /// Where this is non-empty the app asks ("Charing Cross or Bank?") rather than
  /// guessing. Sensor-based branch discrimination needs about three stops of
  /// evidence, by which point the decision is long past.
  Future<List<BranchOption>> branchOptionsAt({
    required String lineId,
    required String direction,
    required String stopId,
  }) async {
    final db = _db;
    if (db == null) return const [];
    final rows = await db.rawQuery(
      'SELECT branch_id, branch_label FROM Branches '
      'WHERE line_id = ? AND direction = ? AND stop_id = ? '
      'ORDER BY branch_id',
      [lineId, direction, stopId],
    );
    final out = <BranchOption>[];
    for (final r in rows) {
      final branchId = (r['branch_id'] as num).toInt();
      final next = await db.rawQuery(
        'SELECT p.name FROM RouteSequences s '
        'JOIN StopPoints p ON p.id = s.stop_id '
        'WHERE s.line_id = ? AND s.direction = ? AND s.branch_id = ? '
        '  AND s.seq_index = ('
        '    SELECT seq_index + 1 FROM RouteSequences '
        '    WHERE line_id = ? AND direction = ? AND branch_id = ? AND stop_id = ?'
        '  ) LIMIT 1',
        [lineId, direction, branchId, lineId, direction, branchId, stopId],
      );
      out.add(BranchOption(
        branchId: branchId,
        label: r['branch_label'] as String? ?? 'Branch $branchId',
        nextStopName: next.isEmpty ? '' : next.first['name'] as String,
      ));
    }
    return out;
  }

  /// Builds the ordered station list between two stops on a chosen route.
  ///
  /// Returns an empty list when the pair is not connected on this
  /// line/direction/branch — callers must treat that as "no plan" and fall back
  /// to GPS, never as an empty-but-valid journey.
  Future<List<PlannedStation>> buildPlan({
    required String lineId,
    required String direction,
    required int branchId,
    required String originStopId,
    required String destinationStopId,
  }) async {
    final db = _db;
    if (db == null) return const [];

    final bounds = await db.rawQuery(
      'SELECT '
      '  (SELECT seq_index FROM RouteSequences WHERE line_id=? AND direction=? '
      '     AND branch_id=? AND stop_id=?) AS a, '
      '  (SELECT seq_index FROM RouteSequences WHERE line_id=? AND direction=? '
      '     AND branch_id=? AND stop_id=?) AS b',
      [
        lineId, direction, branchId, originStopId,
        lineId, direction, branchId, destinationStopId,
      ],
    );
    final a = bounds.first['a'] as int?;
    final b = bounds.first['b'] as int?;
    if (a == null || b == null || b <= a) return const [];

    // Depth resolution is two-tier.
    //
    // Preferred: the exact (stop, line) platform, because depth differs per line
    // at interchanges — Bank is 20.5 m on the Central line and 29.6 m on the
    // Northern.
    //
    // Fallback: the mean of that station's other platforms. This matters more
    // than it looks. The source spreadsheet has no Circle line column at all, so
    // a strict line join returns NULL for every Circle journey and silently
    // disables the barometric half of the fusion test — even though 33 of 34
    // Circle stations do have a depth recorded under District, Metropolitan or
    // H&C. A few metres of interchange error is far better than no signal.
    // Altitude resolution is three-tier, most specific first:
    //   1. the exact (stop, line) platform altitude;
    //   2. the mean of that station's other platforms, for interchanges where
    //      this line has no row of its own;
    //   3. ground elevation, for stations that are at the surface and have no
    //      depth data at all — the whole of the DLR, Elizabeth line and
    //      Overground, where no open dataset publishes platform depths.
    // Tier 3 is why those lines get a barometric prior at all.
    final rows = await db.rawQuery(
      'SELECT s.stop_id, p.name, '
      '       COALESCE(d.depth_metres, f.mean_depth) AS depth_metres, '
      '       COALESCE(d.platform_level_asl_m, f.mean_asl, e.ground_elev_m) '
      '         AS platform_asl, '
      '       (d.platform_level_asl_m IS NULL) AS depth_is_fallback '
      'FROM RouteSequences s '
      'JOIN StopPoints p ON p.id = s.stop_id '
      'LEFT JOIN StationDepths d '
      '  ON d.stop_id = s.stop_id AND d.line_id = s.line_id '
      'LEFT JOIN (SELECT stop_id, AVG(depth_metres) AS mean_depth, '
      '                  AVG(platform_level_asl_m) AS mean_asl '
      '           FROM StationDepths GROUP BY stop_id) f '
      '  ON f.stop_id = s.stop_id '
      'LEFT JOIN Elevation e ON e.stop_id = s.stop_id '
      'WHERE s.line_id=? AND s.direction=? AND s.branch_id=? '
      '  AND s.seq_index BETWEEN ? AND ? '
      'ORDER BY s.seq_index ASC',
      [lineId, direction, branchId, a, b],
    );

    final out = <PlannedStation>[];
    String? prevId;
    for (final r in rows) {
      final stopId = r['stop_id'] as String;
      int? runTime;
      int? peakRunTime;
      if (prevId != null) {
        final rt = await db.rawQuery(
          'SELECT seconds, peak_seconds FROM RunTimes '
          'WHERE line_id=? AND from_stop=? AND to_stop=? LIMIT 1',
          [lineId, prevId, stopId],
        );
        if (rt.isNotEmpty) {
          runTime = (rt.first['seconds'] as num).toInt();
          peakRunTime = (rt.first['peak_seconds'] as num?)?.toInt();
        }
      }
      out.add(PlannedStation(
        stopId: stopId,
        stopName: r['name'] as String,
        depthMetres: (r['depth_metres'] as num?)?.toDouble(),
        platformLevelAslMetres: (r['platform_asl'] as num?)?.toDouble(),
        depthIsFallback: ((r['depth_is_fallback'] as num?)?.toInt() ?? 0) == 1,
        runTimeSeconds: runTime,
        peakRunTimeSeconds: peakRunTime,
        isTarget: stopId == destinationStopId,
      ));
      prevId = stopId;
    }
    return out;
  }

  /// Serialises a plan for the native engine (see JourneyPlan.java).
  static String encodePlan({
    required String lineId,
    required String direction,
    required List<PlannedStation> stations,
    int startIndex = 0,
  }) =>
      jsonEncode({
        'lineId': lineId,
        'direction': direction,
        'startIndex': startIndex,
        'stations': stations.map((s) => s.toJson()).toList(),
      });

  // ── U13: self-learned fingerprints ──────────────────────────────────────

  /// Whether the user has opted in to on-device fingerprint learning.
  ///
  /// Gated by explicit consent rather than mere disclosure. Wi-Fi BSSIDs can be
  /// personal data under UK GDPR where they allow an individual to be singled
  /// out, and writing them to the device engages PECR reg. 6 on storing
  /// information in terminal equipment. Processing is device-local and never
  /// transmitted, which is a strong position — but opt-in removes the ambiguity
  /// entirely, and Play's disclosure rules point the same way.
  static const String prefFingerprintConsent = 'fingerprint_consent_granted';

  /// Process-wide, not per-instance.
  ///
  /// The repository is constructed ad hoc at several call sites, so an instance
  /// field would mean a freshly-built repository silently had no consent and
  /// every write became a no-op — failing safe, but also failing permanently.
  /// [loadConsent] is called once at startup and the answer is shared.
  static bool _consentGranted = false;

  /// Restores the persisted answer. Call once during app initialisation, before
  /// anything can observe radio identifiers.
  static Future<bool> loadConsent() async {
    final prefs = await SharedPreferences.getInstance();
    _consentGranted = prefs.getBool(prefFingerprintConsent) ?? false;
    return _consentGranted;
  }

  /// Whether the user has been asked at all. Distinguishes "declined" from
  /// "not yet prompted", so the consent dialog is shown exactly once unless the
  /// user revisits it from System Health.
  static Future<bool> consentAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(prefFingerprintConsent);
  }

  /// Records the user's answer and applies it immediately.
  ///
  /// Withdrawal is not just a flag flip: consent withdrawn must also erase what
  /// was gathered under it, so this deletes the learned fingerprints when
  /// [granted] is false.
  static Future<void> setFingerprintConsent(bool granted) async {
    _consentGranted = granted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefFingerprintConsent, granted);
    if (!granted) await RouteTopologyRepository().deleteAllFingerprints();
  }

  static bool get hasFingerprintConsent => _consentGranted;

  /// Records observed radio identifiers against a confirmed station.
  ///
  /// Stored on-device only and never transmitted. Silently does nothing without
  /// consent — the check is here, at the single write path, rather than at each
  /// call site, so a future caller cannot bypass it by forgetting.
  Future<void> recordFingerprints({
    required String stopId,
    required String kind,
    required List<String> identifiers,
  }) async {
    if (!_consentGranted) return;
    final db = _db;
    if (db == null || identifiers.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in identifiers) {
      batch.rawInsert(
        'INSERT INTO Fingerprints(stop_id,kind,identifier,observations,last_seen_ms) '
        'VALUES (?,?,?,1,?) '
        'ON CONFLICT(stop_id,kind,identifier) DO UPDATE SET '
        '  observations = observations + 1, last_seen_ms = excluded.last_seen_ms',
        [stopId, kind, id, now],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Best-matching station for a set of observed identifiers, or null.
  ///
  /// Requires at least [minObservations] historical sightings so a single
  /// coincidental match cannot relocate the user.
  Future<String?> matchFingerprint({
    required String kind,
    required List<String> identifiers,
    int minObservations = 2,
  }) async {
    final db = _db;
    if (db == null || identifiers.isEmpty) return null;
    final ph = List.filled(identifiers.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT stop_id, SUM(observations) AS score FROM Fingerprints '
      'WHERE kind = ? AND identifier IN ($ph) '
      'GROUP BY stop_id HAVING score >= ? '
      'ORDER BY score DESC LIMIT 1',
      [kind, ...identifiers, minObservations],
    );
    if (rows.isEmpty) return null;
    return rows.first['stop_id'] as String?;
  }

  /// Drops fingerprints not seen for [maxAge].
  ///
  /// Not optional housekeeping: TfL is migrating station Wi-Fi from Virgin Media
  /// to Boldyn, so BSSIDs turn over wholesale. Stale entries would keep matching
  /// access points that no longer exist and quietly degrade accuracy, so this
  /// must actually be called — see [maintain].
  Future<int> pruneFingerprints({
    Duration maxAge = const Duration(days: 120),
  }) async {
    final db = _db;
    if (db == null) return 0;
    final cutoff =
        DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    return db.delete(
      'Fingerprints',
      where: 'last_seen_ms < ?',
      whereArgs: [cutoff],
    );
  }

  /// Periodic upkeep, safe to call on every app start.
  ///
  /// Cheap: one indexed DELETE against a table that only grows a few rows per
  /// journey.
  Future<void> maintain() async {
    try {
      await pruneFingerprints();
    } catch (_) {
      // Housekeeping must never block startup.
    }
  }

  /// Erases all learned fingerprints.
  ///
  /// Required so users can withdraw consent meaningfully — a delete control is
  /// expected under GDPR erasure principles even for device-local data.
  Future<int> deleteAllFingerprints() async {
    final db = _db;
    if (db == null) return 0;
    return db.delete('Fingerprints');
  }

  Future<int> fingerprintCount() async {
    final db = _db;
    if (db == null) return 0;
    try {
      final r = await db.rawQuery('SELECT COUNT(*) FROM Fingerprints');
      return (r.first.values.first as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
