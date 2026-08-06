"""
ingest_tfl_reference.py
Populates the StationDepths and RunTimes tables from authoritative TfL data.

These two tables are what make the underground fusion test work:

  * StationDepths gives the barometer something to match against.
  * RunTimes gives the timing gate the prior that rejects mid-tunnel holds.

Both were previously empty or geometric guesses. Sources:

  Platform levels  — TfL FOI-0493-2223, served by TfL itself as CSV:
                     https://foi.tfl.gov.uk/FOI-0493-2223/Copy%20of%20Station%20depths.csv
                     Licensed under the TfL Open Data terms, so it is the
                     licence-clean primary. The ianvisits xlsx mirror of the
                     same release is kept only as a fallback for when TfL's
                     FOI host is down — see DEPTH_SOURCES.
  Run times        — TfL FOI-2748-2223 "Inter station database.xlsx", unimpeded
                     and peak running times between adjacent stations.

Run standalone against an existing database:
    python tools/ingest_tfl_reference.py --db _naptan_temp.db

or let build_naptan_db.py call it with --with-reference.

Run it AFTER topology. Station names are resolved per line (see resolve()),
which needs RouteSequences populated; without it the ambiguous names below fall
back to a guess. build_naptan_db.py --all already orders the two correctly.

--------------------------------------------------------------------------
THE TUNNEL DATUM CORRECTION  (read before touching depth handling)
--------------------------------------------------------------------------
TfL records platform levels against "London Underground Datum", which is
100 m below Ordnance Datum Newlyn — chosen so engineers never work with
negative numbers. The spreadsheet states this in its own notes rows.

So a published value of 88.19 is NOT 88 m of anything useful. It is:

    level above sea level = published - 100          =>  -11.81 m
    depth below street    = ground_level - (published - 100)

The sheet carries a per-station "Ground Level outside Station" column, so no
external elevation dataset is needed.

Validated against four independent published facts:
    Hampstead        58.5 m  (documented deepest on the network)   -> computes 58.5
    Greenford       -10.2 m  (above ground, so negative)           -> computes -10.2
    Waterloo Jubilee -26 m above sea level                         -> computes -26.0
    Acton Town        5.5 m  (sub-surface District)                -> computes  5.5
Those checks run automatically; see verify_known_depths().

--------------------------------------------------------------------------
WHAT THIS SOURCE DOES NOT GIVE YOU  (known, accepted gaps)
--------------------------------------------------------------------------
* No Circle column. The Circle shares sub-surface track with the District,
  H&C and Metropolitan, so its depths are derived from those — see
  derive_shared_platform_depths(). All 36 Circle stations are covered that way.
* No Elizabeth line or DLR columns, and no open dataset publishes them. Those
  stations get no barometric prior at all; the engine falls back to the two
  non-barometric conditions.
* Branch-split platforms are averaged. Euston, Camden Town and Kennington each
  appear twice (City branch vs Charing X branch) and StationDepths has no
  branch dimension, so the two are meaned. Worst case is Euston: 33.1 m City
  vs 21.4 m Charing X, meaned to 27.3 m, so either branch is ~5.9 m out. That
  sits inside UndergroundEngine.DEPTH_MATCH_TOLERANCE_M (12 m) and is
  deliberately left alone — adding a branch column would be a schema migration
  for an error the tolerance already absorbs. Revisit if that constant is
  calibrated downwards past ~7 m.
"""

import argparse
import csv
import os
import re
import sqlite3
import sys
import urllib.request

try:
    import openpyxl
except ImportError:
    sys.exit('FATAL: openpyxl required.  pip install openpyxl')

# Tried in order. TfL's own FOI host is first because it is the licence-clean
# primary; the mirror is a third-party upload of the same release and is only
# reached for if TfL is unavailable. Both carry the identical grid layout, so
# parse_depths() reads either — but note the mirror has silently *corrected*
# TfL's "Metropoliton" header typo, which is why LINE_IDS maps both spellings.
DEPTH_SOURCES = [
    ('https://foi.tfl.gov.uk/FOI-0493-2223/Copy%20of%20Station%20depths.csv',
     '_tfl_depths.csv'),
    ('https://www.ianvisits.co.uk/articles/wp-content/uploads/'
     'sites/2/2011/07/Station-depths.xlsx', '_tfl_depths.xlsx'),
]

RUNTIMES_URL = ('https://www.whatdotheyknow.com/request/'
                'distance_and_inter_station_runni/response/201950/attach/2/'
                'Inter%20station%20database.xlsx')

RUNTIMES_FILE = '_tfl_runtimes.xlsx'

# TfL's tunnel datum offset, metres below Ordnance Datum Newlyn.
TUNNEL_DATUM_OFFSET_M = 100.0

# ── Station-name matching ────────────────────────────────────────────────────
# The spreadsheets and NaPTAN disagree on punctuation, line qualifiers and
# branch suffixes. Every unmatched name is a silently missing prior, so this is
# deliberately thorough and reports its own hit rate.

