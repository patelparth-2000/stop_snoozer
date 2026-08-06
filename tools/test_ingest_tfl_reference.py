"""
Tests for ingest_tfl_reference.py.

Focus is on the two things that would silently corrupt calibration data:

  1. The 100 m tunnel-datum correction. Omit it and Hampstead reads -49 m
     instead of 58.5 m — every depth in the database wrong by 100 m, with
     nothing in the app to notice.

  2. Station-name matching. An unmatched name is not an error anywhere; it is
     just a missing prior, so the timing gate quietly runs without a floor on
     that leg. Match rate has to be asserted, not eyeballed.

Run:  python tools/test_ingest_tfl_reference.py
"""

import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ingest_tfl_reference as ing  # noqa: E402


class TestNormalisation(unittest.TestCase):

    def test_apostrophe_variants_both_indexed(self):
        """Sources disagree on possessives, so both forms must be produced.

        NaPTAN "Earl's Court" vs FOI "EARLS COURT" needs 's -> s.
        NaPTAN "St. James's Park" vs FOI "ST JAMES PARK" needs 's -> ''.
        A single rule cannot satisfy both.
        """
        earls = ing.normalise_variants("Earl's Court Underground Station")
        self.assertIn('earls court', earls)
        self.assertIn('earl court', earls)

        james = ing.normalise_variants("St. James's Park Underground Station")
        self.assertIn('st james park', james)

    def test_line_qualifiers_stripped(self):
        for name in ('Hammersmith (H&C Line) Underground Station',
                     'Hammersmith (Dist&Picc Line) Underground Station',
                     'PADDINGTON (Dis)',
                     'BAKER STREET (MET)'):
            keys = ing.normalise_variants(name)
            self.assertTrue(
                any('line' not in k for k in keys),
                f'qualifier survived normalisation for {name!r}: {keys}')

    def test_branch_suffixes_collapse_to_base_station(self):
        for name in ('Kennington Charing X Branch', 'KENNINGTON (CITY)',
                     'Camden Town City Branch'):
            keys = ing.normalise_variants(name)
            self.assertTrue(any(k.startswith(('kennington', 'camden'))
                                for k in keys), keys)

    def test_note_rows_rejected(self):
        # Every note row that actually appears in FOI-0493.
        notes = [
            'Notes',
            'Levels are referred to London Underground Datum',
            'London Underground Datum is 100m below Ordnance Datum Newlyn',
            'Railway track  in station platforms is ideally level but small '
            'gradients do occur',
            'The level value given is an approximation of the level throughout '
            'the platform',
            'Small variations to rail levels do occur due to settlement, rail '
            'wear, and track maintenance',
            'The Ground Level Outside Station, is indicative and is the height '
            'above Ordnance Datum',
        ]
        for n in notes:
            self.assertTrue(ing.is_note_row(n), f'should be a note: {n!r}')

    def test_real_stations_not_rejected_as_notes(self):
        for s in ('Hampstead', 'Tooting Broadway', "Earl's Court",
                  'Heathrow Terminal 4', 'Kennington'):
            self.assertFalse(ing.is_note_row(s), f'should be a station: {s!r}')

    def test_long_station_names_survive_the_note_filter(self):
        """The three FOI-0493 rows a 6-word cutoff silently threw away.

        Each carries real depth data — Edgware Road (Circle) four columns of
        it — so rejecting them lost the station entirely, with no warning
        anywhere because an unmatched station is indistinguishable from a
        station the sheet does not cover.
        """
        for s in ('Edgware Road (Circle, District, H & C)',
                  'Heathrow Airport Terminal 1, 2 & 3',
                  "Shepherd's Bush Market (Hammersmith & City)"):
            self.assertFalse(ing.is_note_row(s), f'should be a station: {s!r}')

    def test_comma_separated_qualifier_stripped(self):
        """"(Circle, District, H & C)" must normalise to the bare station."""
        self.assertIn('edgware road',
                      ing.normalise_variants('Edgware Road (Circle, District, H & C)'))
        self.assertIn('edgware road',
                      ing.normalise_variants('Edgware Road (Circle Line) Underground Station'))

    def test_heathrow_central_aliases_converge(self):
        """Three sources spell the same station three ways."""
        for name in ('Heathrow Airport Terminal 1, 2 & 3',
                     'HEATHROW 123',
                     'Heathrow Terminals 2 & 3 Underground Station'):
            self.assertIn('heathrow terminals 2 and 3',
                          ing.normalise_variants(name), name)

    def test_line_id_mapping(self):
        self.assertEqual(ing.line_id_of('Northern '), 'northern')
        self.assertEqual(ing.line_id_of('H & C'), 'hammersmith-city')
        # TfL's own FOI-0493 CSV misspells this column header. Unmapped, the
        # whole Metropolitan line's depths vanish behind one log line.
        self.assertEqual(ing.line_id_of('Metropoliton'), 'metropolitan')
        self.assertEqual(ing.line_id_of('Metropolitan'), 'metropolitan')
        self.assertEqual(ing.line_id_of('Hammersmith & City'), 'hammersmith-city')
        self.assertEqual(ing.line_id_of('Waterloo & City'), 'waterloo-city')
        # Defunct line: mapped to None deliberately, and flagged as *known*
        # unsupported so it is skipped silently rather than warned about.
        self.assertIsNone(ing.line_id_of('East London'))
        self.assertTrue(ing.is_known_unsupported_line('East London'))
        # Genuinely unknown names must NOT be treated as known-unsupported,
        # otherwise a future TfL rename would vanish without a warning.
        self.assertFalse(ing.is_known_unsupported_line('Bakerloo Express'))


