"""
build_naptan_db.py
Downloads the full NaPTAN dataset from the UK DfT API,
converts it to the StopPoints SQLite schema, gzips it,
and writes assets/uk.db.gz ready for bundling.

Run from the project root:
    python tools/build_naptan_db.py
"""

import csv
import gzip
import os
import sqlite3
import sys
import urllib.request


def _use_utf8_stdout():
    """Stops a console encoding from killing a ten-minute build.

    Windows consoles default to cp1252, which cannot encode the em-dashes and
    arrows in this script's progress output. That raised UnicodeEncodeError on
    the very last line — after the database was fully built — and the cleanup
    in main() then deleted it. Reconfiguring is more robust than policing every
    print for ASCII, and errors='replace' means even an unexpected character
    degrades to '?' rather than aborting.
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass    # already UTF-8, or not a reconfigurable stream


_use_utf8_stdout()

# ── Config ─────────────────────────────────────────────────────────────────────

API_URL  = 'https://naptan.api.dft.gov.uk/v1/access-nodes?dataFormat=csv'
CSV_TEMP = '_naptan_temp.csv'
DB_TEMP  = '_naptan_temp.db'
GZ_OUT   = os.path.join('assets', 'uk.db.gz')

# Bumped whenever the schema changes. StopPointsDb._requiredVersion in
# lib/data/services/stop_points_db.dart MUST match, or devices with an older
# extracted copy will never pick up the new schema.
#   v3 — added StopPointsFts full-text index
#   v4 — added route topology (Lines/RouteSequences/Branches/RunTimes/StationDepths)
#   v5 — StationDepths keyed by (stop_id, line_id): depth is a platform property,
#        not a station one (Bank differs by ~9 m between Central and Northern)
#   v6 — StationDepths.platform_level_asl_m + the Elevation table. The barometer
#        measures altitude change, so matching needs platform altitude, not
#        depth below the local street: streets differ by up to ~76 m across the
#        network against a 12 m tolerance.
SCHEMA_VERSION = 6

# TfL Unified API. No key needed for these endpoints at low volume; if you hit
# rate limits, register an app key and append &app_key=... to the URLs.
TFL_LINES_URL = 'https://api.tfl.gov.uk/Line/Mode/tube,dlr,elizabeth-line,overground/Route'
# serviceTypes=Regular excludes Night services. As of 2026-08 the API returns
# identical branch sets either way, so this changes nothing today — it is here
# so that a Night-only branch appearing later cannot quietly enter the topology
# as a daytime route the user could be offered.
TFL_SEQ_URL   = ('https://api.tfl.gov.uk/Line/{line}/Route/Sequence/{direction}'
                 '?serviceTypes=Regular')

# NaPTAN StopType → fallback transit_type when not overridden by ATCOCode
_TYPE_MAP = {
    # National Rail / Elizabeth Line / Overground
    'RLY': 'train',
    # Ferry
    'FER': 'ferry',
    'FTD': 'ferry',
    # Everything else (BCE, BCT, BCS, BCP, LCE, LBL, etc.) → bus
}

# StopType values to skip unconditionally. NaPTAN models a station as one
# "access area" record plus child platform and entrance records, so keeping the
# children would list the same station several times in search and in
# getClosestStops(). Keep the access areas (RLY for rail, MET for metro) and
# drop the children:
#   PLT  = metro/underground platform (N duplicates per station)
#   TMU  = tram/metro/underground entrance (e.g., 4900ZZLUTBY1)
#   RPL  = rail platform — duplicates its RLY parent
#
# RSE (rail station entrance) is NOT here, and is resolved by position instead
# — see the entrance handling in build_db(). Almost every RSE duplicates a
# station that is already present, but a handful do not, and the two cases
# cannot be told apart by StopType alone.
#
# They cannot be told apart by NAME either, which is the trap. The same station
# is called different things by the two records: the RLY is "Ashley Down" while
# its entrance is "Ashley Down Rail Station". Deduping on an exact name match
# therefore keeps 441 entrances whose station is standing right next to them.
# Position is the only reliable key.
_SKIP_STOP_TYPES = {'PLT', 'TMU', 'RPL'}

# StopTypes that establish a station in its own right, so a nearby entrance
# record is redundant.
_STATION_STOP_TYPES = {'RLY', 'MET'}

# An entrance within this distance of a station record is that station's
# entrance. Generous: large termini spread their entrances over a couple of
# hundred metres, and a false "no station here" costs a duplicate search
# result, while a false "already covered" costs a missing station.
_ENTRANCE_MATCH_M = 400.0
# Grid cell for the proximity lookup, in degrees — comfortably larger than
# _ENTRANCE_MATCH_M so the 3x3 neighbourhood always contains any match.
_GRID_DEG = 0.01


def _classify(atco: str, stop_type: str) -> tuple[str, str | None]:
    """Return (transit_type, wifi_ssid) for a stop, or raise ValueError to skip."""

    # National Rail. RSE is included because an entrance that survives the
    # dedupe in build_db() is the only record its station has, and it is a rail
    # station, not the bus stop the old fallback made it. (RPL children are
    # skipped before this is reached — see _SKIP_STOP_TYPES.)
    if stop_type in ('RLY', 'RSE') or atco.startswith('910'):
        return 'train', None

    # Ferry
    if stop_type in ('FER', 'FTD'):
        return 'ferry', None

    # 9400ZZ* = metro/underground/DLR/tram systems identified by sub-prefix
    if atco.startswith('9400ZZ'):
        sub = atco[6:8]  # e.g. 'LU', 'DL', 'CR', 'MA', 'TW', etc.
        if sub == 'LU':
            return 'underground', 'LUL-Free-Wifi'  # London Underground
        if sub == 'DL':
            return 'dlr', None                      # Docklands Light Railway
        if sub in ('TW', 'GL'):
            return 'underground', None              # Tyne & Wear Metro / Glasgow Subway
        # Northern Line Extension (opened 2021): Nine Elms + Battersea Power Station.
        # NE = Nine Elms (unambiguous).
        # Battersea uses 9400ZZBPSU* — the 'U' at index 9 distinguishes it from
        # Blackpool Tramway stops which use 9400ZZBPSH/SL/SR/ST.
        if sub == 'NE':
            return 'underground', 'LUL-Free-Wifi'
        if atco.startswith('9400ZZBPSU'):
            return 'underground', 'LUL-Free-Wifi'
        # All remaining 9400ZZ* = Croydon Tramlink, Manchester Metrolink,
        # Sheffield Supertram, Nottingham, Blackpool, Edinburgh, West Midlands, etc.
        return 'tram', None

    # LSE/LPE/LWN are London station entrances — keep as underground fallback
    if stop_type in ('LSE', 'LPE', 'LWN'):
        return 'underground', None

    # Bus/coach stops and everything else
    return _TYPE_MAP.get(stop_type, 'bus'), None


def osgb36_to_wgs84(easting: float, northing: float) -> tuple[float, float]:
    """British National Grid (EPSG:27700) -> WGS84 lat/lon.

    NaPTAN publishes every stop twice, as Easting/Northing and as Latitude/
    Longitude, but the lat/lon pair is blank on a handful of rows — including,
    as of the 2026-08 extract, all ten Elizabeth line core stations (Bond
    Street, Farringdon, Liverpool Street, Paddington, Tottenham Court Road,
    Whitechapel, Canary Wharf, Custom House, Abbey Wood, Woolwich). Those rows
    were being dropped for want of coordinates, so the Elizabeth line could
    neither be searched nor sequenced.

    Inverse transverse Mercator on the Airy 1830 ellipsoid, then a Helmert
    transform onto WGS84. Checked against the 5,227 NaPTAN rows that publish
    both representations: median error 0.19 m, 95th percentile 0.19 m. (The
    small tail beyond that is NaPTAN's own disagreement between its two
    coordinate fields, not the projection.)
    """
    import math

    # Airy 1830 / National Grid projection parameters.
    a, b = 6377563.396, 6356256.909
    f0 = 0.9996012717
    lat0, lon0 = math.radians(49.0), math.radians(-2.0)
    e0, n0 = 400000.0, -100000.0
    e2 = 1 - (b * b) / (a * a)
    n = (a - b) / (a + b)

    lat = (northing - n0) / (a * f0) + lat0
    m = 0.0
    for _ in range(100):
        m = b * f0 * (
            (1 + n + 1.25 * n**2 + 1.25 * n**3) * (lat - lat0)
            - (3 * n + 3 * n**2 + 2.625 * n**3)
              * math.sin(lat - lat0) * math.cos(lat + lat0)
            + (1.875 * n**2 + 1.875 * n**3)
              * math.sin(2 * (lat - lat0)) * math.cos(2 * (lat + lat0))
            - (35 / 24) * n**3
              * math.sin(3 * (lat - lat0)) * math.cos(3 * (lat + lat0))
        )
        if abs(northing - n0 - m) < 1e-5:
            break
        lat += (northing - n0 - m) / (a * f0)

    sin_lat = math.sin(lat)
    nu = a * f0 / math.sqrt(1 - e2 * sin_lat**2)
    rho = a * f0 * (1 - e2) / (1 - e2 * sin_lat**2) ** 1.5
    eta2 = nu / rho - 1

    tan_lat = math.tan(lat)
    sec_lat = 1 / math.cos(lat)
    t2, t4, t6 = tan_lat**2, tan_lat**4, tan_lat**6

    vii = tan_lat / (2 * rho * nu)
    viii = tan_lat / (24 * rho * nu**3) * (5 + 3 * t2 + eta2 - 9 * t2 * eta2)
    ix = tan_lat / (720 * rho * nu**5) * (61 + 90 * t2 + 45 * t4)
    x = sec_lat / nu
    xi = sec_lat / (6 * nu**3) * (nu / rho + 2 * t2)
    xii = sec_lat / (120 * nu**5) * (5 + 28 * t2 + 24 * t4)
    xiia = sec_lat / (5040 * nu**7) * (61 + 662 * t2 + 1320 * t4 + 720 * t6)

    de = easting - e0
    lat_osgb = lat - vii * de**2 + viii * de**4 - ix * de**6
    lon_osgb = lon0 + x * de - xi * de**3 + xii * de**5 - xiia * de**7

    # Helmert OSGB36 -> WGS84.
    h = 0.0
    sin_p, cos_p = math.sin(lat_osgb), math.cos(lat_osgb)
    sin_l, cos_l = math.sin(lon_osgb), math.cos(lon_osgb)
    nu2 = a / math.sqrt(1 - e2 * sin_p**2)
    x1 = (nu2 + h) * cos_p * cos_l
    y1 = (nu2 + h) * cos_p * sin_l
    z1 = ((1 - e2) * nu2 + h) * sin_p

    tx, ty, tz = 446.448, -125.157, 542.060
    s = -20.4894e-6
    rx = math.radians(0.1502 / 3600)
    ry = math.radians(0.2470 / 3600)
    rz = math.radians(0.8421 / 3600)

    x2 = tx + (1 + s) * x1 - rz * y1 + ry * z1
    y2 = ty + rz * x1 + (1 + s) * y1 - rx * z1
    z2 = tz - ry * x1 + rx * y1 + (1 + s) * z1

    a2, b2 = 6378137.000, 6356752.3142
    e22 = 1 - (b2 * b2) / (a2 * a2)
    p = math.hypot(x2, y2)
    lat2 = math.atan2(z2, p * (1 - e22))
    for _ in range(100):
        nu3 = a2 / math.sqrt(1 - e22 * math.sin(lat2) ** 2)
        new = math.atan2(z2 + e22 * nu3 * math.sin(lat2), p)
        if abs(new - lat2) < 1e-12:
            lat2 = new
            break
        lat2 = new
    return math.degrees(lat2), math.degrees(math.atan2(y2, x2))


# Bounds of the British National Grid, in metres. Anything outside is not a
# coordinate — most often a 0/0 placeholder.
_BNG_MAX_EASTING = 700_000
_BNG_MAX_NORTHING = 1_300_000
# Generous bounding box for the British Isles, used as a second, independent
# check on the projected result.
_GB_LAT = (49.5, 61.0)
_GB_LON = (-9.0, 2.2)


class _StationIndex:
    """Coarse spatial index over station records, for entrance deduplication.

    A dict of 0.01-degree cells is enough here: there are only a few thousand
    stations, lookups are one-off during the build, and it avoids pulling in a
    spatial library for a single proximity question.
    """

    def __init__(self):
        self._cells = {}

    @staticmethod
    def _cell(lat, lon):
        return (int(lat / _GRID_DEG), int(lon / _GRID_DEG))

    def add(self, lat, lon):
        self._cells.setdefault(self._cell(lat, lon), []).append((lat, lon))

    def nearest_within(self, lat, lon, metres=_ENTRANCE_MATCH_M):
        """Distance to the closest station, or None if none is that close."""
        import math
        cx, cy = self._cell(lat, lon)
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for slat, slon in self._cells.get((cx + dx, cy + dy), ()):
                    d = math.hypot(
                        (slat - lat) * 111_320,
                        (slon - lon) * 111_320 * math.cos(math.radians(lat)))
                    if d <= metres and (best is None or d < best):
                        best = d
        return best


def _recover_from_grid(row) -> tuple[float, float] | tuple[None, None]:
    """Lat/lon from a NaPTAN row's grid reference, or (None, None).

    NaPTAN leaves Latitude/Longitude blank on tens of thousands of rows while
    still publishing Easting/Northing — including every Elizabeth line core
    station. Those rows used to be dropped outright.

    Both the input and the projected output are range-checked. A 0/0 grid
    reference is a common placeholder and projects to a point off the coast of
    Cornwall, so accepting it silently would scatter thousands of stops into
    the sea and put them in range of a geofence lookup there. Rejecting is
    correct: a missing stop is a gap, a misplaced one is a wrong answer.
    """
    try:
        easting = float(row.get('Easting', '').strip())
        northing = float(row.get('Northing', '').strip())
    except (ValueError, TypeError, AttributeError):
        return None, None
    if not (0 < easting <= _BNG_MAX_EASTING and 0 < northing <= _BNG_MAX_NORTHING):
        return None, None
    try:
        lat, lon = osgb36_to_wgs84(easting, northing)
    except (ValueError, ZeroDivisionError, OverflowError):
        return None, None
    if not (_GB_LAT[0] <= lat <= _GB_LAT[1] and _GB_LON[0] <= lon <= _GB_LON[1]):
        return None, None
    return lat, lon


def _require_fts5(conn: sqlite3.Connection) -> None:
    """Abort early with a clear message if this Python's SQLite lacks FTS5.

    Without it the build would silently produce a database with no search
    index, and the app would fall back to full-table LIKE scans on 500k rows.
    """
    try:
        conn.execute('CREATE VIRTUAL TABLE _fts5_probe USING fts5(x)')
        conn.execute('DROP TABLE _fts5_probe')
    except sqlite3.OperationalError as e:
        sys.exit(
            f'FATAL: this Python build has no FTS5 support ({e}).\n'
            f'       sqlite3.sqlite_version = {sqlite3.sqlite_version}\n'
            '       Install a Python whose bundled SQLite enables FTS5, then re-run.'
        )


def create_topology_schema(conn: sqlite3.Connection) -> None:
    """Creates the route-topology tables the underground engine depends on.

    Without an ordered station sequence per line and direction there is no way to
    count stops, so this is the foundation for barometric/accelerometer arrival
    detection rather than an optional extra.

    Tables are created even when --with-topology is not passed, so the app can
    rely on their existence and simply find them empty.
    """
    conn.executescript('''
        -- One row per line (Northern, Victoria, DLR, ...).
        CREATE TABLE IF NOT EXISTS Lines (
            line_id   TEXT PRIMARY KEY,
            name      TEXT NOT NULL,
            mode      TEXT NOT NULL,
            colour    TEXT
        );

        -- Ordered station sequence. (line_id, direction, branch_id, seq_index)
        -- is the topology: seq_index N and N+1 are adjacent stations.
        -- branch_id separates divergent paths (e.g. Northern via Bank vs via
        -- Charing Cross) so a branch is a distinct ordered sequence, not a
        -- special case in the traversal code.
        CREATE TABLE IF NOT EXISTS RouteSequences (
            line_id    TEXT NOT NULL,
            direction  TEXT NOT NULL,
            branch_id  INTEGER NOT NULL DEFAULT 0,
            seq_index  INTEGER NOT NULL,
            stop_id    TEXT NOT NULL,
            PRIMARY KEY (line_id, direction, branch_id, seq_index)
        );
        CREATE INDEX IF NOT EXISTS idx_seq_stop
            ON RouteSequences(stop_id);
        CREATE INDEX IF NOT EXISTS idx_seq_line_dir
            ON RouteSequences(line_id, direction, branch_id, seq_index);

        -- Points where a line splits. The app prompts the user here (see the
        -- Kennington decision) instead of guessing from sensors.
        CREATE TABLE IF NOT EXISTS Branches (
            line_id       TEXT NOT NULL,
            direction     TEXT NOT NULL,
            stop_id       TEXT NOT NULL,
            branch_id     INTEGER NOT NULL,
            branch_label  TEXT,
            PRIMARY KEY (line_id, direction, stop_id, branch_id)
        );

        -- Expected travel seconds between adjacent stations. This is the timing
        -- prior that rejects mid-tunnel holds: an accelerometer stop that
        -- arrives too early cannot be the next platform.
        -- `seconds` is the UNIMPEDED run time: the train moving with no holds,
        -- i.e. a physical floor. The timing gate uses it as the lower bound.
        -- `peak_seconds` is the AM-peak scheduled time and informs the upper
        -- bound only, so congestion widens the window without raising the floor.
        CREATE TABLE IF NOT EXISTS RunTimes (
            line_id      TEXT NOT NULL,
            from_stop    TEXT NOT NULL,
            to_stop      TEXT NOT NULL,
            seconds      INTEGER NOT NULL,
            peak_seconds INTEGER,
            source       TEXT NOT NULL DEFAULT 'estimate',
            PRIMARY KEY (line_id, from_stop, to_stop)
        );

        -- Platform depth below street level, metres, plus the platform's
        -- altitude above sea level.
        --
        -- Keyed by (stop_id, line_id) because depth is a property of the
        -- platform, not the station: Bank is 20.5 m on the Central line but
        -- 29.6 m on the Northern. A station-level average would be wrong by
        -- ~9 m at exactly the interchanges where precision matters most.
        --
        -- `platform_level_asl_m` is the column the barometer actually needs.
        -- A barometer measures a *change in altitude*, so the expected reading
        -- between two stations is the difference in their platform altitudes.
        -- `depth_metres` alone cannot express that: it is measured from each
        -- station's own street, and streets are not level with one another.
        -- Tooting Broadway's is 16 m above sea level and Hampstead's is 108 m,
        -- so treating depth as descent is wrong by far more than the engine's
        -- 12 m tolerance. Keep depth for display; match on altitude.
        --
        -- Populated by tools/ingest_tfl_reference.py from TfL FOI data, with
        -- the 100 m tunnel-datum correction applied. `source` distinguishes
        -- 'tfl_foi' from 'tfl_foi_shared_platform' / 'estimate' / 'measured'
        -- so the engine can weight them.
        CREATE TABLE IF NOT EXISTS StationDepths (
            stop_id              TEXT NOT NULL,
            line_id              TEXT NOT NULL DEFAULT '',
            depth_metres         REAL NOT NULL,
            platform_level_asl_m REAL,
            source               TEXT NOT NULL DEFAULT 'estimate',
            PRIMARY KEY (stop_id, line_id)
        );

        -- Ground elevation at the station, metres above Ordnance Datum.
        --
        -- Two jobs. For an Underground station it is the term that converts a
        -- published depth into an altitude. For everything else — the DLR,
        -- Elizabeth line, Overground and the Bakerloo north of Queen's Park —
        -- no open dataset publishes platform depths at all, but those stations
        -- are at the surface, so ground elevation *is* the platform altitude
        -- and this table is the only prior they get.
        --
        -- Populated by tools/fetch_elevation.py from OS Terrain 50 (OGL).
        CREATE TABLE IF NOT EXISTS Elevation (
            stop_id       TEXT PRIMARY KEY,
            ground_elev_m REAL NOT NULL,
            easting       INTEGER,
            northing      INTEGER,
            source        TEXT NOT NULL DEFAULT 'os_terrain_50'
        );
    ''')


def _naptan_alias(tfl_id: str) -> str | None:
    """The NaPTAN stop id behind a TfL station-level naptanId, if different.

    THIS IS NOT COSMETIC. The two namespaces do not overlap at all:

        TfL   /Line/northern/StopPoints  ->  940GZZLUHTD   (Hampstead)
        NaPTAN Stops.csv, StopType MET   ->  9400ZZLUHTD

    Character 4 encodes the record class — 'G' is the station group TfL
    publishes, '0' is the stop record NaPTAN publishes. Matching the raw TfL id
    against StopPoints therefore matches *nothing*: measured against live data,
    0 of 360 TfL station ids appear in NaPTAN, and all 360 do after this
    substitution. Before it, ingest_topology() counted every id as unmatched and
    wrote an empty RouteSequences, which the app reports as "Route data not
    installed" while silently falling back to GPS on every underground journey.

    The same rule covers National Rail stations on the Elizabeth line and
    Overground (TfL 910GBONDST -> NaPTAN 9100BONDST), so it is applied by
    position rather than special-cased per mode.
    """
    if len(tfl_id) > 4 and tfl_id[3] == 'G':
        return tfl_id[:3] + '0' + tfl_id[4:]
    return None


def _make_stop_resolver(known: set):
    """TfL naptanId -> local StopPoints id, or None if we do not have the stop.

    Tries the id as published first so that a future TfL change to emitting
    plain NaPTAN ids keeps working without another fix here.
    """
    def resolve(naptan_id: str):
        if naptan_id in known:
            return naptan_id
        alias = _naptan_alias(naptan_id)
        if alias and alias in known:
            return alias
        return None
    return resolve


def _tfl_get(url: str):
    """GETs JSON from the TfL API, returning None on any failure.

    Topology is an enhancement: a network hiccup must not fail the whole build
    and leave the user without a stop database.
    """
    import json
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'StopSnoozer-build'})
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.loads(r.read().decode('utf-8'))
    except Exception as e:
        print(f'\n  WARN: TfL request failed ({type(e).__name__}: {e})')
        print(f'        {url}')
        return None


def _estimate_run_time(conn, line_id, from_stop, to_stop) -> int:
    """Straight-line distance / assumed average speed, as a placeholder prior.

    Deliberately crude. Real inter-station times must come from timetables or
    field measurement (see the field-test protocol); this only gives the timing
    gate a sane starting value so the fusion test is not comparing against zero.
    Tube average including dwell is roughly 33 km/h ≈ 9.2 m/s.
    """
    row = conn.execute(
        'SELECT a.latitude, a.longitude, b.latitude, b.longitude '
        'FROM StopPoints a, StopPoints b WHERE a.id=? AND b.id=?',
        (from_stop, to_stop),
    ).fetchone()
    if not row:
        return 120
    import math
    lat1, lon1, lat2, lon2 = row
    # Equirectangular approximation is fine at inter-station scale.
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    metres = 6_371_000 * math.hypot(x, y)
    # Track distance exceeds straight-line; 1.25 is a common curvature factor.
    return max(45, min(600, int(metres * 1.25 / 9.2)))


def ingest_topology(conn: sqlite3.Connection) -> None:
    """Fetches TfL line/route sequences into the topology tables.

    Matches TfL StopPoint naptanIds against NaPTAN ids already in StopPoints.
    Any sequence entry whose stop is unknown locally is skipped and counted, so a
    mismatch shows up as a number rather than silently corrupting the sequence.
    """
    print('Fetching TfL line routes...')
    lines = _tfl_get(TFL_LINES_URL)
    if not lines:
        print('  Skipping topology — TfL unreachable. Tables left empty.')
        return

    seen = set()
    for ln in lines:
        lid = ln.get('id')
        if not lid or lid in seen:
            continue
        seen.add(lid)
        conn.execute(
            'INSERT OR REPLACE INTO Lines(line_id,name,mode,colour) VALUES (?,?,?,?)',
            (lid, ln.get('name') or lid, ln.get('modeName') or 'tube', None),
        )
    print(f'  {len(seen)} lines.')

    known = {r[0] for r in conn.execute('SELECT id FROM StopPoints')}
    to_stop_id = _make_stop_resolver(known)
    total_seq = 0
    total_unmatched = 0
    total_branches = 0
    unmatched_samples = set()

    for i, lid in enumerate(sorted(seen), 1):
        for direction in ('inbound', 'outbound'):
            data = _tfl_get(TFL_SEQ_URL.format(line=lid, direction=direction))
            if not data:
                continue
            # orderedLineRoutes gives one entry per branch, already in order.
            branches = data.get('orderedLineRoutes') or []
            for branch_id, br in enumerate(branches):
                ids = br.get('naptanIds') or []
                seq_index = 0
                prev = None
                for naptan in ids:
                    stop_id = to_stop_id(naptan)
                    if stop_id is None:
                        total_unmatched += 1
                        if len(unmatched_samples) < 8:
                            unmatched_samples.add(naptan)
                        continue
                    conn.execute(
                        'INSERT OR REPLACE INTO RouteSequences'
                        '(line_id,direction,branch_id,seq_index,stop_id) '
                        'VALUES (?,?,?,?,?)',
                        (lid, direction, branch_id, seq_index, stop_id),
                    )
                    if prev is not None:
                        conn.execute(
                            'INSERT OR IGNORE INTO RunTimes'
                            '(line_id,from_stop,to_stop,seconds,source) '
                            'VALUES (?,?,?,?,?)',
                            (lid, prev, stop_id,
                             _estimate_run_time(conn, lid, prev, stop_id),
                             'estimate'),
                        )
                    prev = stop_id
                    seq_index += 1
                    total_seq += 1
            if len(branches) > 1:
                total_branches += _record_branch_points(
                    conn, lid, direction, branches, to_stop_id)
        print(f'\r  {i}/{len(seen)} lines processed...', end='', flush=True)

    print(f'\r  {total_seq:,} sequence entries, {total_branches} branch points, '
          f'{total_unmatched:,} unmatched NaPTAN ids.        ')
    if unmatched_samples:
        print(f'  unmatched examples: {sorted(unmatched_samples)}')
    # An empty topology is the failure mode the app cannot detect for itself:
    # it just shows "Route data not installed" and uses GPS underground.
    if total_seq == 0:
        print('  ERROR: topology is EMPTY — no TfL stop matched a NaPTAN id.')
        print('         Check _naptan_alias(); the id namespaces have diverged.')


def _record_branch_points(conn, line_id, direction, branches, to_stop_id) -> int:
    """Records the stations where branches diverge.

    A divergence is the last stop shared by two branches: the app must ask the
    user which way they are going *before* that station's successors differ.

    Ids are mapped to local StopPoints ids here for the same reason as in
    ingest_topology — comparing raw TfL ids would leave every sequence empty and
    silently record no branch points at all.
    """
    seqs = []
    for br in branches:
        resolved = (to_stop_id(n) for n in (br.get('naptanIds') or []))
        seqs.append([s for s in resolved if s is not None])

    count = 0
    for a in range(len(seqs)):
        for b in range(a + 1, len(seqs)):
            sa, sb = seqs[a], seqs[b]
            common = 0
            while common < len(sa) and common < len(sb) and sa[common] == sb[common]:
                common += 1
            if common == 0 or common >= len(sa) or common >= len(sb):
                continue
            divergence_stop = sa[common - 1]
            for branch_id, nxt in ((a, sa[common]), (b, sb[common])):
                label = conn.execute(
                    'SELECT name FROM StopPoints WHERE id=?', (nxt,)
                ).fetchone()
                conn.execute(
                    'INSERT OR REPLACE INTO Branches'
                    '(line_id,direction,stop_id,branch_id,branch_label) '
                    'VALUES (?,?,?,?,?)',
                    (line_id, direction, divergence_stop, branch_id,
                     f'via {label[0]}' if label else None),
                )
            count += 1
    return count


def build_search_index(conn: sqlite3.Connection) -> None:
    """Builds the FTS5 prefix index used by StopPointsDb.searchStops().

    External-content table (content='StopPoints'): the index is stored but the
    text is not duplicated, so this costs index size only. prefix='2 3 4'
    precomputes 2/3/4-character prefixes so autocomplete does not have to scan
    the term list on every keystroke.
    """
    print('  Building FTS5 search index...')
    conn.execute('''
        CREATE VIRTUAL TABLE StopPointsFts USING fts5(
            name,
            content='StopPoints',
            content_rowid='rowid',
            tokenize="unicode61 remove_diacritics 2",
            prefix='2 3 4'
        )
    ''')
    conn.execute(
        "INSERT INTO StopPointsFts(rowid, name) SELECT rowid, name FROM StopPoints"
    )
    # Merge the b-tree into one segment so first-query latency is not paid by the user.
    conn.execute("INSERT INTO StopPointsFts(StopPointsFts) VALUES('optimize')")


def _progress(block_num, block_size, total_size):
    downloaded = block_num * block_size
    if total_size > 0:
        pct = min(100, downloaded * 100 // total_size)
        mb  = downloaded / 1_000_000
        tot = total_size / 1_000_000
        print(f'\r  {pct:3d}%  {mb:6.1f} / {tot:.1f} MB', end='', flush=True)


def download(url: str, dest: str) -> None:
    print(f'Downloading NaPTAN CSV from DfT API...')
    urllib.request.urlretrieve(url, dest, _progress)
    print(f'\n  Saved to {dest} ({os.path.getsize(dest)/1e6:.1f} MB)')


def build_db(csv_path: str, db_path: str,
             with_topology: bool = False,
             with_reference: bool = False) -> tuple[int, int]:
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    _require_fts5(conn)
    # page_size must be set before any writes on a new database
    conn.execute('PRAGMA page_size = 16384;')
    # user_version = 3: Flutter checks this to decide whether to re-extract the asset.
    # v3 added the StopPointsFts full-text index (replaces LIKE '%…%' scanning).
    conn.execute(f'PRAGMA user_version = {SCHEMA_VERSION};')
    conn.execute('''
        CREATE TABLE StopPoints (
            id           TEXT PRIMARY KEY,
            name         TEXT NOT NULL,
            transit_type TEXT NOT NULL,
            latitude     REAL NOT NULL,
            longitude    REAL NOT NULL,
            wifi_ssid    TEXT,
            indicator    TEXT
        )
    ''')

    inserted  = 0
    skipped   = 0
    recovered = 0
    batch     = []
    # Names that already have a station record, and the entrance rows whose
    # fate depends on them. See _SKIP_STOP_TYPES.
    station_index = _StationIndex()
    deferred_entrances = []

    print('Processing rows...')
    with open(csv_path, encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Only active stops
            if row.get('Status', '').strip().lower() != 'active':
                skipped += 1
                continue

            atco      = row.get('ATCOCode', '').strip()
            name      = row.get('CommonName', '').strip()
            lat_str   = row.get('Latitude', '').strip()
            lon_str   = row.get('Longitude', '').strip()
            stop_type = row.get('StopType', '').strip()
            indicator = row.get('Indicator', '').strip() or None

            if not atco or not name:
                skipped += 1
                continue

            try:
                lat = float(lat_str)
                lon = float(lon_str)
            except ValueError:
                # Blank lat/lon but a valid grid reference: recoverable, and
                # worth recovering — every Elizabeth line core station lands
                # here, along with ~31k bus stops. See osgb36_to_wgs84().
                lat, lon = _recover_from_grid(row)
                if lat is None:
                    skipped += 1
                    continue
                recovered += 1

            # Skip platform and area-reference records (they duplicate MET station entries)
            if stop_type in _SKIP_STOP_TYPES:
                skipped += 1
                continue

            if stop_type in _STATION_STOP_TYPES:
                station_index.add(lat, lon)

            # Entrances are held back until every station record has been seen,
            # because whether an entrance is a duplicate depends on a row that
            # may appear later in the file.
            if stop_type == 'RSE':
                deferred_entrances.append(
                    (atco, name, lat, lon, indicator))
                continue

            transit_type, wifi_ssid = _classify(atco, stop_type)

            batch.append((atco, name, transit_type, lat, lon, wifi_ssid, indicator))
            inserted += 1

            if len(batch) >= 10_000:
                conn.executemany(
                    'INSERT OR IGNORE INTO StopPoints VALUES (?,?,?,?,?,?,?)',
                    batch,
                )
                batch.clear()
                print(f'\r  {inserted:,} rows...', end='', flush=True)

    if batch:
        conn.executemany(
            'INSERT OR IGNORE INTO StopPoints VALUES (?,?,?,?,?,?,?)',
            batch,
        )

    # Now that every station record has been seen, resolve the entrances by
    # POSITION. Names cannot do this: the same station is "Ashley Down" as an
    # RLY record and "Ashley Down Rail Station" as its entrance, so an exact
    # name match keeps 441 entrances standing next to their own station.
    # Multiple doors of one station also collapse to the first — a user picking
    # a destination wants "Darlington Rail Station", not a choice between its
    # main and Park Lane entrances.
    kept_entrances = []
    kept_index = _StationIndex()
    for atco, name, lat, lon, indicator in deferred_entrances:
        # Already covered by a real station record, or by an entrance of the
        # same station we have just decided to keep (large stations have
        # several doors and we want one row, not one per door).
        if (station_index.nearest_within(lat, lon) is not None
                or kept_index.nearest_within(lat, lon) is not None):
            skipped += 1
            continue
        kept_index.add(lat, lon)
        transit_type, wifi_ssid = _classify(atco, 'RSE')
        kept_entrances.append(
            (atco, name, transit_type, lat, lon, wifi_ssid, indicator))
    if kept_entrances:
        conn.executemany(
            'INSERT OR IGNORE INTO StopPoints VALUES (?,?,?,?,?,?,?)',
            kept_entrances,
        )
        inserted += len(kept_entrances)

    print(f'\r  {inserted:,} rows inserted, {skipped:,} skipped.   ')
    if deferred_entrances:
        print(f'  {len(kept_entrances):,} station(s) kept from entrance records '
              f'only (no RLY record exists for them); '
              f'{len(deferred_entrances) - len(kept_entrances):,} '
              f'duplicate entrances dropped.')
    if recovered:
        print(f'  {recovered} row(s) had no lat/lon and were recovered from '
              f'their grid reference.')
    print('  Building index...')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_stop_name ON StopPoints(name);')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_stop_type ON StopPoints(transit_type);')
    # Bounding-box lookups in getClosestStops() filter on both coordinates.
    conn.execute('CREATE INDEX IF NOT EXISTS idx_stop_latlon ON StopPoints(latitude, longitude);')
    build_search_index(conn)
    create_topology_schema(conn)
    conn.commit()

    if with_topology:
        ingest_topology(conn)
        conn.commit()
    else:
        print('  Topology tables created empty (pass --with-topology to populate).')

    if with_reference:
        # Order matters. Elevation needs RouteSequences to know which stops are
        # worth sampling, and the depth ingest needs Elevation to give surface
        # stations a platform altitude, so it runs between the two.
        import fetch_elevation
        fetch_elevation.ingest(conn)
        conn.commit()
        # Must run after topology: coverage reporting joins against RouteSequences,
        # and real run times overwrite the geometric estimates written above.
        import ingest_tfl_reference
        ingest_tfl_reference.ingest(conn)
    else:
        print('  Depths/run-times not ingested (pass --with-reference).')
        print('  WARNING: without this, StationDepths is empty and run times are')
        print('           crude geometric estimates — the barometric half of the')
        print('           fusion test is disabled and the timing gate is unreliable.')

    print('  Vacuuming...')
    conn.execute('VACUUM')
    conn.close()
    return inserted, skipped


def compress(db_path: str, gz_path: str) -> None:
    os.makedirs(os.path.dirname(gz_path) or '.', exist_ok=True)
    print(f'Compressing {db_path} → {gz_path} ...')
    db_size = os.path.getsize(db_path)
    with open(db_path, 'rb') as src, gzip.open(gz_path, 'wb', compresslevel=6) as dst:
        done = 0
        while chunk := src.read(1_048_576):
            dst.write(chunk)
            done += len(chunk)
            print(f'\r  {done/db_size*100:.0f}%', end='', flush=True)
    gz_size = os.path.getsize(gz_path)
    print(f'\r  {db_size/1e6:.1f} MB → {gz_size/1e6:.1f} MB '
          f'({gz_size/db_size*100:.0f}% of original)')


def main():
    want_all      = '--all' in sys.argv
    with_topology = want_all or '--with-topology' in sys.argv
    with_reference = want_all or '--with-reference' in sys.argv
    keep_csv      = '--keep-csv' in sys.argv

    if not (with_topology and with_reference):
        print('NOTE: for a fully-featured database use --all, which is')
        print('      --with-topology (TfL route sequences) plus')
        print('      --with-reference (FOI platform depths + real run times).')
        print('      Underground tracking needs both.\n')

    try:
        if not (keep_csv and os.path.exists(CSV_TEMP)):
            download(API_URL, CSV_TEMP)
        build_db(CSV_TEMP, DB_TEMP, with_topology=with_topology,
                 with_reference=with_reference)
        compress(DB_TEMP, GZ_OUT)
    except BaseException:
        # Keep the intermediates on failure. This build downloads ~100 MB and
        # takes minutes; deleting a fully-built database because something
        # trivial threw afterwards means paying for all of it again, and
        # discards the evidence needed to diagnose the failure.
        print(f'\nBuild failed. Kept {DB_TEMP} and {CSV_TEMP} for inspection; '
              f're-run with --keep-csv to reuse the download.')
        raise
    else:
        cleanup = (CSV_TEMP, DB_TEMP) if not keep_csv else (DB_TEMP,)
        for f in cleanup:
            if os.path.exists(f):
                os.remove(f)

    print(f'\nDone!  {GZ_OUT} is ready to bundle.')
    print(f'Schema version {SCHEMA_VERSION} — StopPointsDb._requiredVersion '
          'must match this.')


if __name__ == '__main__':
    main()