ALIASES = {
    'heathrow 123': 'heathrow terminals 2 and 3',
    'heathrow terminals 1 2 and 3': 'heathrow terminals 2 and 3',
    'heathrow terminals 123': 'heathrow terminals 2 and 3',
    # FOI-0493 writes this one out in full, with "Airport" and a comma:
    # "Heathrow Airport Terminal 1, 2 & 3".
    'heathrow airport terminal 1 2 and 3': 'heathrow terminals 2 and 3',
    'heathrow terminal 1 2 and 3': 'heathrow terminals 2 and 3',
    'heathrow 5': 'heathrow terminal 5',
    'heathrow terminal four': 'heathrow terminal 4',
    'heathrow terminal 4 loop': 'heathrow terminal 4',
    'totteridge': 'totteridge and whetstone',
    'highbury': 'highbury and islington',
    'kings cross': 'kings cross st pancras',
    'walthamstow': 'walthamstow central',
    'bromley': 'bromley by bow',
}

# One line name as it may appear inside a parenthesised qualifier.
_LINE_WORD = (
    r'bakerloo|central|district|dist\s*and\s*picc|dist|dis|circle'
    r'|h\s*and\s*c|hc|hammersmith|jubilee|met|metropolitan|metropoliton'
    r'|northern|piccadilly|picc|victoria|w\s*and\s*c|waterloo|dlr|elizabeth'
    r'|london|city|cx|hb|nb|sb'
)

# "(H&C Line)", "(Dist&Picc Line)", "(MET)", "(CX)", "(City)", "(HB)" and also
# comma-separated lists — FOI-0493 labels the sub-surface Edgware Road
# "Edgware Road (Circle, District, H & C)". Note '&' has already become ' and '
# by the time this runs, so the separator alternation has to accept "and" too.
_QUALIFIER = re.compile(
    r'\(\s*(?:' + _LINE_WORD + r')'
    r'(?:\s*(?:,|and|/)\s*(?:' + _LINE_WORD + r'))*'
    r'(?:\s+line)?\s*\)', re.I)
_BRANCH = re.compile(r'\b(?:charing\s*x|charing\s*cross|city)\s+branch\b', re.I)
_NOISE = re.compile(r'\b(?:underground|station|rail|dlr|lu|tube|line)\b', re.I)

# Rows in the depth sheet that are prose notes, not stations.
_NOTE_WORDS = re.compile(
    r'\b(?:datum|notes?|gradients?|approximation|indicative|variations?|ordnance'
    r'|settlement|maintenance|referred)\b', re.I)


def _base_normalise(name: str) -> str:
    """Shared cleanup, apostrophes left for the caller to decide."""
    s = str(name).strip()
    s = s.replace('’', "'")
    s = s.replace('&', ' and ')
    s = _BRANCH.sub(' ', s)
    s = _QUALIFIER.sub(' ', s)
    s = _NOISE.sub(' ', s)
    return s


def normalise_variants(name: str):
    """All plausible normalised keys for a station name.

    Two apostrophe treatments are needed because the sources are inconsistent
    about possessives:

        NaPTAN "Earl's Court"        FOI "EARLS COURT"      -> needs 's -> s
        NaPTAN "St. James's Park"    FOI "ST JAMES PARK"    -> needs 's -> ''

    Collapsing to one rule breaks the other, so both keys are indexed.
    """
    s = _base_normalise(name)
    out = []
    for repl in ('s', ''):
        t = re.sub(r"'s\b", repl, s)
        t = t.replace("'", '')
        t = re.sub(r'[^A-Za-z0-9]+', ' ', t)
        t = ' '.join(t.split()).lower()
        if t:
            out.append(ALIASES.get(t, t))
    seen, uniq = set(), []
    for k in out:
        if k not in seen:
            seen.add(k)
            uniq.append(k)
    return uniq


# Longest genuine station name in FOI-0493 is 7 words
# ("Edgware Road (Circle, District, H & C)"), and the shortest note row is also
# 7 ("Levels are referred to London Underground Datum") — so word count alone
# cannot separate them and _NOTE_WORDS carries the load at that length.
# The threshold sits just above the longest station name rather than below it:
# at 6 it silently discarded Edgware Road (Circle), Heathrow Terminals 1/2/3
# and Shepherd's Bush Market, taking their depths with them.
_MAX_STATION_WORDS = 7


def is_note_row(text: str) -> bool:
    """True for the sheet's trailing explanatory prose.

    Callers additionally require a numeric ground level, which on its own
    rejects every note row in FOI-0493. This is the second line of defence, so
    it is tuned to avoid false positives on real stations rather than to catch
    every conceivable note.
    """
    t = str(text).strip()
    if not t:
        return True
    if t.lower() in ('notes', 'note'):
        return True
    if len(t.split()) > _MAX_STATION_WORDS:
        return True
    return bool(_NOTE_WORDS.search(t))


def build_naptan_index(conn):
    """normalised name -> candidate stop_ids, best first.

    A *list*, not a single id, because several London names are genuinely
    ambiguous once line qualifiers are normalised away:

        "edgware road"  -> 940GZZLUERB (Bakerloo, 24.9 m deep tube)
                           940GZZLUERC (Circle/District/H&C, 5.2 m sub-surface)
        "hammersmith"   -> 940GZZLUHSD (District & Piccadilly)
                           940GZZLUHSC (Circle & Hammersmith and City)

    Collapsing those to one id attributed a 24.9 m deep-tube platform to a
    5.2 m sub-surface one — a 19.7 m error, wider than the engine's 12 m depth
    tolerance. resolve() picks between the candidates using the line the row
    came from.

    Ordering within a key is (transit type, then id) so it is deterministic:
    Underground beats DLR beats rail. Rail is included because several rows in
    the TfL sheets are Overground / former East London Line stations that
    NaPTAN does not classify as Underground.
    """
    rank = {'underground': 0, 'dlr': 1, 'train': 2}
    index = {}
    rows = conn.execute(
        "SELECT id, name, transit_type FROM StopPoints "
        "WHERE transit_type IN ('underground','dlr','train')")
    for stop_id, name, tt in rows:
        r = rank.get(tt, 9)
        for key in normalise_variants(name):
            index.setdefault(key, []).append((r, stop_id))
    return {k: [sid for _, sid in sorted(set(v))] for k, v in index.items()}


