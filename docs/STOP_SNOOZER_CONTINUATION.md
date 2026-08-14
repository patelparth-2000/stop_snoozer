# StopSnoozer — Session Continuation

**Read this file first. Then read `STOPSNOOZER_PLAN.md`.**
This file is only for the StopSnoozer project.

> **Also read [STOPSNOOZER_ISSUES.md](STOPSNOOZER_ISSUES.md)** — the full defect and risk
> register (49 items). Several tasks marked ✅ in the plan have known gaps recorded there;
> notably **U12 (Cell-ID) is dead code at runtime** and **F1's ground-truth logging is
> unwired**, which together block calibration.

| | |
|---|---|
| **Last session** | 2026-08-10 |
| **Current phase** | v1 complete. v2 engine built **on real TfL data**, not yet field-verified. Play compliance code written, not yet run on a device. |
| **Next task** | **Regenerate the asset (`--all`), then run F2.** Blocked only on physical access to the route. |

> **Play submission work is now tracked in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md)** —
> declaration wording, video shot list, Data Safety answers and the keystore
> command. Everything there is written; none of it is submitted.

---

## Status in one paragraph

v1 (above-ground) is complete and hardened. The v2 underground stack is built
and now runs on **real TfL data** rather than estimates: platform depths and
inter-station run times were ingested from TfL FOI releases, with the 100 m
tunnel-datum correction applied and validated against four independently
published figures. 21 of the 50 tracked issues are resolved. What remains is
mostly **not code** — the fusion thresholds still need calibrating against a
real journey, and that needs someone on a train.

---

## What is left, and why

| Item | Status | Blocker |
|---|---|---|
| **Regenerate asset (`--all`)** | 🔴 | Just needs running; see above |
| **F2 — field test** | 🔴 | Requires physically riding Tooting Broadway → Euston on both Northern branches. Protocol in plan Section 11. |
| **Threshold calibration** | 🔴 | Depends on F2 logs |
| **Release signing keystore** | 🔴 | Gradle wired 2026-08-10; needs your `.jks` + `key.properties`. Command in PLAY_SUBMISSION.md §1 |
| **Play submission** | 🟡 | Disclosure, consent, targetSdk 36 and all the wording are done. Needs a Play Console: submit the declaration, host the policy on Pages, record the video |
| Fingerprint consent UI | ✅ | Built 2026-08-10. Prompted at first journey setup; revocable in System Health, and revoking erases |
| I-13 — multiple underground targets | 🟡 | `JourneyPlan` supports it; engine stops at the first |
| I-09 — per-leg alarm style in multi-target | 🟡 | `TargetStop` has no style field |
| I-16/I-17 — engine/GPS arbitration, journey-end UI | 🟡 | Both subsystems can run at once with no arbitration |
| I-23 — native tests for the fusion engine | ⬜ | Least-tested, most safety-critical code |
| U15 / U16 — TfL cache, Activity Transition | ⬜ | Not started |
| iOS (v3) | ❌ | Deferred by D10. Needs a Mac. |

---

## Before trusting the underground engine

Every constant marked `CALIBRATE` in
`android/app/src/main/java/com/stopsnoozer/app/UndergroundEngine.java` is a
starting value from the literature, **not a measurement**:

- `STOPPED_STD_DEV` — accelerometer noise floor; varies with how the phone is carried
- `DEPTH_MATCH_TOLERANCE_M`, `PRESSURE_SETTLE_HPA` — barometric matching
- `RUN_TIME_MIN_FRACTION` / `RUN_TIME_MAX_FRACTION` — the timing gate
- confidence gains/penalties and `CONFIDENCE_FAILSAFE_THRESHOLD`

To gather the data: on the route-select screen turn on **"Record sensor data for
this journey"** before tapping Start Tracking. During the ride, tap
**ARRIVED AT PLATFORM** the moment the train stops at each station, and
**Tunnel hold** if it stops between stations. Those markers are what the sensor
trace gets scored against — without them the logs cannot calibrate anything.

Then pull the CSVs from
`/Android/data/com.stopsnoozer.app/files/sensor_logs/`.

The `stop_candidate` rows are the important ones — each records which of the
three fusion conditions passed or failed, so a wrongly-rejected platform or a
wrongly-accepted tunnel hold is directly visible.

**Capture both branches**, and at least one run containing a mid-tunnel hold —
that is the negative case the fusion test exists to reject and the hardest thing
to tune without real data.

---

## The database asset — regenerated 2026-08-11

`assets/uk.db.gz` is now the **schema v6** build: 30.1 MB gzipped, 71.5 MB on
device, 381,096 stops (bus 376,633 · train 2,722 · ferry 799 · tram 542 ·
underground 355 · DLR 45) plus full TfL topology, run times, platform
altitudes and elevations.

