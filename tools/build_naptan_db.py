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

# ── Config ─────────────────────────────────────────────────────────────────────

API_URL  = 'https://naptan.api.dft.gov.uk/v1/access-nodes?dataFormat=csv'
CSV_TEMP = '_naptan_temp.csv'
DB_TEMP  = '_naptan_temp.db'
GZ_OUT   = os.path.join('assets', 'uk.db.gz')

# NaPTAN StopType → fallback transit_type when not overridden by ATCOCode
_TYPE_MAP = {
    # National Rail / Elizabeth Line / Overground
    'RLY': 'train',
    'RPL': 'train',
    # Ferry
    'FER': 'ferry',
    'FTD': 'ferry',
    # Everything else (BCE, BCT, BCS, BCP, LCE, LBL, etc.) → bus
}

# StopType values to skip entirely — they duplicate MET station-level records:
#   PLT = individual platform (creates N duplicates per station)
#   TMU = Tram/Metro/Underground area reference (e.g., 4900ZZLUTBY1)
_SKIP_STOP_TYPES = {'PLT', 'TMU'}


def _classify(atco: str, stop_type: str) -> tuple[str, str | None]:
    """Return (transit_type, wifi_ssid) for a stop, or raise ValueError to skip."""

    # National Rail (910* ATCOCode or RLY/RPL type)
    if stop_type in ('RLY', 'RPL') or atco.startswith('910'):
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


def build_db(csv_path: str, db_path: str) -> tuple[int, int]:
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    # page_size must be set before any writes on a new database
    conn.execute('PRAGMA page_size = 16384;')
    # user_version = 2: Flutter checks this to decide whether to re-extract the asset
    conn.execute('PRAGMA user_version = 2;')
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

    inserted = 0
    skipped  = 0
    batch    = []

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

            if not atco or not name or not lat_str or not lon_str:
                skipped += 1
                continue

            try:
                lat = float(lat_str)
                lon = float(lon_str)
            except ValueError:
                skipped += 1
                continue

            # Skip platform and area-reference records (they duplicate MET station entries)
            if stop_type in _SKIP_STOP_TYPES:
                skipped += 1
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

    print(f'\r  {inserted:,} rows inserted, {skipped:,} skipped.   ')
    print('  Building index...')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_stop_name ON StopPoints(name);')
    conn.commit()
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
    try:
        download(API_URL, CSV_TEMP)
        build_db(CSV_TEMP, DB_TEMP)
        compress(DB_TEMP, GZ_OUT)
    finally:
        for f in (CSV_TEMP, DB_TEMP):
            if os.path.exists(f):
                os.remove(f)

    print(f'\nDone!  {GZ_OUT} is ready to bundle.')
    print('Add this to pubspec.yaml under flutter > assets:')
    print('    - assets/uk.db.gz')


if __name__ == '__main__':
    main()