class TestDatumCorrection(unittest.TestCase):
    """The correction itself, independent of any spreadsheet."""

    @staticmethod
    def depth(published_level, ground_level):
        return ground_level - (published_level - ing.TUNNEL_DATUM_OFFSET_M)

    def test_hampstead_deepest_station(self):
        # Published 49.1/49.9 at ground 108 -> ~58.5 m, the documented deepest
        # point on the network.
        self.assertAlmostEqual(self.depth(149.1, 108), 58.9, places=1)
        self.assertAlmostEqual(self.depth(149.9, 108), 58.1, places=1)

    def test_above_ground_station_is_negative(self):
        # Greenford is elevated; depth below street must come out negative.
        self.assertAlmostEqual(self.depth(132.2, 22), -10.2, places=1)

    def test_sub_surface_line_is_shallow(self):
        # Acton Town, District line — sub-surface lines sit ~5-9 m down.
        self.assertAlmostEqual(self.depth(115.5, 21), 5.5, places=1)

    def test_omitting_correction_is_catastrophically_wrong(self):
        """Guards the specific mistake the correction exists to prevent."""
        wrong = 108 - 149.1              # forgot the -100 offset
        right = self.depth(149.1, 108)
        self.assertAlmostEqual(wrong, -41.1, places=1)
        self.assertGreater(abs(right - wrong), 99.0)