It was previously stuck at v2 — no search index, no topology, no depths — which
is why route pre-selection showed "Route data not installed" and every
underground journey fell back to GPS.

**Size note.** It grew from 16.3 MB because v2 predated the FTS5 search index
and the lat/lon index, not because of the data added since. Measured cost:
`idx_stop_latlon` 6.4 MB, FTS5 6.2 MB, `idx_stop_name` 3.1 MB, `idx_stop_type`
0.9 MB, base data ~13.5 MB. All four indexes are used — check
`EXPLAIN QUERY PLAN` before trimming any of them. `idx_stop_type` looks like a
pointless six-value index but SQLite genuinely picks it for typed
`getClosestStops`, where underground+train is 0.8% of rows.

Re-run it with:

```bash
python tools/build_naptan_db.py --all
```

`--all` = `--with-topology` (TfL route sequences, branch points) plus
`--with-reference` (FOI platform depths and real inter-station run times).
Takes a while — it downloads the full NaPTAN CSV plus two spreadsheets.

It also downloads **OS Terrain 50** (~162 MB, OGL, no key) once and caches it in
`_os_terrain50/`. That is what gives the DLR, Elizabeth line and Overground a
barometric prior at all — see "depth vs altitude" below.

Expected output, from the build actually shipped on 2026-08-11:

```
381,096 rows inserted, 54,201 skipped.
31,416 row(s) had no lat/lon and were recovered from their grid reference.
2 station(s) kept from entrance records only; 3,740 duplicate entrances dropped.
2,718 sequence entries, 81 branch points, 0 unmatched NaPTAN ids.
elevation: 470/470 sequenced stops sampled from OS Terrain 50
run times: 736 legs written from 754 sheet rows
depths: 320 (stop,line) pairs from 274/274 stations (100.0%)
depths: derived 36 circle station(s) from district/hammersmith-city/metropolitan
depths: derived 17 hammersmith-city station(s) ...
platform levels: 216 surface (stop,line) pairs from OS Terrain 50
depth validation: all 4 known values within tolerance
platform validation: 1 co-named station pair(s) kept distinct
platform levels: 3 known altitudes within tolerance, none missing
coverage: run times 732/1152 adjacent legs from real TfL data (64%); the
          remaining 420 use geometric estimates
coverage: depths 470/470 sequenced stations (100%)
```

That 64% is the honest figure. The coverage line used to count *any* run-time
row and so reported 100% while a third of the legs were still the crude
straight-line estimates written during topology ingest. FOI-2748 covers London
Underground only; the estimated legs are DLR, Elizabeth line and Overground.

Three lines are load-bearing — if any of them reads differently, **stop**:

- **`0 unmatched NaPTAN ids`** and a non-zero sequence count. TfL publishes
  station ids as `940GZZLUHTD` while NaPTAN stores `9400ZZLUHTD`; they share no
  ids at all. `_naptan_alias()` bridges them. Before that fix every id was
  unmatched, `RouteSequences` came out empty, and the app showed "Route data
  not installed" while quietly using GPS underground — with no error anywhere.
- **`depth validation`**. FAILED means the 100 m tunnel-datum correction was
  lost and every depth is wrong by 100 m. See the header comment in
  `tools/ingest_tfl_reference.py`.
- **`platform validation`**. FAILED means two co-named stations collapsed onto
  one id. Edgware Road (Bakerloo) is 24.9 m down and Edgware Road (Circle) is
  5.2 m; confusing them is a 19.7 m error, wider than the engine's whole 12 m
  depth tolerance.

Verify the tooling itself with `python tools/test_ingest_tfl_reference.py`
(33 tests) and `python tools/test_build_naptan_db.py` (11 tests).

---

## Depth vs altitude — read before touching the barometric test

**The barometer measures a change in altitude, so the engine matches on
`platform_level_asl_m`, not `depth_metres`.** The two are different quantities
and confusing them was a real bug, fixed 2026-08-10.

Depth is measured from each station's *own street*, and streets are not level
with one another. Tooting Broadway's is 16 m above sea level, Hampstead's is
108 m; across the network ground level spans about 76 m against a 12 m match
tolerance. The engine used to compare descent-since-boarding directly against
depth, which silently assumed every street was at the same height. On the F2
route that put the expectation 21.8 m out at Euston, 23.8 m at Camden Town and
21.8 m at Tottenham Court Road — so the barometric condition could not pass at
the destination, and simulating the confidence machine trips the fail-safe at
Camden Town, one stop early.

What replaces it:

- `StationDepths.platform_level_asl_m` holds each platform's altitude. That is
  the sheet's *native* quantity — FOI-0493 publishes levels on a datum 100 m
  below Ordnance, so altitude is `published - 100` and depth is the derived
  one. `depth_metres` is kept for display.
- `UndergroundEngine` compares the altitude change **since the last confirmed
  platform** against the change the two platforms' levels predict. Both sides
  are differences, so it no longer matters where the pressure baseline was
  captured, and weather drift cannot accumulate across a journey.
- `anchorPressureHpa` is re-anchored at every arrival and at every
  `confirmPosition`. It is deliberately **invalidated on `restoreState`** — the
  pressure history dies with the process, so the next sample may be mid-tunnel.
  The test abstains until a real arrival rather than asserting a descent that
  never happened.
- **Known limitation:** the first leg is anchored wherever tracking started. If
  the user began above ground it is out by the boarding station's own depth.
  Self-corrects at the first confirmed arrival. Worth checking in the F2 logs
  before calibrating anything else.

`stop_candidate` rows in the sensor log now carry **both** sides: column `f` is
the measured altitude change, column `g` the expected one. A `depthOk=false`
row is uninterpretable without the pair — it cannot distinguish a bad reading
from a bad prior, which is exactly what calibration has to separate.

---

**Depth gaps are now filled by elevation, not left empty.** FOI-0493 covers
London Underground infrastructure only, and per-station depths for the DLR
(45), Elizabeth line (43), Overground (118) and the Bakerloo north of Queen's
Park (10) are **not published anywhere** — searched for individually, only a
handful of mutually inconsistent figures exist in journalism. Those stations
are overwhelmingly at grade, so `fill_surface_platform_levels()` records their
platform altitude as the OS Terrain 50 ground elevation, with
`source='os_terrain_50_surface'` marking the assumption.

That is honest but not free: the genuinely sub-surface exceptions it cannot
know about — the Elizabeth line core, the Thames Tunnel stations, Bank DLR,
Cutty Sark — are recorded as surface and **will be wrong**. This is a missing
depth, not an invented one, and the `source` value makes the whole set
correctable in bulk if a real dataset ever appears. Do not hand-populate them
from press figures; that puts unverifiable numbers into a safety-relevant
prior, and the engine treats a present altitude as authoritative.

---

## Warnings

- **Do not reintroduce SSID-based station identity.** Underground SSIDs are
  provider-branded and identical across all 260+ stations. `WifiPresenceDetector`
  deliberately detects *presence* only. Plan Section 3 lists the full set of
  disproven ideas — check it before adding any detection mechanism.
- **Cell-ID staleness filter is not optional.** `getAllCellInfo()` can return
  cells cached from the previous station. `CellObserver` rejects anything older
  than 5 s, and treats an indeterminable age as untrustworthy rather than fresh.
- **Arrival needs all three conditions.** Dropping any one reintroduces false
  arrivals on mid-tunnel holds.
- **Timing rejection must not cost confidence.** Correctly rejecting a hold is
  the system working, not degrading.
- **Schema changes must be made in two places**: `create_topology_schema()` in
  `tools/build_naptan_db.py` and `_createTopologySchema()` in
  `lib/data/services/stop_points_db.dart`, plus a `SCHEMA_VERSION` /
  `_requiredVersion` bump in both. They are kept in sync by hand.
- **Stop ids in the database are NaPTAN's, never TfL's.** Everything written to
  `RouteSequences`, `RunTimes` and `StationDepths` goes through
  `_naptan_alias()` first. Any new code that takes a naptanId straight from the
  TfL API and joins it against `StopPoints` will match nothing. Note that
  `DISTINCT_PLATFORMS` in the ingest script is written in the `9400ZZ…` form
  for exactly this reason.
- **Station names alone do not identify a station.** "Edgware Road" and
  "Hammersmith" are each two different stations, and the FOI sheets use the
  bare name for both. `resolve()` takes the line as a second key and needs
  `RouteSequences` populated, which is why topology must be ingested first.
- **Depth is per platform, and some platforms are shared.** A line with no
  column of its own in FOI-0493 (the Circle) or running over another line's
  metals (H&C over the District) inherits from
  `SHARED_PLATFORM_DONORS`. Donors must agree within `MAX_DONOR_SPREAD_M` or
  the value is skipped rather than guessed — that guard is what stops a
  deep-tube depth being lent to a sub-surface line.
- **Never match the barometer against `depth_metres`.** See "depth vs altitude"
  above. `platform_level_asl_m` is the column; depth is for display only. The
  legacy depth path in `depthMatchesStation()` exists solely so an app update
  ahead of an asset update still functions, and it carries the original bug.