def line_members(conn):
    """line_id -> set of stop_ids the line actually serves, from RouteSequences.

    This is what makes an ambiguous name resolvable: the spreadsheets say which
    line each depth or leg belongs to, and only one of the candidate stations is
    on that line. Returns {} when topology has not been ingested, in which case
    resolve() degrades to the old best-guess behaviour.
    """
    try:
        rows = conn.execute(
            'SELECT line_id, stop_id FROM RouteSequences').fetchall()
    except sqlite3.Error:
        return {}
    members = {}
    for line_id, stop_id in rows:
        members.setdefault(line_id, set()).add(stop_id)
    return members


def resolve(index, name, line_id=None, members=None):
    """Best stop_id for a spreadsheet station name, or None.

    When `line_id` and `members` are supplied, a candidate that the line
    actually serves always wins — across every normalised variant, not just the
    first one that happens to match. Only if no variant yields an on-line
    candidate does it fall back to the first match, which keeps standalone runs
    against a topology-less database working exactly as before.
    """
    on_line = members.get(line_id) if (members and line_id) else None
    fallback = None
    for key in normalise_variants(name):
        candidates = index.get(key)
        if not candidates:
            continue
        if fallback is None:
            fallback = candidates[0]
        if on_line:
            for stop_id in candidates:
                if stop_id in on_line:
                    return stop_id
    return fallback


# ── Line-name mapping to TfL Unified API ids ────────────────────────────────
# RouteSequences uses Unified API line ids; the spreadsheets use display names.

LINE_IDS = {
    'bakerloo': 'bakerloo',
    'central': 'central',
    'circle': 'circle',
    'district': 'district',
    'hammersmith and city': 'hammersmith-city',
    'hammersmith & city': 'hammersmith-city',
    'h and c': 'hammersmith-city',        # the run-time sheet writes "H & C"
    'hand c': 'hammersmith-city',
    # 'East London' closed in 2007 and reopened as London Overground; it has no
    # Unified API tube line id, so those legs are intentionally dropped.
    'east london': None,
    'jubilee': 'jubilee',
    'metropolitan': 'metropolitan',
    # TfL's own FOI-0493 CSV misspells the column header. Dropping it would
    # lose every Metropolitan depth (35 stations) with only an "unmapped line
    # names" line in the log to show for it. The ianvisits mirror spells it
    # correctly, so which spelling appears depends on which source answered.
    'metropoliton': 'metropolitan',
    'northern': 'northern',
    'piccadilly': 'piccadilly',
    'victoria': 'victoria',
    'waterloo and city': 'waterloo-city',
    'waterloo & city': 'waterloo-city',
    'elizabeth': 'elizabeth',
    'dlr': 'dlr',
}


def line_id_of(display_name):
    """Unified API line id, or None when the line is intentionally unsupported.

    Returning None for a *known* defunct line (East London) and for an unknown
    one is deliberate: both should be skipped, and the caller reports unknown
    names so a future TfL renaming surfaces as output rather than silence.
    """
    if not display_name:
        return None
    key = str(display_name).strip().lower().replace('&', ' and ')
    key = ' '.join(key.split())
    if key in LINE_IDS:
        return LINE_IDS[key]
    return None


def is_known_unsupported_line(display_name):
    key = ' '.join(str(display_name or '').strip().lower()
                   .replace('&', ' and ').split())
    return key in LINE_IDS and LINE_IDS[key] is None


# ── Download ────────────────────────────────────────────────────────────────

def _looks_like_payload(data, dest):
    """Cheap sanity check that we got the file and not an error page.

    An HTML error page is still HTTP 200 from some hosts, and would otherwise
    be parsed as an empty spreadsheet and reported as "0 stations matched".
    """
    if dest.endswith('.xlsx'):
        return data.startswith(b'PK')
    head = data[:512].lstrip().lower()
    return not head.startswith((b'<!doctype', b'<html'))


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 1024:
        print(f'  using cached {dest}')
        return True
    print(f'  downloading {dest} ...')
    try:
        req = urllib.request.Request(
            url, headers={'User-Agent': 'Mozilla/5.0 StopSnoozer-build'})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        if not _looks_like_payload(data, dest):
            print('  WARN: response is not the expected file (got HTML?) — skipping')
            return False
        with open(dest, 'wb') as f:
            f.write(data)
        print(f'  saved {len(data):,} bytes')
        return True
    except Exception as e:
        print(f'  WARN: download failed ({type(e).__name__}: {e})')
        return False


def download_first_available(sources):
    """Downloads the first reachable source, returning its local path or None."""
    for url, dest in sources:
        if download(url, dest):
            return dest
        print(f'  falling back to the next depth source...')
    return None


# ── Depth ingestion ─────────────────────────────────────────────────────────