class TestNaptanIndex(unittest.TestCase):

    def setUp(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.execute(
            'CREATE TABLE StopPoints (id TEXT PRIMARY KEY, name TEXT, '
            'transit_type TEXT, latitude REAL, longitude REAL, '
            'wifi_ssid TEXT, indicator TEXT)')
        rows = [
            ('9400ZZLUHDN', 'Hampstead Underground Station', 'underground'),
            ('9400ZZLUECT', "Earl's Court Underground Station", 'underground'),
            ('9400ZZLUSJP', "St. James's Park Underground Station", 'underground'),
            ('9400ZZLUHSC', 'Hammersmith (H&C Line) Underground Station', 'underground'),
            ('9400ZZLUWWL', 'Walthamstow Central Underground Station', 'underground'),
            ('9100SHRDHST', 'Shoreditch High Street Rail Station', 'train'),
        ]
        for sid, nm, tt in rows:
            self.conn.execute(
                'INSERT INTO StopPoints VALUES (?,?,?,0,0,NULL,NULL)',
                (sid, nm, tt))
        self.index = ing.build_naptan_index(self.conn)

    def tearDown(self):
        self.conn.close()

    def test_resolves_foi_spellings(self):
        cases = {
            'Hampstead': '9400ZZLUHDN',
            'EARLS COURT': '9400ZZLUECT',
            'ST JAMES PARK': '9400ZZLUSJP',
            'HAMMERSMITH (H&C)': '9400ZZLUHSC',
            'WALTHAMSTOW': '9400ZZLUWWL',
        }
        for name, expected in cases.items():
            self.assertEqual(ing.resolve(self.index, name), expected,
                             f'failed to resolve {name!r}')

    def test_unknown_station_returns_none(self):
        self.assertIsNone(ing.resolve(self.index, 'Nonexistent Parkway'))

    def test_underground_preferred_over_rail(self):
        """Rail is only a fallback; a tube station must win a name collision."""
        self.conn.execute(
            "INSERT INTO StopPoints VALUES "
            "('9100HMRSMTH','Hammersmith (H&C Line) Rail Station','train',0,0,NULL,NULL)")
        idx = ing.build_naptan_index(self.conn)
        self.assertEqual(ing.resolve(idx, 'HAMMERSMITH (H&C)'), '9400ZZLUHSC')


class TestLineAwareResolution(unittest.TestCase):
    """Co-named stations must be told apart by the line the row came from.

    Edgware Road is the case that matters: two separate stations 150 m apart,
    one a 24.9 m deep-tube platform and one a 5.2 m sub-surface box. Picking
    the wrong one puts the depths 19.7 m out — wider than the engine's entire
    12 m match tolerance, so the barometric condition fails at that station
    every time and does so silently.
    """

    STOPS = [
        ('9400ZZLUERB', 'Edgware Road (Bakerloo) Underground Station'),
        ('9400ZZLUERC', 'Edgware Road (Circle Line) Underground Station'),
        ('9400ZZLUHSD', 'Hammersmith (Dist&Picc Line) Underground Station'),
        ('9400ZZLUHSC', 'Hammersmith (H&C Line) Underground Station'),
    ]
    SEQUENCES = [
        ('bakerloo', '9400ZZLUERB'),
        ('circle', '9400ZZLUERC'),
        ('district', '9400ZZLUERC'),
        ('hammersmith-city', '9400ZZLUERC'),
        ('district', '9400ZZLUHSD'),
        ('piccadilly', '9400ZZLUHSD'),
        ('circle', '9400ZZLUHSC'),
        ('hammersmith-city', '9400ZZLUHSC'),
    ]

    def setUp(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.execute(
            'CREATE TABLE StopPoints (id TEXT PRIMARY KEY, name TEXT, '
            'transit_type TEXT, latitude REAL, longitude REAL, '
            'wifi_ssid TEXT, indicator TEXT)')
        self.conn.execute(
            'CREATE TABLE RouteSequences (line_id TEXT, direction TEXT, '
            'branch_id INTEGER, seq_index INTEGER, stop_id TEXT)')
        self.conn.execute(
            'CREATE TABLE StationDepths (stop_id TEXT, line_id TEXT, '
            'depth_metres REAL, source TEXT, PRIMARY KEY (stop_id, line_id))')
        for sid, nm in self.STOPS:
            self.conn.execute(
                'INSERT INTO StopPoints VALUES (?,?,?,0,0,NULL,NULL)',
                (sid, nm, 'underground'))
        for i, (line, sid) in enumerate(self.SEQUENCES):
            self.conn.execute(
                'INSERT INTO RouteSequences VALUES (?,?,?,?,?)',
                (line, 'inbound', 0, i, sid))
        self.index = ing.build_naptan_index(self.conn)
        self.members = ing.line_members(self.conn)

    def tearDown(self):
        self.conn.close()

    def test_index_keeps_every_candidate(self):
        """One key, two stations — collapsing them is the original bug."""
        self.assertEqual(sorted(self.index['edgware road']),
                         ['9400ZZLUERB', '9400ZZLUERC'])

    def test_depth_sheet_names_resolve_per_line(self):
        cases = [
            ('Edgware Road (Bakerloo)', 'bakerloo', '9400ZZLUERB'),
            ('Edgware Road (Circle, District, H & C)', 'district', '9400ZZLUERC'),
            ('Edgware Road (Circle, District, H & C)', 'hammersmith-city',
             '9400ZZLUERC'),
            ('Hammersmith  (District)', 'district', '9400ZZLUHSD'),
            ('Hammersmith  ', 'hammersmith-city', '9400ZZLUHSC'),
        ]
        for name, line, expected in cases:
            self.assertEqual(
                ing.resolve(self.index, name, line, self.members), expected,
                f'{name!r} on {line} should resolve to {expected}')

    def test_run_time_sheet_names_resolve_per_line(self):
        """The sheet writes a bare "EDGWARE ROAD" under four different lines."""
        for line, expected in (('Bakerloo', '9400ZZLUERB'),
                               ('Circle', '9400ZZLUERC'),
                               ('District', '9400ZZLUERC'),
                               ('H & C', '9400ZZLUERC')):
            lid = ing.line_id_of(line)
            self.assertEqual(
                ing.resolve(self.index, 'EDGWARE ROAD', lid, self.members),
                expected, f'EDGWARE ROAD on {line}')
        self.assertEqual(
            ing.resolve(self.index, 'HAMMERSMITH', 'piccadilly', self.members),
            '9400ZZLUHSD')

    def test_falls_back_when_topology_is_absent(self):
        """A topology-less database must still resolve, just without the hint.

        ingest_tfl_reference.py can be run standalone against a database that
        has no RouteSequences; degrading to the old best-guess is correct there,
        silently returning None would not be.
        """
        self.assertIsNotNone(ing.resolve(self.index, 'EDGWARE ROAD'))
        self.assertIsNotNone(
            ing.resolve(self.index, 'EDGWARE ROAD', 'bakerloo', {}))

    def test_line_that_does_not_serve_the_station_falls_back(self):
        """An on-line candidate is preferred, never required."""
        self.assertIsNotNone(
            ing.resolve(self.index, 'EDGWARE ROAD', 'victoria', self.members))


class TestSharedPlatformDerivation(unittest.TestCase):
    """The Circle owns no track, so FOI-0493 gives it no column at all."""

    def setUp(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.execute(
            'CREATE TABLE RouteSequences (line_id TEXT, direction TEXT, '
            'branch_id INTEGER, seq_index INTEGER, stop_id TEXT)')
        self.conn.execute(
            'CREATE TABLE StationDepths (stop_id TEXT, line_id TEXT, '
            'depth_metres REAL, platform_level_asl_m REAL, source TEXT, '
            'PRIMARY KEY (stop_id, line_id))')
        for i, (line, sid) in enumerate([
                ('circle', 'STOP_A'), ('district', 'STOP_A'),
                ('circle', 'STOP_B'), ('metropolitan', 'STOP_B'),
                ('circle', 'STOP_C'),
                ('circle', 'STOP_D'), ('district', 'STOP_D'),
                ('metropolitan', 'STOP_D')]):
            self.conn.execute('INSERT INTO RouteSequences VALUES (?,?,?,?,?)',
                              (line, 'inbound', 0, i, sid))
        for sid, line, depth, asl in [('STOP_A', 'district', 5.2, 10.8),
                                      ('STOP_B', 'metropolitan', 8.0, 4.0),
                                      ('STOP_D', 'district', 4.0, 12.0),
                                      ('STOP_D', 'metropolitan', 30.0, -14.0)]:
            self.conn.execute(
                'INSERT INTO StationDepths VALUES (?,?,?,?,?)',
                (sid, line, depth, asl, 'tfl_foi'))

    def tearDown(self):
        self.conn.close()

    def depth(self, stop_id, line_id='circle'):
        return self.conn.execute(
            'SELECT depth_metres, source FROM StationDepths '
            'WHERE stop_id=? AND line_id=?', (stop_id, line_id)).fetchone()

    def altitude(self, stop_id, line_id='circle'):
        row = self.conn.execute(
            'SELECT platform_level_asl_m FROM StationDepths '
            'WHERE stop_id=? AND line_id=?', (stop_id, line_id)).fetchone()
        return row[0] if row else None

    def test_derives_from_the_shared_sub_surface_platform(self):
        ing.derive_shared_platform_depths(self.conn)
        self.assertEqual(self.depth('STOP_A'), (5.2, 'tfl_foi_shared_platform'))
        self.assertEqual(self.depth('STOP_B'), (8.0, 'tfl_foi_shared_platform'))

    def test_no_donor_means_no_row_invented(self):
        ing.derive_shared_platform_depths(self.conn)
        self.assertIsNone(self.depth('STOP_C'))

    def test_disagreeing_donors_are_skipped(self):
        """4 m and 30 m cannot be the same platform, so trust neither.

        This is the guard that stops a deep-tube depth being lent to a
        sub-surface line if the donor map is ever wrong.
        """
        ing.derive_shared_platform_depths(self.conn)
        self.assertIsNone(self.depth('STOP_D'))

    def test_never_overwrites_a_real_measurement(self):
        self.conn.execute("INSERT INTO StationDepths "
                          "VALUES ('STOP_A','circle',99.0,1.0,'tfl_foi')")
        ing.derive_shared_platform_depths(self.conn)
        self.assertEqual(self.depth('STOP_A'), (99.0, 'tfl_foi'))

    def test_altitude_is_carried_across_with_the_depth(self):
        """A derived row without an altitude would be useless to the matcher."""
        ing.derive_shared_platform_depths(self.conn)
        self.assertEqual(self.altitude('STOP_A'), 10.8)
        self.assertEqual(self.altitude('STOP_B'), 4.0)


class TestPlatformAltitude(unittest.TestCase):
    """Altitude is the quantity the barometer can actually corroborate.

    A barometer reads a *change* in altitude. Depth below the local street
    cannot express that, because streets are not level with one another —
    Tooting Broadway's is 16 m above sea level and Hampstead's is 108 m. The
    old model compared descent-since-boarding against depth and so assumed
    every street was at the same height; on Tooting Broadway -> Euston that is
    wrong by 21.8 m at the destination, nearly twice the match tolerance.
    """

    # (published level on LU datum, ground level) -> (depth, altitude)
    def test_sheet_yields_both_quantities(self):
        published, ground = 103.6, 25.0          # Euston, Charing X branch
        altitude = published - ing.TUNNEL_DATUM_OFFSET_M
        depth = ground - altitude
        self.assertAlmostEqual(altitude, 3.6, places=1)
        self.assertAlmostEqual(depth, 21.4, places=1)

    def test_descent_between_stations_uses_altitude_not_depth(self):
        """The invariant the engine now relies on."""
        tooting_alt, tooting_depth = 3.2, 12.8
        euston_alt, euston_depth = 3.6, 21.4

        true_descent = tooting_alt - euston_alt
        self.assertAlmostEqual(true_descent, -0.4, places=1)

        # What the old model would have expected at Euston.
        self.assertAlmostEqual(euston_depth, 21.4, places=1)
        self.assertGreater(abs(euston_depth - true_descent), 21.0)

        # Both stations are deep, but the journey between them is almost level
        # because both streets sit at a similar height.
        self.assertGreater(tooting_depth, 10.0)
        self.assertGreater(euston_depth, 10.0)


class TestSurfacePlatformLevels(unittest.TestCase):
    """The DLR, Elizabeth line and Overground get a prior only from elevation."""

    def setUp(self):
        self.conn = sqlite3.connect(':memory:')
        self.conn.executescript('''
            CREATE TABLE RouteSequences (line_id TEXT, direction TEXT,
                branch_id INTEGER, seq_index INTEGER, stop_id TEXT);
            CREATE TABLE StationDepths (stop_id TEXT, line_id TEXT,
                depth_metres REAL, platform_level_asl_m REAL, source TEXT,
                PRIMARY KEY (stop_id, line_id));
            CREATE TABLE Elevation (stop_id TEXT PRIMARY KEY,
                ground_elev_m REAL NOT NULL, easting INTEGER, northing INTEGER,
                source TEXT);
        ''')
        for i, (line, stop) in enumerate([('dlr', 'DLR_A'), ('dlr', 'DLR_B'),
                                          ('northern', 'TUBE_A'),
                                          ('dlr', 'NO_ELEV')]):
            self.conn.execute('INSERT INTO RouteSequences VALUES (?,?,?,?,?)',
                              (line, 'inbound', 0, i, stop))
        for stop, elev in [('DLR_A', 12.0), ('DLR_B', -2.3), ('TUBE_A', 25.0)]:
            self.conn.execute(
                'INSERT INTO Elevation VALUES (?,?,NULL,NULL,?)',
                (stop, elev, 'os_terrain_50'))
        # An Underground station that already has a real measurement.
        self.conn.execute(
            "INSERT INTO StationDepths VALUES ('TUBE_A','northern',12.8,3.2,"
            "'tfl_foi')")

    def tearDown(self):
        self.conn.close()

    def row(self, stop_id, line_id):
        return self.conn.execute(
            'SELECT depth_metres, platform_level_asl_m, source '
            'FROM StationDepths WHERE stop_id=? AND line_id=?',
            (stop_id, line_id)).fetchone()

    def test_surface_stations_get_ground_level_as_platform_altitude(self):
        ing.fill_surface_platform_levels(self.conn)
        self.assertEqual(self.row('DLR_A', 'dlr'),
                         (0.0, 12.0, 'os_terrain_50_surface'))

    def test_below_sea_level_ground_is_preserved(self):
        """Canning Town really is below Ordnance Datum; do not clamp it."""
        ing.fill_surface_platform_levels(self.conn)
        self.assertEqual(self.row('DLR_B', 'dlr')[1], -2.3)

    def test_measured_underground_values_are_not_overwritten(self):
        ing.fill_surface_platform_levels(self.conn)
        self.assertEqual(self.row('TUBE_A', 'northern'),
                         (12.8, 3.2, 'tfl_foi'))

    def test_no_elevation_means_no_row_invented(self):
        ing.fill_surface_platform_levels(self.conn)
        self.assertIsNone(self.row('NO_ELEV', 'dlr'))

    def test_source_marks_the_assumption(self):
        """These rows assert 'at surface level', not 'measured 0 m down'.

        The genuinely sub-surface exceptions the source data misses — the
        Elizabeth line core, the Thames Tunnel — land here too and will be
        wrong. Marking them keeps that correctable in bulk.
        """
        ing.fill_surface_platform_levels(self.conn)
        self.assertEqual(self.row('DLR_A', 'dlr')[2], 'os_terrain_50_surface')


if __name__ == '__main__':
    unittest.main(verbosity=2)