- **Do not clamp a negative platform altitude to zero.** Canning Town sits
  below Ordnance Datum at -2.3 m, and several stations are genuinely below sea
  level. Depths are also legitimately negative at elevated stations —
  Shepherd's Bush Market is -5.9 m because it is on a viaduct.
- **Station identity is positional, never by name.** NaPTAN calls the same
  station different things on different records — the RLY is "Ashley Down",
  its entrance is "Ashley Down Rail Station". Deduping rail-station entrances
  (`RSE`) on an exact name match kept 441 entrances standing beside their own
  station; `_StationIndex` in the builder resolves them by position instead,
  which drops 3,740 and keeps the 2 that really have no station record.
  `nearest_within()` returns `0.0` for an exact hit, so test it with
  `is not None` — truthiness reads a perfect match as "nothing here".
- **Validate NaPTAN assumptions against the whole extract, not a slice.**
  Filtering to ATCO areas 910/940 shows zero `RSE` rows, because entrances are
  registered by local authorities under their own area codes. Two separate
  wrong conclusions in this file came from sampling before deciding.
- **Three co-named rail pairs are expected** and are NaPTAN's own modelling,
  not a dedupe failure: Farringdon, Whitechapel and Heathrow T5 each carry a
  separate ATCO code for their Elizabeth line and National Rail identities.
- **Do not key re-extraction off the schema version.** The asset is generated by
  separate tooling and lags the code; that combination re-extracts on every
  launch and still lacks the new tables. `_migrate()` handles this in place.
- **Never request background location before the disclosure dialog.**
  `SplashCubit.requestPermissions()` takes the disclosure as a required
  parameter and only calls `Permission.locationAlways.request()` when it
  returned `true`. That structure is deliberate — it is the exact ordering Play
  rejects apps for, so it is enforced by the signature rather than by a comment.
  Do not "simplify" it into a plain method that prompts directly.
- **Radio-scan consent is PECR reg. 6, not GDPR.** The regulation governs
  *accessing* information in terminal equipment, so "it never leaves the device"
  is not a defence and does not make consent optional. Keep the opt-in, and keep
  declining fully functional — that is what makes the consent freely given.
- **`RouteTopologyRepository`'s consent flag is static on purpose.** The
  repository is constructed ad hoc at several call sites; as an instance field
  it defaulted to `false` everywhere and silently disabled all learning forever.

---

## Build environment

- Flutter is **not on PATH**. SDK at `C:\Flutter_sdk_src\flutter`:
  `$env:PATH = "C:\Flutter_sdk_src\flutter\bin;$env:PATH"`
- **VS Code Java/Kotlin language servers hold `build/` jars open**, breaking
  `flutter clean` and Gradle cleanup with "being used by another process". Kill
  the `redhat.java` / `kotlinLanguageServer` / `GradleDaemon` java processes,
  then delete `build/`. VS Code restarts them. This recurs.
- **`flutter test` can crash** with `PathExistsException ... sqlite3.dll` after an
  APK build. Kill leftover `dart` / `flutter_tester` processes and delete
  `build/native_assets`.
- Kotlin incremental-cache stack traces mentioning `shared_preferences_android`
  and *"different roots"* are **benign** — pub cache on `C:`, project on `E:`.
  The build succeeds; don't chase them.

---

## Key files

| File | Role |
|---|---|
| `STOPSNOOZER_PLAN.md` | The reference. Section 8 = progress, Section 11 = field-test protocol. |
| `PLAY_SUBMISSION.md` | Play paperwork: keystore command, declaration wording, video shot list, Data Safety answers. |
| `docs/index.md` | The privacy policy. Served by GitHub Pages from `main` → `/docs`. |
| `.../shared/widgets/prominent_disclosure_dialog.dart` | Both consent dialogs. **Read its class doc before changing either call site.** |
| `.../app/UndergroundEngine.java` | Fusion engine + confidence machine. **All CALIBRATE constants live here.** |
| `.../app/SensorLogger.java` | Field-test CSV logging. |
| `.../app/JourneyPlan.java` | Resolved route handed from Dart to native. |
| `.../app/SnoozeTrackingService.java` | Foreground service; orchestrates GPS + underground. |
| `lib/data/repositories/route_topology_repository.dart` | Topology queries, plan assembly, fingerprints. |
| `lib/presentation/route_select/` | Route pre-selection UI. |
| `tools/build_naptan_db.py` | Database builder; use `--all`. |
| `tools/ingest_tfl_reference.py` | FOI depth + run-time ingestion. **Read its header before touching depth handling** — the 100 m datum correction lives there. |
| `tools/check_16kb_alignment.sh` | Real 16 KB check for the release pipeline. |
| `lib/presentation/route_select/components/field_test_panel.dart` | Ground-truth markers for F2. |
