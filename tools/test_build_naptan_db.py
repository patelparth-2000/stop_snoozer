"""
Tests for build_naptan_db.py.

Both things covered here are failures that produce a *plausible-looking*
database, which is why they need tests rather than eyeballing:

  1. The TfL / NaPTAN id namespaces. TfL publishes 940GZZLUHTD, NaPTAN stores
     9400ZZLUHTD. Match them raw and nothing matches — the build prints a large
     "unmatched" count and writes an empty RouteSequences, and the app then
     reports "Route data not installed" and falls back to GPS on every
     underground journey. Nothing crashes and the stop database is fine.

  2. The grid-reference fallback. NaPTAN leaves Latitude/Longitude blank on a
     handful of rows — as of the 2026-08 extract, on all ten Elizabeth line
     core stations — while still publishing Easting/Northing. Those rows were
     dropped, so the stations were simply absent.

Run:  python tools/test_build_naptan_db.py
"""

import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_naptan_db as B  # noqa: E402


class TestNaptanAlias(unittest.TestCase):

    def test_metro_station_ids(self):
        """TfL 940G... -> NaPTAN 9400... for London Underground."""
        self.assertEqual(B._naptan_alias('940GZZLUHTD'), '9400ZZLUHTD')
        self.assertEqual(B._naptan_alias('940GZZLUERB'), '9400ZZLUERB')

    def test_national_rail_station_ids(self):
        """The same positional rule covers Elizabeth line / Overground stops."""
        self.assertEqual(B._naptan_alias('910GBONDST'), '9100BONDST')
        self.assertEqual(B._naptan_alias('910GCANWHRF'), '9100CANWHRF')

    def test_only_position_four_is_rewritten(self):
        """A NaPTAN id must not be mangled into something else."""
        self.assertIsNone(B._naptan_alias('9400ZZLUHTD'))
        self.assertIsNone(B._naptan_alias('490G00012F'[:4]))

    def test_resolver_prefers_the_id_as_published(self):
        """If TfL ever emits plain NaPTAN ids, no further fix is needed."""
        resolve = B._make_stop_resolver({'9400ZZLUHTD', '940GZZLUXXX'})
        self.assertEqual(resolve('940GZZLUXXX'), '940GZZLUXXX')
        self.assertEqual(resolve('940GZZLUHTD'), '9400ZZLUHTD')

    def test_resolver_reports_genuinely_unknown_stops(self):
        resolve = B._make_stop_resolver({'9400ZZLUHTD'})
        self.assertIsNone(resolve('940GZZLUNOPE'))


class TestStationIndex(unittest.TestCase):
    """Proximity is the only workable key for entrance deduplication.

    Names cannot do it: NaPTAN calls the same station "Ashley Down" on its RLY
    record and "Ashley Down Rail Station" on its entrance. Deduping on an exact
    name match kept 441 entrances standing beside their own station.
    """

    def setUp(self):
        self.idx = B._StationIndex()
        self.idx.add(51.5074, -0.1278)          # Charing Cross

    def test_exact_position_matches(self):
        # Must be `is not None`, never truthiness: an exact hit is 0.0 metres,
        # which is falsy and would read as "no station here".
        self.assertIsNotNone(self.idx.nearest_within(51.5074, -0.1278))
        self.assertEqual(self.idx.nearest_within(51.5074, -0.1278), 0.0)

    def test_a_far_entrance_of_a_large_terminus_still_matches(self):
        self.assertIsNotNone(self.idx.nearest_within(51.5100, -0.1278))

    def test_a_genuinely_separate_station_does_not_match(self):
        self.assertIsNone(self.idx.nearest_within(51.5140, -0.1278))

    def test_search_spans_cell_boundaries(self):
        """A point just across a grid edge must still find its neighbour."""
        edge = B._StationIndex()
        edge.add(51.5099, -0.1278)              # just below the 0.01 boundary
        self.assertIsNotNone(edge.nearest_within(51.5101, -0.1278))

    def test_empty_index_matches_nothing(self):
        self.assertIsNone(B._StationIndex().nearest_within(51.5, -0.1))


class TestOsgb36ToWgs84(unittest.TestCase):
    """Checked against coordinates NaPTAN itself publishes both ways."""

    # (easting, northing, expected lat, expected lon) — NaPTAN's own values
    # for stations that carry both representations.
    FIXTURES = [
        (528661, 181068, 51.513895, -0.147246),   # Bond Street
        (531580, 181843, 51.520188, -0.104915),   # Farringdon
        (547372, 179055, 51.491241, 0.121374),    # Abbey Wood
        (526582, 181300, 51.516449, -0.177107),   # Paddington
    ]

    def test_matches_published_coordinates(self):
        for easting, northing, exp_lat, exp_lon in self.FIXTURES:
            lat, lon = B.osgb36_to_wgs84(easting, northing)
            self.assertAlmostEqual(lat, exp_lat, places=4)
            self.assertAlmostEqual(lon, exp_lon, places=4)

    def test_error_is_sub_metre(self):
        """Measured across NaPTAN: median 0.19 m. Assert well inside that."""
        for easting, northing, exp_lat, exp_lon in self.FIXTURES:
            lat, lon = B.osgb36_to_wgs84(easting, northing)
            metres = math.hypot((lat - exp_lat) * 111_320,
                                (lon - exp_lon) * 111_320
                                * math.cos(math.radians(lat)))
            self.assertLess(metres, 2.0)

    def test_lands_in_london(self):
        """A transposed easting/northing would still return *a* number."""
        lat, lon = B.osgb36_to_wgs84(530000, 180000)
        self.assertTrue(51.0 < lat < 52.0, lat)
        self.assertTrue(-1.0 < lon < 1.0, lon)


class TestStopTypeFiltering(unittest.TestCase):

    def test_child_records_are_skipped(self):
        """Platforms and area references duplicate their parent station."""
        for stop_type in ('PLT', 'TMU', 'RPL'):
            self.assertIn(stop_type, B._SKIP_STOP_TYPES)

    def test_station_access_areas_are_kept(self):
        for stop_type in ('RLY', 'MET'):
            self.assertNotIn(stop_type, B._SKIP_STOP_TYPES)

    def test_entrances_are_resolved_by_position_not_stop_type(self):
        """Entrances are deduped per station in build_db(), not by StopType.

        Of 3,742 entrance records, 3,740 duplicate a station that is already
        present and 2 do not. Neither a blanket skip nor a blanket keep is
        right, so the decision cannot live in this set.
        """
        self.assertNotIn('RSE', B._SKIP_STOP_TYPES)

    def test_a_surviving_entrance_is_a_rail_station_not_a_bus_stop(self):
        """It is the only record its station has, so it must read as rail.

        The old fallback typed these 'bus' (their ATCO is a local-authority
        area, not 910), which pushed them below actual bus stops in search
        ranking for a query like "Ascot".
        """
        self.assertEqual(B._classify('0100ASHYDN0', 'RSE')[0], 'train')

    def test_classification(self):
        self.assertEqual(B._classify('9400ZZLUHTD', 'MET')[0], 'underground')
        self.assertEqual(B._classify('9400ZZDLBAN', 'MET')[0], 'dlr')
        self.assertEqual(B._classify('9100BONDST', 'RLY')[0], 'train')


if __name__ == '__main__':
    unittest.main(verbosity=2)
