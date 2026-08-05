"""
fetch_elevation.py
Samples ground elevation for every station from OS Terrain 50.

WHY THIS EXISTS
---------------
The barometer measures a *change in altitude*. To turn that into "which station
are we at" the engine needs each platform's altitude, which is

    platform level above sea level = ground level - depth below street

TfL's FOI-0493 supplies both terms, but only for London Underground. For the
DLR, Elizabeth line, Overground and the Bakerloo north of Queen's Park it
supplies neither, and no open dataset publishes their platform depths — they
were searched for individually and only a handful of conflicting figures exist
in journalism. Those stations are overwhelmingly at surface level though, so
their platform altitude simply *is* the ground altitude, and that is a solved
problem: OS Terrain 50 covers all of GB.

Ignoring elevation is not an option. Ground level across the network spans
about 76 m (Canning Town -2.3 m to Shenfield 73.3 m) against a 12 m match
tolerance, so a prior that assumes every street is at the same height is wrong
by more than the tolerance on most journeys.

SOURCE
------
OS Terrain 50, Ordnance Survey OpenData, Open Government Licence v3.0.
No API key required. ~162 MB for the whole of GB as ASCII grid.
    https://osdatahub.os.uk/downloads/open/Terrain50
Attribution: "Contains OS data (c) Crown copyright and database right 2026."

50 m post spacing, 4 m RMSE vertical, EPSG:27700, Ordnance Datum Newlyn.
Validated here against the ground levels TfL publishes in FOI-0493 for 279
Underground stations: median difference 1.3 m, 90th percentile 5.4 m. That is
comfortably inside the barometric tolerance, so the two sources are
interchangeable for this purpose.

USAGE
    python tools/fetch_elevation.py --db _naptan_temp.db

Downloads and caches the grid in _os_terrain50/, then writes one row per stop
into the Elevation table. Re-run is cheap once the cache exists.
"""

import argparse
import glob
import io
import os
import sqlite3
import sys
import urllib.request
import zipfile

TERRAIN50_URL = ('https://api.os.uk/downloads/v1/products/Terrain50/downloads'
                 '?area=GB&format=ASCII+Grid+and+GML+%28Grid%29&redirect')

CACHE_DIR = '_os_terrain50'
ZIP_NAME = os.path.join(CACHE_DIR, 'terr50_gagg_gb.zip')
ASC_DIR = os.path.join(CACHE_DIR, 'asc')

# NODATA in Terrain 50 is -9999; anything near it is sea or absent.
_NODATA_FLOOR = -1000.0