def _num(v):
    """Numeric cell value, or None. Handles the CSV's strings and blank ' ' cells."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v.strip())
        except ValueError:
            return None
    return None


def load_depth_grid(path):
    """The depth table as a list of rows, from either source format.

    TfL serves FOI-0493 as a flat CSV; the ianvisits mirror is the original
    workbook, where the table lives on the 'Rail Levels' sheet. Layout is
    identical once loaded, so everything downstream is format-agnostic.
    """
    if path.endswith('.csv'):
        with open(path, encoding='utf-8-sig', newline='', errors='replace') as f:
            return list(csv.reader(f))
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        if 'Rail Levels' not in wb.sheetnames:
            raise ValueError("depth sheet 'Rail Levels' not found")
        return list(wb['Rail Levels'].iter_rows(values_only=True))
    finally:
        wb.close()


def parse_depths(path):
    """Yields (station_name, line_display, direction, depth_m, platform_asl_m).

    Column layout: row 0 holds line names positioned at the first of each
    line's two direction columns; row 1 holds the direction labels; col 0 is
    the station and col 1 its street elevation.

    IMPORTANT: there is a trailing 'Mean' direction column (col 23) with NO line
    header. Forward-filling the last seen line name would attribute that
    cross-line average to Waterloo & City, inventing depths for ~270 stations
    that line does not even serve. Each line header therefore owns exactly its
    own two columns and nothing else.
    """
    rows = load_depth_grid(path)
    if len(rows) < 3:
        raise ValueError(f'depth table has only {len(rows)} rows')

    line_row, dir_row = rows[0], rows[1]
    col_line = {}
    for i, v in enumerate(line_row):
        if i < 2 or not v or not str(v).strip():
            continue
        name = str(v).strip()
        if name.lower().startswith('height'):
            continue
        # Own this column and the next one only.
        for c in (i, i + 1):
            if c < len(dir_row) and dir_row[c] and str(dir_row[c]).strip():
                col_line[c] = (name, str(dir_row[c]).strip())

    for r in rows[2:]:
        if not r or not r[0] or not str(r[0]).strip() or is_note_row(r[0]):
            continue
        station = str(r[0]).strip()
        ground = _num(r[1]) if len(r) > 1 else None
        # Every note row in FOI-0493 fails this test, which is what actually
        # keeps prose out — is_note_row above is the backstop, not the filter.
        if ground is None:
            continue
        for c, (line_name, direction) in col_line.items():
            if c >= len(r):
                continue
            v = _num(r[c])
            if v is None:
                continue
            # The sheet's native quantity is the platform's altitude, on a
            # datum 100 m below Ordnance. Both are yielded: depth for display,
            # altitude for the barometric match.
            level_asl = v - TUNNEL_DATUM_OFFSET_M
            yield station, line_name, direction, ground - level_asl, level_asl


def ingest_depths(conn, path):
    index = build_naptan_index(conn)
    members = line_members(conn)
    # (stop_id, line_id) -> ([depths], [altitudes]) across directions
    acc = {}
    unmatched_names = set()
    unmatched_lines = set()
    seen_names = set()

    for station, line_name, _direction, depth, asl in parse_depths(path):
        seen_names.add(station)
        lid = line_id_of(line_name)
        if lid is None:
            unmatched_lines.add(line_name)
            continue
        # Resolved per line: "Edgware Road" is two different stations at two
        # very different depths, and only the line tells them apart.
        stop_id = resolve(index, station, lid, members)
        if not stop_id:
            unmatched_names.add(station)
            continue
        d, a = acc.setdefault((stop_id, lid), ([], []))
        d.append(depth)
        a.append(asl)

    rows = [(sid, lid, round(sum(d) / len(d), 2), round(sum(a) / len(a), 2),
             'tfl_foi')
            for (sid, lid), (d, a) in acc.items()]
    conn.executemany(
        'INSERT OR REPLACE INTO StationDepths'
        '(stop_id, line_id, depth_metres, platform_level_asl_m, source) '
        'VALUES (?,?,?,?,?)', rows)

    matched = len(seen_names) - len(unmatched_names)
    pct = 100.0 * matched / max(1, len(seen_names))
    print(f'  depths: {len(rows):,} (stop,line) pairs from '
          f'{matched}/{len(seen_names)} stations ({pct:.1f}%)')
    if unmatched_lines:
        print(f'  depths: unmapped line names: {sorted(unmatched_lines)}')
    if unmatched_names:
        print(f'  depths: unmatched stations ({len(unmatched_names)}): '
              f'{sorted(unmatched_names)}')
    return len(rows)


# FOI-0493's columns are per *line*, but its platforms are per *station box*.
# Where two lines share the same platforms, only the line that "owns" the track
# carries a value and the other column is blank — so a line can be missing
# depths at stations it demonstrably serves.
#
# Worst case is the Circle, which has no column at all (it owns no track of its
# own), leaving all 36 of its stations with no barometric prior whatsoever.
# The Hammersmith & City is missing 17 of 29 for the same reason, and the
# Piccadilly 9 of 53 across the surface stretches it shares with the District
# and Metropolitan.
#
# Donors are only listed where the two lines genuinely use the same platform
# face. Cross-checked by MAX_DONOR_SPREAD_M below, so a mistake here shows up
# as a skipped derivation rather than a wrong depth.
SHARED_PLATFORM_DONORS = {
    # The sub-surface family: one cut-and-cover box per station.
    'circle': ('district', 'hammersmith-city', 'metropolitan'),
    'hammersmith-city': ('circle', 'district', 'metropolitan'),
    'district': ('circle', 'hammersmith-city', 'metropolitan'),
    'metropolitan': ('circle', 'hammersmith-city', 'district', 'jubilee'),
    # Surface stretches only: the Uxbridge branch (shared with the
    # Metropolitan) and Ealing Common / Turnham Green (shared with the
    # District). Everywhere the Piccadilly is deep tube it already has its own
    # value, so nothing deep is ever borrowed.
    'piccadilly': ('district', 'metropolitan'),
}

# Donors must agree within this many metres before their mean is trusted.
# Disagreement means they are not actually the same platforms — the one case
# this must never do is lend a deep-tube depth to a sub-surface line.
MAX_DONOR_SPREAD_M = 3.0


def derive_shared_platform_depths(conn):
    """Fills depths for lines that share another line's platforms.

    Only fills gaps: a line's own FOI value always wins. Written with
    source='tfl_foi_shared_platform' rather than 'tfl_foi' so the distinction
    survives into the database and the engine can weight it.
    """
    members = line_members(conn)
    if not members:
        print('  depths: no topology — skipping shared-platform derivation.')
        return 0

    written = 0
    skipped_spread = []
    for line_id, donors in SHARED_PLATFORM_DONORS.items():
        stops = members.get(line_id)
        if not stops:
            continue
        rows = []
        for stop_id in sorted(stops):
            existing = conn.execute(
                'SELECT 1 FROM StationDepths WHERE stop_id=? AND line_id=?',
                (stop_id, line_id)).fetchone()
            if existing:
                continue
            placeholders = ','.join('?' * len(donors))
            donated = conn.execute(
                f'SELECT depth_metres, platform_level_asl_m FROM StationDepths '
                f'WHERE stop_id=? AND line_id IN ({placeholders})',
                (stop_id, *donors)).fetchall()
            vals = [d for d, _ in donated]
            if not vals:
                continue
            if max(vals) - min(vals) > MAX_DONOR_SPREAD_M:
                skipped_spread.append(
                    f'{stop_id}/{line_id} ({min(vals):.1f}..{max(vals):.1f} m)')
                continue
            asls = [a for _, a in donated if a is not None]
            rows.append((stop_id, line_id, round(sum(vals) / len(vals), 2),
                         round(sum(asls) / len(asls), 2) if asls else None,
                         'tfl_foi_shared_platform'))
        conn.executemany(
            'INSERT OR REPLACE INTO StationDepths'
            '(stop_id, line_id, depth_metres, platform_level_asl_m, source) '
            'VALUES (?,?,?,?,?)', rows)
        written += len(rows)
        if rows:
            print(f'  depths: derived {len(rows)} {line_id} station(s) from '
                  f'{"/".join(donors)}')
    if skipped_spread:
        print(f'  depths: {len(skipped_spread)} derivation(s) skipped, donors '
              f'disagree: {skipped_spread}')
    return written


# ── Run-time ingestion ──────────────────────────────────────────────────────

def parse_runtimes(path):
    """Yields (line_display, from_name, to_name, unimpeded_s, am_peak_s).

    Times in the sheet are DECIMAL MINUTES (2.2333 == 2 min 14 s), not
    minutes:seconds. Multiplying by 60 is correct; reading the fraction as
    seconds would be badly wrong.
    """
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    sheet = 'Runtime' if 'Runtime' in wb.sheetnames else wb.sheetnames[0]
    rows = list(wb[sheet].iter_rows(values_only=True))
    wb.close()

    header_idx = None
    for i, r in enumerate(rows[:10]):
        joined = ' '.join(str(c).lower() for c in r if c)
        if 'station from' in joined and 'running time' in joined:
            header_idx = i
            break
    if header_idx is None:
        raise ValueError('could not locate run-time header row')

    hdr = [str(c).lower() if c else '' for c in rows[header_idx]]

    def find(*fragments):
        for i, h in enumerate(hdr):
            if all(f in h for f in fragments):
                return i
        return None

    c_line = find('line')
    c_from = find('station from')
    c_to = find('station to')
    c_unimp = find('impeded', 'running time')
    c_am = find('am peak')

    if None in (c_line, c_from, c_to) or c_unimp is None:
        raise ValueError(f'unexpected run-time columns: {hdr[:8]}')

    for r in rows[header_idx + 1:]:
        if not r or len(r) <= max(c_to, c_unimp):
            continue
        if not r[c_from] or not r[c_to]:
            continue
        unimp = r[c_unimp]
        if not isinstance(unimp, (int, float)) or unimp <= 0:
            continue
        am = r[c_am] if c_am is not None and c_am < len(r) else None
        yield (r[c_line], str(r[c_from]).strip(), str(r[c_to]).strip(),
               int(round(float(unimp) * 60.0)),
               int(round(float(am) * 60.0)) if isinstance(am, (int, float)) and am > 0 else None)


def ingest_runtimes(conn, path):
    """Writes unimpeded and peak run times per adjacent leg.

    `seconds` stores the **unimpeded** time deliberately. That figure is the
    train actually moving with no holds — a physical floor — which is exactly
    what the timing gate needs to reject arrivals that are too early to be real.

    Taking max(unimpeded, peak) instead would inflate that floor: Oval →
    Kennington is 102 s unimpeded but 168 s at AM peak, and a 168 s prior would
    start rejecting legitimate fast off-peak runs. The peak value is kept in its
    own column so the engine can widen the *upper* bound without moving the
    lower one.
    """
    index = build_naptan_index(conn)
    members = line_members(conn)
    best = {}                       # (line, from, to) -> (unimpeded, peak)
    unmatched, unmapped_lines, total = set(), set(), 0

    for line_name, a, b, unimp_s, am_s in parse_runtimes(path):
        total += 1
        lid = line_id_of(line_name)
        if lid is None:
            if not is_known_unsupported_line(line_name):
                unmapped_lines.add(str(line_name).strip())
            continue
        # The sheet writes a bare "EDGWARE ROAD" under four different lines and
        # a bare "HAMMERSMITH" under Piccadilly. Resolving without the line
        # keyed those legs to a station the line does not serve, so the
        # topology join found nothing and the legs went uncovered.
        sa = resolve(index, a, lid, members)
        sb = resolve(index, b, lid, members)
        if not sa:
            unmatched.add(a)
        if not sb:
            unmatched.add(b)
        if not sa or not sb or sa == sb:
            continue
        key = (lid, sa, sb)
        peak = am_s or unimp_s
        prev = best.get(key)
        if prev is None:
            best[key] = (unimp_s, peak)
        else:
            # Branch-duplicated rows (e.g. "KENNINGTON (CITY)" vs "(CX)") collapse
            # to the same pair: keep the fastest floor and the slowest ceiling so
            # the resulting window covers every variant.
            best[key] = (min(prev[0], unimp_s), max(prev[1], peak))

    rows = [(lid, a, b, u, p, 'tfl_foi')
            for (lid, a, b), (u, p) in best.items()]
    conn.executemany(
        'INSERT OR REPLACE INTO RunTimes'
        '(line_id, from_stop, to_stop, seconds, peak_seconds, source) '
        'VALUES (?,?,?,?,?,?)', rows)
    print(f'  run times: {len(rows):,} legs written from {total:,} sheet rows')
    if unmapped_lines:
        print(f'  run times: unmapped line names: {sorted(unmapped_lines)}')
    if unmatched:
        print(f'  run times: unmatched stations ({len(unmatched)}): '
              f'{sorted(unmatched)}')
    return len(rows)


def fill_surface_platform_levels(conn):
    """Gives every remaining sequenced (stop, line) a platform altitude.

    This is the only prior the DLR, Elizabeth line, Overground and the Bakerloo
    north of Queen's Park ever get. FOI-0493 covers London Underground
    infrastructure only, and no open dataset publishes platform depths for the
    rest — they were searched for station by station and only a handful of
    mutually inconsistent figures exist in journalism.

    Those stations are overwhelmingly at grade, so their platform altitude is
    the ground altitude, which OS Terrain 50 gives for all of them. Depth is
    recorded as 0.0 and the source says so, which keeps the claim honest: this
    asserts "at surface level here", not "measured 0 m below the street".

    The genuinely sub-surface exceptions (the Elizabeth line core, the Thames
    Tunnel stations, Bank DLR, Cutty Sark) are therefore recorded as surface
    and will be wrong. That is deliberate and bounded — it is a missing depth,
    not an invented one, and the alternative is scattered unverifiable figures
    in a safety-relevant prior. `source` marks every one of these rows so they
    can be corrected in bulk if a real dataset ever appears.
    """
    try:
        conn.execute('SELECT 1 FROM Elevation LIMIT 1')
    except sqlite3.Error:
        print('  platform levels: no Elevation table — run fetch_elevation '
              'first. Surface lines will have no barometric prior.')
        return 0

    rows = conn.execute('''
        SELECT DISTINCT r.stop_id, r.line_id, e.ground_elev_m
        FROM RouteSequences r
        JOIN Elevation e ON e.stop_id = r.stop_id
        WHERE NOT EXISTS (SELECT 1 FROM StationDepths d
                          WHERE d.stop_id = r.stop_id AND d.line_id = r.line_id)
    ''').fetchall()
    conn.executemany(
        'INSERT OR REPLACE INTO StationDepths'
        '(stop_id, line_id, depth_metres, platform_level_asl_m, source) '
        'VALUES (?,?,0.0,?,?)',
        [(sid, lid, elev, 'os_terrain_50_surface') for sid, lid, elev in rows])

    # Underground stations whose depth came from FOI already have an altitude;
    # this backfills any that somehow lack one.
    conn.execute('''
        UPDATE StationDepths
           SET platform_level_asl_m =
               (SELECT e.ground_elev_m - StationDepths.depth_metres
                  FROM Elevation e WHERE e.stop_id = StationDepths.stop_id)
         WHERE platform_level_asl_m IS NULL
           AND EXISTS (SELECT 1 FROM Elevation e
                        WHERE e.stop_id = StationDepths.stop_id)
    ''')
    print(f'  platform levels: {len(rows):,} surface (stop,line) pairs from '
          f'OS Terrain 50')
    return len(rows)


# ── Validation ──────────────────────────────────────────────────────────────

# Independently published values used to prove the datum correction is applied.
KNOWN_DEPTHS = [
    ('Hampstead', 'northern', 58.5, 1.5),
    ('Greenford', 'central', -10.2, 1.5),
    ('Acton Town', 'district', 5.5, 1.5),
    ('Tooting Broadway', 'northern', 12.8, 1.5),
]


def verify_known_depths(conn):
    """Fails loudly if the tunnel-datum correction was not applied.

    Without the -100 m offset Hampstead would read ~-49 m instead of 58.5 m, so
    this catches the single most consequential mistake in the whole ingest.
    """
    index = build_naptan_index(conn)
    members = line_members(conn)
    problems = []
    for name, lid, expected, tol in KNOWN_DEPTHS:
        stop_id = resolve(index, name, lid, members)
        if not stop_id:
            problems.append(f'{name}: not resolvable to a NaPTAN id')
            continue
        row = conn.execute(
            'SELECT depth_metres FROM StationDepths WHERE stop_id=? AND line_id=?',
            (stop_id, lid)).fetchone()
        if row is None:
            problems.append(f'{name} ({lid}): no depth ingested')
            continue
        got = row[0]
        if abs(got - expected) > tol:
            problems.append(
                f'{name} ({lid}): got {got:.1f} m, expected ~{expected} m '
                f'(±{tol}) — is the {TUNNEL_DATUM_OFFSET_M:.0f} m tunnel-datum '
                f'correction applied?')
    if problems:
        print('  DEPTH VALIDATION FAILED:')
        for p in problems:
            print(f'    - {p}')
        return False
    print(f'  depth validation: all {len(KNOWN_DEPTHS)} known values within '
          f'tolerance')
    return True


# Stations whose name is shared by two physically separate sets of platforms.
# Both must exist with their own depth, and the two must stay far apart — that
# is the whole point of resolving per line.
# Ids are NaPTAN ATCOCodes as stored in StopPoints ('9400ZZ...'), NOT the
# '940GZZ...' form the TfL API publishes — see _naptan_alias in build_naptan_db.
DISTINCT_PLATFORMS = [
    # (naptan id, line, naptan id, line, minimum metres apart)
    ('9400ZZLUERB', 'bakerloo', '9400ZZLUERC', 'district', 15.0),
]


def verify_distinct_platforms(conn):
    """Fails if two co-named stations collapsed onto one depth.

    Edgware Road (Bakerloo) is a 24.9 m deep-tube platform; Edgware Road
    (Circle) is 5.2 m sub-surface, 150 m up the road. Resolving both to one
    stop put a deep-tube depth on a sub-surface platform — an error wider than
    the engine's whole depth tolerance, and invisible in the summary counts
    because the row count stays the same.
    """
    problems = []
    for id_a, line_a, id_b, line_b, min_gap in DISTINCT_PLATFORMS:
        rows = {}
        for sid, lid in ((id_a, line_a), (id_b, line_b)):
            row = conn.execute(
                'SELECT depth_metres FROM StationDepths '
                'WHERE stop_id=? AND line_id=?', (sid, lid)).fetchone()
            if row is None:
                problems.append(f'{sid} ({lid}): no depth ingested')
            else:
                rows[sid] = row[0]
        if len(rows) == 2:
            gap = abs(rows[id_a] - rows[id_b])
            if gap < min_gap:
                problems.append(
                    f'{id_a} ({rows[id_a]:.1f} m) and {id_b} '
                    f'({rows[id_b]:.1f} m) are only {gap:.1f} m apart, '
                    f'expected >{min_gap:.0f} m — did both names resolve to '
                    f'the same station?')
    if problems:
        print('  PLATFORM VALIDATION FAILED:')
        for p in problems:
            print(f'    - {p}')
        return False
    print(f'  platform validation: {len(DISTINCT_PLATFORMS)} co-named station '
          f'pair(s) kept distinct')
    return True


# Platform altitudes that are independently checkable. Hampstead's platforms
# are the highest on the network *in altitude* despite being the deepest below
# street — which is exactly the distinction this column exists to capture, and
# the one the old depth-only model could not express.
KNOWN_PLATFORM_LEVELS = [
    ('Hampstead', 'northern', 49.4, 2.0),      # street 108 m, 58.6 m down
    ('Waterloo', 'jubilee', -26.0, 2.0),       # TfL's published -26 m ASL
    ('Tooting Broadway', 'northern', 3.2, 2.0),
]


def verify_platform_levels(conn):
    """Checks platform altitudes, and that the descent model is consistent.

    The second half matters more than the first. It recomputes the expected
    barometric descent for a known pair and asserts it against the altitude
    difference, which is the invariant the engine now relies on. Depth alone
    cannot satisfy it: Tooting Broadway to Euston is a 21.8 m error under the
    old model and ~0 m under this one.
    """
    index = build_naptan_index(conn)
    members = line_members(conn)
    problems = []
    for name, lid, expected, tol in KNOWN_PLATFORM_LEVELS:
        stop_id = resolve(index, name, lid, members)
        if not stop_id:
            problems.append(f'{name}: not resolvable')
            continue
        row = conn.execute(
            'SELECT platform_level_asl_m FROM StationDepths '
            'WHERE stop_id=? AND line_id=?', (stop_id, lid)).fetchone()
        if row is None or row[0] is None:
            problems.append(f'{name} ({lid}): no platform altitude')
            continue
        if abs(row[0] - expected) > tol:
            problems.append(f'{name} ({lid}): altitude {row[0]:.1f} m, '
                            f'expected ~{expected} m (+/-{tol})')

    missing = conn.execute(
        'SELECT COUNT(*) FROM StationDepths '
        'WHERE platform_level_asl_m IS NULL').fetchone()[0]
    if missing:
        problems.append(f'{missing} depth row(s) have no platform altitude — '
                        'the barometric match cannot use them')

    if problems:
        print('  PLATFORM LEVEL VALIDATION FAILED:')
        for p in problems:
            print(f'    - {p}')
        return False
    print(f'  platform levels: {len(KNOWN_PLATFORM_LEVELS)} known altitudes '
          f'within tolerance, none missing')
    return True


def report_coverage(conn):
    """How much of the topology actually has priors."""
    seq = conn.execute('SELECT COUNT(*) FROM RouteSequences').fetchone()[0]
    if seq == 0:
        print('  coverage: RouteSequences empty — run build_naptan_db.py '
              '--with-topology first, then re-run this.')
        return
    legs = conn.execute('''
        SELECT COUNT(*) FROM (
          SELECT a.line_id, a.stop_id AS f, b.stop_id AS t
          FROM RouteSequences a JOIN RouteSequences b
            ON a.line_id=b.line_id AND a.direction=b.direction
           AND a.branch_id=b.branch_id AND b.seq_index=a.seq_index+1
          GROUP BY a.line_id, a.stop_id, b.stop_id)
    ''').fetchone()[0]
    # Split by source. Counting any RunTimes row as "covered" reports 100%
    # even when a third of the legs are still the geometric estimates written
    # during topology ingest — and it is precisely those legs where the timing
    # gate has no real floor to reject a mid-tunnel hold against.
    measured = conn.execute('''
        SELECT COUNT(*) FROM (
          SELECT a.line_id, a.stop_id AS f, b.stop_id AS t
          FROM RouteSequences a JOIN RouteSequences b
            ON a.line_id=b.line_id AND a.direction=b.direction
           AND a.branch_id=b.branch_id AND b.seq_index=a.seq_index+1
          GROUP BY a.line_id, a.stop_id, b.stop_id)
        WHERE EXISTS (SELECT 1 FROM RunTimes r
                      WHERE r.line_id=line_id AND r.from_stop=f AND r.to_stop=t
                        AND r.source <> 'estimate')
    ''').fetchone()[0]
    stops = conn.execute(
        'SELECT COUNT(DISTINCT stop_id) FROM RouteSequences').fetchone()[0]
    with_depth = conn.execute(
        'SELECT COUNT(DISTINCT stop_id) FROM StationDepths').fetchone()[0]
    print(f'  coverage: run times {measured}/{legs} adjacent legs from real '
          f'TfL data ({100.0*measured/max(1,legs):.0f}%); the remaining '
          f'{legs - measured} use geometric estimates')
    print(f'  coverage: depths {with_depth}/{stops} sequenced stations '
          f'({100.0*with_depth/max(1,stops):.0f}%)')

    # Per-line depth coverage. The aggregate above hides the cases that matter:
    # a line at 0% has no barometric prior anywhere on it, which is invisible
    # at runtime because the engine just quietly drops to two conditions.
    gaps = conn.execute('''
        SELECT s.line_id,
               COUNT(DISTINCT s.stop_id) AS stops,
               COUNT(DISTINCT d.stop_id) AS with_depth
        FROM RouteSequences s
        LEFT JOIN StationDepths d
               ON d.stop_id = s.stop_id AND d.line_id = s.line_id
        GROUP BY s.line_id
        HAVING with_depth < stops
        ORDER BY (1.0 * with_depth / stops), s.line_id
    ''').fetchall()
    for line_id, n, have in gaps:
        print(f'  coverage: depths {line_id:<18} {have}/{n} '
              f'({100.0*have/max(1,n):.0f}%)')


# ── Entry point ─────────────────────────────────────────────────────────────

def ingest(conn, keep_files=False):
    print('Ingesting TfL reference data...')
    if not line_members(conn):
        print('  WARN: RouteSequences is empty. Ambiguous station names '
              '(Edgware Road, Hammersmith) cannot be resolved per line and '
              'Circle depths cannot be derived. Run --with-topology first.')

    depth_file = download_first_available(DEPTH_SOURCES)
    ok_rt = download(RUNTIMES_URL, RUNTIMES_FILE)

    if ok_rt:
        try:
            ingest_runtimes(conn, RUNTIMES_FILE)
        except Exception as e:
            print(f'  WARN: run-time ingest failed ({type(e).__name__}: {e})')
    if depth_file:
        try:
            ingest_depths(conn, depth_file)
            derive_shared_platform_depths(conn)
            fill_surface_platform_levels(conn)
            conn.commit()
            verify_known_depths(conn)
            verify_distinct_platforms(conn)
            verify_platform_levels(conn)
        except Exception as e:
            print(f'  WARN: depth ingest failed ({type(e).__name__}: {e})')
    conn.commit()
    report_coverage(conn)

    if not keep_files:
        for f in [dest for _, dest in DEPTH_SOURCES] + [RUNTIMES_FILE]:
            if os.path.exists(f):
                os.remove(f)


def main():
    # Windows consoles default to cp1252 and cannot encode the
    # em-dashes in this script's output. See build_naptan_db.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--db', required=True, help='SQLite database to populate')
    ap.add_argument('--keep-files', action='store_true',
                    help='keep downloaded spreadsheets for inspection')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit(f'FATAL: {args.db} does not exist')
    conn = sqlite3.connect(args.db)
    try:
        ingest(conn, keep_files=args.keep_files)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