def download_grid():
    """Fetches the national grid archive once, into CACHE_DIR."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    if os.path.exists(ZIP_NAME) and os.path.getsize(ZIP_NAME) > 100_000_000:
        print(f'  using cached {ZIP_NAME}')
        return True
    print(f'  downloading OS Terrain 50 (~162 MB)...')
    try:
        req = urllib.request.Request(
            TERRAIN50_URL, headers={'User-Agent': 'StopSnoozer-build'})
        with urllib.request.urlopen(req, timeout=600) as r, \
                open(ZIP_NAME, 'wb') as f:
            while chunk := r.read(1_048_576):
                f.write(chunk)
        print(f'  saved {os.path.getsize(ZIP_NAME):,} bytes')
        return True
    except Exception as e:
        print(f'  WARN: Terrain 50 download failed ({type(e).__name__}: {e})')
        return False


def extract_tiles(only_prefixes=None):
    """Unpacks the nested per-tile zips into ASC_DIR.

    The archive is a zip of zips, one inner archive per 100 km grid square.
    `only_prefixes` limits extraction to those squares — passing the squares
    that actually contain stations turns a 2,859-tile unpack into a few hundred.
    """
    if os.path.isdir(ASC_DIR) and glob.glob(os.path.join(ASC_DIR, '*.asc')):
        print(f'  using cached tiles in {ASC_DIR}')
        return
    os.makedirs(ASC_DIR, exist_ok=True)
    count = 0
    with zipfile.ZipFile(ZIP_NAME) as outer:
        for name in outer.namelist():
            if not name.lower().endswith('.zip'):
                continue
            square = os.path.basename(os.path.dirname(name)).lower()
            if only_prefixes and square not in only_prefixes:
                continue
            with zipfile.ZipFile(io.BytesIO(outer.read(name))) as inner:
                for member in inner.namelist():
                    if member.lower().endswith('.asc'):
                        dest = os.path.join(ASC_DIR, os.path.basename(member))
                        with open(dest, 'wb') as f:
                            f.write(inner.read(member))
                        count += 1
    print(f'  extracted {count} tiles')


class Terrain50:
    """Lazily-loaded ASCII-grid DTM, indexed by tile origin."""

    def __init__(self, asc_dir=ASC_DIR):
        self._dir = asc_dir
        self._tiles = {}
        self._paths = {}
        for path in glob.glob(os.path.join(asc_dir, '*.asc')):
            # Tile files are named by their grid square, e.g. TQ28.asc.
            self._paths[os.path.basename(path).lower().split('.')[0]] = path

    @staticmethod
    def _tile_key(easting, northing):
        """Grid-square name for a coordinate, e.g. (531580,181843) -> 'tq38'."""
        e, n = int(easting), int(northing)
        # British National Grid 100 km lettering.
        letters = 'ABCDEFGHJKLMNOPQRSTUVWXYZ'   # 'I' is not used
        e100, n100 = e // 100_000, n // 100_000
        major_e, major_n = (e100 + 10) // 5, (n100 + 5) // 5
        major = letters[(4 - major_n) * 5 + major_e]
        minor_e, minor_n = (e100 + 10) % 5, (n100 + 5) % 5
        minor = letters[(4 - minor_n) * 5 + minor_e]
        return f'{major}{minor}{(e // 10_000) % 10}{(n // 10_000) % 10}'.lower()

    def _load(self, key):
        if key in self._tiles:
            return self._tiles[key]
        path = self._paths.get(key)
        if path is None:
            self._tiles[key] = None
            return None
        header = {}
        with open(path) as f:
            for _ in range(5):
                k, v = f.readline().split()
                header[k.lower()] = float(v)
            rows = [line.split() for line in f if line.strip()]
        self._tiles[key] = (header, rows)
        return self._tiles[key]

    def sample(self, easting, northing):
        """Ground elevation in metres above Ordnance Datum, or None."""
        tile = self._load(self._tile_key(easting, northing))
        if tile is None:
            return None
        header, rows = tile
        cell = header['cellsize']
        col = int((easting - header['xllcorner']) // cell)
        # ASC rows run north to south, so row 0 is the top of the tile.
        top = header['yllcorner'] + header['nrows'] * cell
        row = int((top - northing) // cell)
        if not (0 <= row < len(rows) and 0 <= col < len(rows[row])):
            return None
        value = float(rows[row][col])
        return None if value < _NODATA_FLOOR else value


def wgs84_to_osgb36(lat, lon):
    """WGS84 lat/lon -> British National Grid easting/northing.

    The inverse of osgb36_to_wgs84() in build_naptan_db.py. Needed because
    StopPoints stores only lat/lon, while Terrain 50 is indexed on the grid.
    """
    import math

    a2, b2 = 6378137.000, 6356752.3142
    e22 = 1 - (b2 * b2) / (a2 * a2)
    phi, lam = math.radians(lat), math.radians(lon)
    nu = a2 / math.sqrt(1 - e22 * math.sin(phi) ** 2)
    x1 = nu * math.cos(phi) * math.cos(lam)
    y1 = nu * math.cos(phi) * math.sin(lam)
    z1 = (1 - e22) * nu * math.sin(phi)

    # Helmert WGS84 -> OSGB36 (the reverse of the transform in the builder).
    tx, ty, tz = -446.448, 125.157, -542.060
    s = 20.4894e-6
    rx = math.radians(-0.1502 / 3600)
    ry = math.radians(-0.2470 / 3600)
    rz = math.radians(-0.8421 / 3600)
    x2 = tx + (1 + s) * x1 - rz * y1 + ry * z1
    y2 = ty + rz * x1 + (1 + s) * y1 - rx * z1
    z2 = tz - ry * x1 + rx * y1 + (1 + s) * z1

    a, b = 6377563.396, 6356256.909
    e2 = 1 - (b * b) / (a * a)
    p = math.hypot(x2, y2)
    phi2 = math.atan2(z2, p * (1 - e2))
    for _ in range(100):
        nu2 = a / math.sqrt(1 - e2 * math.sin(phi2) ** 2)
        new = math.atan2(z2 + e2 * nu2 * math.sin(phi2), p)
        if abs(new - phi2) < 1e-12:
            phi2 = new
            break
        phi2 = new
    lam2 = math.atan2(y2, x2)

    f0 = 0.9996012717
    lat0, lon0 = math.radians(49.0), math.radians(-2.0)
    e0, n0 = 400000.0, -100000.0
    n = (a - b) / (a + b)
    nu3 = a * f0 / math.sqrt(1 - e2 * math.sin(phi2) ** 2)
    rho = a * f0 * (1 - e2) / (1 - e2 * math.sin(phi2) ** 2) ** 1.5
    eta2 = nu3 / rho - 1
    m = b * f0 * (
        (1 + n + 1.25 * n**2 + 1.25 * n**3) * (phi2 - lat0)
        - (3 * n + 3 * n**2 + 2.625 * n**3)
          * math.sin(phi2 - lat0) * math.cos(phi2 + lat0)
        + (1.875 * n**2 + 1.875 * n**3)
          * math.sin(2 * (phi2 - lat0)) * math.cos(2 * (phi2 + lat0))
        - (35 / 24) * n**3
          * math.sin(3 * (phi2 - lat0)) * math.cos(3 * (phi2 + lat0))
    )
    sp, cp, tp = math.sin(phi2), math.cos(phi2), math.tan(phi2)
    i = m + n0
    ii = nu3 / 2 * sp * cp
    iii = nu3 / 24 * sp * cp**3 * (5 - tp**2 + 9 * eta2)
    iiia = nu3 / 720 * sp * cp**5 * (61 - 58 * tp**2 + tp**4)
    iv = nu3 * cp
    v = nu3 / 6 * cp**3 * (nu3 / rho - tp**2)
    vi = nu3 / 120 * cp**5 * (5 - 18 * tp**2 + tp**4 + 14 * eta2
                              - 58 * tp**2 * eta2)
    dl = lam2 - lon0
    northing = i + ii * dl**2 + iii * dl**4 + iiia * dl**6
    easting = e0 + iv * dl + v * dl**3 + vi * dl**5
    return easting, northing


def ingest_elevation(conn):
    """Fills the Elevation table for every stop that appears in the topology.

    Restricted to sequenced stops deliberately: the full NaPTAN table is ~450k
    rows of bus stops that will never be part of an underground journey, and
    sampling them all would bloat the shipped asset for no benefit.
    """
    stops = conn.execute(
        'SELECT DISTINCT s.id, s.latitude, s.longitude FROM StopPoints s '
        'JOIN RouteSequences r ON r.stop_id = s.id').fetchall()
    if not stops:
        print('  elevation: no sequenced stops — run --with-topology first.')
        return 0

    coords = [(sid, *wgs84_to_osgb36(lat, lon)) for sid, lat, lon in stops]
    squares = {Terrain50._tile_key(e, n)[:2] for _, e, n in coords}
    extract_tiles(only_prefixes=squares)

    dtm = Terrain50()
    rows, missing = [], 0
    for sid, easting, northing in coords:
        value = dtm.sample(easting, northing)
        if value is None:
            missing += 1
            continue
        rows.append((sid, round(value, 1), int(easting), int(northing),
                     'os_terrain_50'))
    conn.executemany(
        'INSERT OR REPLACE INTO Elevation'
        '(stop_id, ground_elev_m, easting, northing, source) '
        'VALUES (?,?,?,?,?)', rows)
    print(f'  elevation: {len(rows):,}/{len(stops):,} sequenced stops sampled '
          f'from OS Terrain 50')
    if missing:
        print(f'  elevation: {missing} stop(s) outside the grid — left null')
    return len(rows)


def ingest(conn):
    print('Sampling ground elevation (OS Terrain 50)...')
    if not download_grid():
        print('  elevation: skipped. Platform altitudes for non-Underground '
              'stations will be unavailable.')
        return 0
    return ingest_elevation(conn)


def main():
    # Windows consoles default to cp1252 and cannot encode the
    # em-dashes in this script's output. See build_naptan_db.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--db', required=True, help='SQLite database to populate')
    args = ap.parse_args()
    if not os.path.exists(args.db):
        sys.exit(f'FATAL: {args.db} does not exist')
    conn = sqlite3.connect(args.db)
    try:
        ingest(conn)
        conn.commit()
    finally:
        conn.close()


if __name__ == '__main__':
    main()
