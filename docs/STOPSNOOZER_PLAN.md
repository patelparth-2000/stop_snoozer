# StopSnoozer — Master Implementation Plan & Progress Tracker

**Single source of truth for the StopSnoozer build.**
Commuter wake-up alarm for UK rail, bus, and the London Underground.
Flutter · Android-primary · Offline-capable

| | |
|---|---|
| **Created** | 2026-08-08 |
| **Last updated** | 2026-08-10 |
| **Current phase** | v1 complete; v2 underground engine built on real TfL data, **awaiting field calibration**. Play compliance code written, not yet exercised on a device. |
| **Next milestone** | Regenerate the asset → F2 field test → threshold calibration |
| **Next task** | **`python tools/build_naptan_db.py --all`, then F2 — ride the route with logging on.** F2 is blocked on physical access. |
| **Continuation file** | `STOP_SNOOZER_CONTINUATION.md` (read that first in a new session) |
| **Issue register** | `STOPSNOOZER_ISSUES.md` — 21 of 50 resolved. Several tasks marked ✅ below have known gaps recorded there. |
| **Play paperwork** | `PLAY_SUBMISSION.md` |

---

## Table of Contents

1. [How to Use This Document](#1-how-to-use-this-document)
2. [Settled Decisions — Do Not Re-Litigate](#2-settled-decisions--do-not-re-litigate)
3. [Disproven Claims — Never Reintroduce](#3-disproven-claims--never-reintroduce)
4. [The Four-Layer Architecture](#4-the-four-layer-architecture)
5. [Signal Ranking](#5-signal-ranking)
6. [Data Model Additions Required](#6-data-model-additions-required)
7. [Codebase Audit — What Actually Exists](#7-codebase-audit--what-actually-exists)
8. [Progress Tracker](#8-progress-tracker)
9. [Blocked / Needs Field Testing](#9-blocked--needs-field-testing)
10. [Compliance Checklist](#10-compliance-checklist)
11. [Field Test Protocol](#11-field-test-protocol)
12. [Accuracy Expectations](#12-accuracy-expectations)
13. [Cost Reality](#13-cost-reality)
14. [Key Sources](#14-key-sources)
15. [Change Log](#15-change-log)

---

## 1. How to Use This Document

This document is the reference for the entire StopSnoozer build. It consolidates four rounds of technical review — the assumptions that were tested and broken, the corrections that emerged, and the architecture that survived.

**Reading order for a new session:**

1. `STOP_SNOOZER_CONTINUATION.md` — where the last session stopped
2. Section 2 and 3 of this document — the settled decisions and the disproven claims
3. Section 8 — the progress tracker, to find the first unfinished task
4. The specific files named in the continuation file

**Rules for maintaining this document:**

- Section 8 is updated based on **work actually completed and verified**, never on work merely planned.
- A task moves to ✅ only when the code exists *and* has been exercised (compiled, run, or tested). Written-but-unverified work stays 🔵.
- When all work is complete, delete `STOP_SNOOZER_CONTINUATION.md` and mark this document complete at the top.
- Section 3 is load-bearing. Several of these ideas are intuitive and were independently proposed more than once before being disproven. Re-check Section 3 before adding any detection mechanism.

**Status legend**

| Symbol | Meaning |
|---|---|
| ✅ | Done and verified |
| 🔵 | Code written, not yet verified on a device |
| 🟡 | In progress |
| ⬜ | Not started |
| 🔴 | Blocked |
| 🧪 | Needs field testing to determine thresholds |
| ❌ | Deliberately dropped — do not build |

---

## 2. Settled Decisions — Do Not Re-Litigate

These emerged from the review and are final unless field testing contradicts them.

| # | Decision | Rationale |
|---|---|---|
| D1 | **Route pre-selection is mandatory** | Multiple valid routes reach any destination (the Oxford Circus problem). Sensor-only disambiguation needs ~3 stops of evidence — long after the branch decision. Transit and Citymapper both require pre-selection. It is the correct design, not a compromise. |
| D2 | **Presence, not identity** | A Wi-Fi/cell signal need not identify *which* station. Route narrowing supplies identity; the signal only confirms "we are at a station." This turns an absolute-localiser problem into a sequence-detector problem. |
| D3 | **Barometer is the primary underground signal** | ~0.12 hPa/metre. A 20–30 m descent is 2.4–3.6 hPa — far above sensor noise. |
| D4 | **Cell-ID is opportunistic only, never primary** | The phone shows literal **No Service** in deep tube. `getAllCellInfo()` returns null/empty or *stale cached cells from the last station* — an active false-positive source. `requestNetworkScan()` needs `MODIFY_PHONE_STATE` (system/signature-only). Every reading must be timestamp-filtered, rejecting anything >5 s old. |
| D5 | **Wi-Fi is corroboration, not a metronome** | Android throttles scans to 4 per 2 minutes; a foreground service does not exempt you. Time scans around expected arrival windows. |
| D6 | **Arrival requires a three-way fusion test** | Accelerometer full stop **AND** barometric settle at expected station depth **AND** elapsed time inside the expected run-time window. A mid-tunnel hold satisfies only the first — this is the tunnel-hold discriminator and it is the single most important correctness rule in the engine. |
| D7 | **Confidence state machine, not a stop counter** | Maintain a belief over possible positions. When confidence drops, wake the user **one stop early** with an honest message. Never guess silently. |
| D8 | **Expected-transition detection, not generic mode classification** | Because the route is pre-selected, the app knows which transitions to expect. Android Activity Recognition reports only generic `IN_VEHICLE` and cannot distinguish bus from train — use it as a cheap secondary confirmer only. |
| D9 | **No offline bus route database** | ~19,600 TfL bus stops and ~670 routes for zero benefit; buses run above ground where GPS works. Optional middle ground: cache only routes on saved commutes. |
| D10 | **Android first, iOS deferred to v3** | The Android detection stack does not port: iOS forbids Wi-Fi scanning and granular cell reads, and background CoreMotion dead-reckoning is not sanctioned by Apple. |
| D11 | **Kennington branch resolved by user prompt** | Prompt at Kennington ("Charing Cross or Bank?"). Near-100% reliable, trivial to build. Upgrade to automatic later only if field testing exceeds ~95%. |
| D12 | **FTS5 or prefix indexing for search** | `LIKE '%foo%'` full-scans 500 k rows. |

---

## 3. Disproven Claims — Never Reintroduce

| Claim | Reality |
|---|---|
| Per-station Wi-Fi SSIDs are available from open data | **Fabricated.** The NaPTAN schema has no Wi-Fi fields. TfL publishes only aggregated crowding, never AP identifiers. |
| Underground SSIDs are station-unique | **False.** Provider-branded and identical across all 260+ stations — "TfL WiFi", "EE WiFi", "Three_WiFi". An SSID cannot tell you which station you are at. |
| iOS background CoreMotion dead-reckoning | **Not sanctioned by Apple.** No general background accelerometer mode. Rejection risk under Guideline 2.5.4; Apple DTS explicitly warns against it. |
| Android background Wi-Fi scanning is continuous | **Throttled** to 4 scans / 2 min. Still requires `ACCESS_FINE_LOCATION` and location services ON. |
| Cell-ID works with No Service | **No.** Returns null/empty or stale cache. `requestNetworkScan()` is system-only. |
| 100% offline tracking | **Not at useful accuracy.** The data layer is fully offline; tracking needs opportunistic signals. |
| 100% zero cost | **False.** ~$124 in store fees minimum, plus a Mac for iOS. Operating cost is genuinely ~£0. |
| Sub-1 ms search on 500 k rows | Only for **prefix** queries on a warm index. |
| Activity Recognition distinguishes bus from train | **No.** Reports only generic `IN_VEHICLE`. |

> **Note on the current codebase:** the `wifi_ssid` column in `StopPoints` and the exact-SSID equality matching in `SnoozeTrackingService.evaluateWifiResults()` are direct implementations of the disproven identity model. They are scheduled for replacement in Section 8, task **U3**.

---

## 4. The Four-Layer Architecture

### Layer 1 — Route pre-selection (mandatory)

User picks origin, destination, and — where multiple routes exist — the specific line and interchanges, at trip setup while online and attentive. Default to the typical route so regular commutes stay one tap. This eliminates runtime ambiguity entirely.

### Layer 2 — Opportunistic fixes wherever signal exists

At any platform or concourse with Wi-Fi or cellular, take a fix and **reset the tracker to certainty**. Use cached TfL Unified API / National Rail Darwin snapshots for delay-aware timing. Refresh via `WorkManager` whenever connectivity appears — never on a fixed schedule.

### Layer 3 — Offline sensor coasting (the primary underground engine)

See Section 5 for the signal ranking.

**The tunnel-hold discriminator (critical — decision D6):**

```
declareArrival  ⟺  accelerometerFullStop
                 ∧ barometricSettleAtExpectedDepth
                 ∧ elapsedTime ∈ expectedRunTimeWindow
```

A mid-tunnel hold satisfies only the first condition. All three are required.

### Layer 4 — Confidence state machine + fail-safe

Maintain a *belief* over possible positions, not a brittle counter. When confidence drops — missed detection, ambiguous branch, no corroboration — **wake the user one stop early** with an honest message:

> *"Approaching your area — couldn't confirm exact position."*

Never guess silently.

### Transport mode detection

- **Entering the Underground:** geofence at the known station entrance (NaPTAN/TfL coordinates) + GPS signal loss + barometric descent signature (clean multi-hPa rise over 20–60 s riding down) + escalator accelerometer signature (`STILL` while vertically displaced)
- **Exiting:** reverse barometric ascent + GPS reacquisition + cellular service returning (`ServiceStateListener`)
- **Bus vs walking:** GPS speed and heading alone. No road map-matching needed.

### Multiple alarm stations

Trivial on Android — a list of target nodes checked by the same detection loop. No OS cap. (iOS's 20-geofence limit is irrelevant underground, since geofences need location fixes tunnels don't provide.)

### Self-learned fingerprint database

1. On journeys with connectivity/GPS, record `{confirmed station, timestamp, visible BSSIDs, visible cells, barometric baseline}`
2. Build per-station fingerprints with observation frequencies; age out stale entries (TfL is migrating Virgin Wi-Fi → Boldyn, so churn is expected)
3. On later journeys, match observed fingerprints to raise confidence and enable recovery-mode re-localisation
4. Store on-device (SQLite). Disclose clearly that identifiers are recorded locally.

---

## 5. Signal Ranking

| Rank | Signal | Role |
|---|---|---|
| 1 | **Barometer** | Primary positioning. Detects station-depth arrival and network entry/exit. |
| 2 | **Accelerometer** | Stop/start detection + vibration footprint matching (~90% line/station accuracy at ≥3 stops). |
| 3 | **Timing prior** | Known inter-station run times gate every candidate arrival — rejects tunnel holds. |
| 4 | **Wi-Fi presence** | Opportunistic confirmation, 4 scans / 2 min, timed to expected arrival windows. Also seeds the fingerprint DB. |
| 5 | **Cell-ID** | Opportunistic only. Mandatory timestamp filter (reject >5 s old). |
| 6 | **Magnetometer / gyroscope** | Largely unusable in a steel carriage. Context only. |

---

## 6. Data Model Additions Required

The current `StopPoints` schema carries no topology. The v2 engine cannot work without it.

**Current schema** (`lib/data/services/stop_points_db.dart`):

```sql
CREATE TABLE StopPoints (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, transit_type TEXT NOT NULL,
  latitude REAL NOT NULL, longitude REAL NOT NULL,
  wifi_ssid TEXT,          -- ← disproven, to be dropped (task U3)
  indicator TEXT
)
```

**Additions needed:**

| Table | Purpose | Source |
|---|---|---|
| `Lines` | Line id, name, colour, mode | TfL Unified API `Line/Route` |
| `RouteSequences` | Ordered `(line_id, direction, seq_index, stop_id)` — the topology that makes stop-counting possible | TfL `Line/{id}/Route/Sequence/{direction}` |
| `Branches` | Branch points and their alternatives (e.g. Kennington) | Derived from route sequences |
| `RunTimes` | `(line_id, from_stop, to_stop, seconds)` — gates the fusion test | TfL timetable / field measurement |
| `StationDepths` | `(stop_id, platform_depth_metres)` — the barometric expectation | Public depth data + field measurement 🧪 |
| `Fingerprints` | Self-learned `(stop_id, bssid/cell_id, observation_count, last_seen)` | Recorded on-device |

Station depths and run times are the two that field testing must validate — see Section 11.

---

## 7. Codebase Audit — What Actually Exists

> ⚠️ **This section is a dated snapshot, not the current state.** It records the
> tree as it stood on 2026-08-08, *before* v2 was built, and is kept for the
> findings it produced. Most of "Absent or wrong" below has since been fixed —
> the sensors exist, the topology tables exist, `applicationId` is
> `com.stopsnoozer.app`, attribution shipped, and there are 26 Dart tests.
> **For current state read Section 8 and `STOPSNOOZER_ISSUES.md`, not this.**

Audited 2026-08-08 against the working tree at `main` (`58bca0f`).

**Scale:** 74 Dart files, 4 Java files + 1 Kotlin activity (~1,845 native lines), 1 Python DB builder.

### Working and substantial

| Area | State |
|---|---|
| GPS geofencing, multi-target | `SnoozeTrackingService.java` — `FusedLocationProviderClient`, high-accuracy + balanced-power fallback, `checkLocationAndTrigger()` distance test over a target list |
| Foreground service resilience | `START_STICKY`, state persisted to SharedPreferences, `resumeFromPrefs()`, `onTaskRemoved()` AlarmManager re-arm, `BootReceiver` |
| Exact-alarm scheduling | `AlarmScheduler.java`, `CommuteAlarmReceiver.java` |
| Alarm UX | Full-screen intent, lock-screen visibility, snooze, user ringtone picker, subtle-vs-defcon styles, slide-to-dismiss |
| Offline stop database | `uk.db.gz` asset + `tools/build_naptan_db.py` (NaPTAN CSV → SQLite → gzip), ~430-stop dev seed fallback, 16 KB page size |
| Full UI | Splash, dashboard, search, trip config, alarm, system health, calendar, onboarding, 5 themes with launcher-icon aliases |
| Platform channel | 22 methods bridging Dart ↔ native |
| Battery-optimisation exemption | `checkBatteryOptimization` / `requestBatteryOptimization` channel methods |
| Manifest compliance | `foregroundServiceType="location"`, `FOREGROUND_SERVICE_LOCATION`, `USE_EXACT_ALARM`, background location, full-screen intent |

### Absent or wrong

| Gap | Detail |
|---|---|
| **No sensors at all** | Zero barometer, accelerometer, or `SensorManager` usage anywhere in the tree. `sensors_plus` is not a dependency. The entire v2 engine is unbuilt. |
| **Disproven Wi-Fi model still shipped** | `evaluateWifiResults()` does exact `SSID`/`BSSID` equality against a per-stop `wifi_ssid` column that no open dataset can populate. This is Section 3's first disproven claim, implemented. |
| **No route topology** | No `Lines`, `RouteSequences`, `RunTimes`, `StationDepths`, or `Branches` tables. No line/direction concept in the models. |
| **No route pre-selection UI** | `TripConfigCubit` manages an ordered leg list with radius and alarm style — but no line, direction, or interchange selection. Layer 1 is unbuilt. |
| **No confidence state machine** | Detection is a boolean `alarmFired` flag. No belief state, no fail-safe early alarm. |
| **Search uses `LIKE`** | `where: 'name LIKE ?'` with a plain `idx_stop_name` B-tree index — the exact anti-pattern D12 rules out. |
| **`applicationId` is `com.example.stop_snoozer`** | **Hard Play Store blocker** — Google Play rejects `com.example.*`. Must change before any submission. |
| **No OGL v3.0 attribution** | Legally required for NaPTAN. No attribution string anywhere in `lib/`. |
| **No "test your alarm" feature** | Named in the plan as a first-class v1 requirement (mitigates OEM service kills). Absent. |
| **Missing permissions** | `READ_PHONE_STATE` and `ACTIVITY_RECOGNITION` not declared. |
| **README describes the disproven architecture** | Advertises Wi-Fi SSID station detection, iOS dead-reckoning, and "100% offline / zero-backend". All three are in Section 3. |
| **Effectively no tests** | `test/widget_test.dart` only. |

**Environment note:** `minSdk = 30`, so every sensor and telephony API in this plan is available without legacy branching.

---

## 8. Progress Tracker

> Updated from verified work only. See the status legend in Section 1.

### v1 — Android, above-ground

| ID | Task | Status | Notes |
|---|---|---|---|
| A1 | Offline NaPTAN stop database | ✅ | `uk.db.gz` + `tools/build_naptan_db.py`; dev seed fallback |
| A2 | GPS geofencing alarm (bus + rail) | ✅ | Multi-target, GPS + network fallback |
| A3 | Exact-alarm scheduler with departure-time activation | ✅ | `AlarmScheduler.java` + `CommuteAlarmReceiver` |
| A4 | Foreground service survives kill / reboot | ✅ | `START_STICKY` + prefs restore + `BootReceiver` + `onTaskRemoved` re-arm |
| A5 | Alarm UI — full-screen, slide-to-dismiss, snooze, ringtone choice | ✅ | |
| A6 | Multi-leg trip configuration | ✅ | Reorderable legs, per-leg radius and alarm style |
| A7 | Theming + launcher icon aliases | ✅ | 5 themes |
| A8 | Battery-optimisation exemption request | ✅ | Generic Android dialog only — see A9 |
| A9 | OEM-specific battery onboarding | ✅ | `OemBatteryHelper` — resolve-checked deep links for MIUI/Huawei/Honor/Oppo/Realme/Vivo/Samsung/Asus/LeEco/OnePlus. Card hidden when no Activity resolves, rather than sending users to a screen their phone lacks. |
| A10 | "Test your alarm" feature | ✅ | `AlarmSelfTest` — schedules a real alarm through AlarmManager → receiver → foreground service, so it exercises the OS waking a backgrounded app (the thing that actually breaks). Resolution reads a native fired-timestamp, not a Dart timer, so a process kill reports failure instead of a false pass. |
| A11 | FTS5 / prefix-indexed search | ✅ | External-content FTS5 with `prefix='2 3 4'`, both in `build_naptan_db.py` and the dev-seed path. Query builder neutralises FTS5 operators in user input. Ranking puts stations above bus stops. LIKE retained as a fallback only. 12 tests. |
| A12 | OGL v3.0 attribution in-app | ✅ | `AttributionCard` in System Health: OGL statement, TfL credit + non-endorsement, on-device privacy note |
| A13 | **Change `applicationId` off `com.example.*`** | ✅ | Now `com.stopsnoozer.app` (matches the existing `com.stopsnoozer.app.*` action constants). Java + Kotlin packages moved via `git mv`, all 5 hardcoded launcher-alias strings updated, iOS bundle id aligned. Verified: clean debug APK builds, merged manifest resolves all aliases to the new package, `analyze` clean, tests pass. |
| A14 | Two-stage alerts (early nudge + firm alarm) | ✅ | Silent low-priority nudge at 2.5× wake radius (capped 2 km), once per stop; suppressed when the outer ring is within 1.2× the radius so both alerts don't land together. Firm alarm cancels the nudge banner. |
| A15 | Declare `READ_PHONE_STATE` + `ACTIVITY_RECOGNITION` | ✅ | Both declared and confirmed present in the merged manifest |
| A18 | **Exact-alarm runtime guard + boot-loop hardening** | ✅ | `AlarmScheduler` now checks `canScheduleExactAlarms()` and falls back to `setAndAllowWhileIdle()`; `rescheduleAllFromPrefs()` catches per entry. See "Bugs found and fixed" below. |
| A16 | Rewrite README to match the real architecture | ✅ | Now documents the fusion rule, pre-selection, honest accuracy figures, calibration requirement, and attribution |
| A17 | Test coverage for the data layer | ✅ | 26 tests via `sqflite_common_ffi`: FTS5 construction + hostile input, ranking, topology resolution, branch detection, plan assembly, run-time coverage, fingerprints |

### v2 — Underground

| ID | Task | Status | Notes |
|---|---|---|---|
| U1 | Route topology tables | ✅ | `Lines`, `RouteSequences` (with `branch_id`), `Branches`, `RunTimes`, `StationDepths`, `Fingerprints`. Created in both the Python builder and Dart `_migrate()`. |
| U2 | TfL route-sequence ingestion | ✅ | `--with-topology` flag; `orderedLineRoutes` → per-branch sequences; branch points derived as the last shared station; run times estimated from geometry (`source='estimate'`). Network failure degrades to empty tables, never a failed build. |
| U3 | Remove the disproven Wi-Fi identity model | ✅ | SSID equality matching replaced by `WifiPresenceDetector` — transit-operator SSID *presence* only. Identity comes from the route model. |
| U4 | Route pre-selection UI + branch prompts | ✅ | `route_select/` — line → direction → branch. Direction inferred (only one ordering works); branch asked only where topology says the line splits. Named blockers for no-topology / not-connected / no-sensors. |
| U5 | Barometer | ✅ | `TYPE_PRESSURE`, smoothed, **relative** to a captured surface baseline — absolute altitude is useless since weather moves sea-level pressure more than a platform's depth. |
| U6 | Accelerometer stop/start | ✅ | 50-sample windows, magnitude std-dev threshold, 3 consecutive windows to declare a stop. |
| U7 | Timing-prior gate | ✅ | Run-time window 0.55×–2.20× expected, absolute 30 s floor. |
| U8 | Three-way fusion arrival test | ✅ | D6 implemented exactly. Timing rejection costs **no** confidence — correctly rejecting a hold is the system working. |
| U9 | Confidence state machine + fail-safe | ✅ | Full match +0.10, partial −0.25, fail-safe below 0.55 fires one stop early with an honest message. Devices without a barometer start just above the threshold. |
| U10 | Expected-transition detection | 🟡 | Barometric network entry/exit, `onSurfaced()` → GPS handback, and `ServiceStateListener` all done (the last landed 2026-08-09 as I-18 — this row previously said otherwise and was stale). **Still missing: station-entrance geofencing from NaPTAN coordinates.** Note I-16: `onSurfaced()` starts GPS but does not stop the engine, so both subsystems can run with no arbitration. |
| U11 | Opportunistic Wi-Fi presence | ✅ | Throttle-aware cadence; forwards corroboration to the engine instead of firing alarms directly. |
| U12 | Cell-ID with staleness filter | ✅ | `CellObserver`, 5 s ceiling, LTE/NR/GSM/WCDMA. Indeterminable age treated as untrustworthy, not fresh — assuming freshness *is* the stale-cache bug. |
| U13 | Self-learned fingerprint database | ✅ | Schema + repo (record/match/prune). `minObservations` guard stops a single coincidental match relocating the user. Tested. |
| U14 | Multiple alarm stations per journey | 🟡 | GPS multi-target works; `JourneyPlan` supports multiple `isTarget` stations, but the engine stops at the first. |
| U15 | Cached TfL / Darwin snapshots via `WorkManager` | ⬜ | Not started. Delay-aware timing would tighten the U7 window. |
| U16 | Activity Transition API as secondary confirmer | ⬜ | Not started. Permission declared. Never for bus-vs-Tube (D8). |
| U17 | Privacy disclosure for BSSIDs / cell IDs | ✅ | In `AttributionCard` and README. |

### v3 — iOS

| ID | Task | Status | Notes |
|---|---|---|---|
| I1 | Everything iOS | ❌ | Deferred by D10. Needs a Mac and $99/yr. Reduced feature set: no Wi-Fi scanning, no granular cell reads, accelerometer + manual confirmation, clearly communicated lower reliability. |

### Field testing

| ID | Task | Status | Notes |
|---|---|---|---|
| F1 | Instrumented logging build | ✅ | `SensorLogger` — CSV per journey to `/Android/data/com.stopsnoozer.app/files/sensor_logs/`. Row types: pressure, accel window, **stop_candidate** (shows which fusion condition rejected each stop), external_fix, wifi_scan, cell (with age), service_state, ground_truth, note. |
| F2 | Ride Tooting Broadway → Euston on **both** Northern line branches | 🔴🧪 | **Requires you to physically ride the route — I cannot do this.** Everything needed to run it is built. Section 11 has the protocol. |

### Bugs found and fixed (not in the original plan)

| ID | Bug | Fix |
|---|---|---|
| A18a | `AlarmScheduler.scheduleAndSave()` called `setAlarmClock()` with no permission guard. `minSdk = 30`, and on API 31–32 the user can revoke `SCHEDULE_EXACT_ALARM` — `setAlarmClock()` then throws `SecurityException`. Thrown from `rescheduleAllFromPrefs()` on boot, this would abort the loop and **silently kill every stored alarm**. | Added `scheduleExactOrFallback()`: checks `canScheduleExactAlarms()` (API 31+), catches `SecurityException` for the revoke-between-check-and-call race, and falls back to `setAndAllowWhileIdle()` — inexact but still fires in Doze. |
| A18b | `rescheduleAllFromPrefs()` wrapped its whole loop in one `try/catch (JSONException)`, so a single malformed alarm record aborted every later alarm on boot. | Moved the catch inside the loop so one bad record is skipped, not fatal. |
| A19 | Bumping the schema version would have made `_isStale()` delete and re-extract `uk.db.gz` on **every launch** while never gaining the new tables — because the bundled asset is generated by a separate tooling step and still carried the old version. | Replaced version-triggered re-extraction with idempotent in-place migration (`_migrate()`). Re-extraction now happens only when the file is missing or unreadable. |
| A20 | Wi-Fi SSID matching fired an alarm on *any* SSID match. Since Underground SSIDs are identical network-wide, this would trigger at the first station with Wi-Fi, not the user's stop. | Presence detection now only feeds corroboration into the engine; with no journey plan active, a bare Wi-Fi hit no longer fires anything. |

**Follow-up:** when exact alarms are unavailable the app now degrades silently. Surfacing that in the System Health screen belongs with **A10** ("test your alarm"), since both answer the same user question — *will my alarm actually fire on this device?*

**Remaining work, in order:**

1. **Regenerate the asset** — `python tools/build_naptan_db.py --all`, then commit it. One command, and nothing underground works without it (I-02).
2. **F2 — the field test.** Blocks calibration of every `CALIBRATE` constant in `UndergroundEngine`. Only you can run it.
3. **Calibrate thresholds** from the F2 logs.
4. U14 / I-13 (multi-target underground — the engine stops at the first target), U10 completion (station-entrance geofence), I-16 (engine/GPS arbitration), U15 (`WorkManager` TfL cache), U16 (Activity Transition).
5. I-23 — native unit tests for the fusion engine. There is currently **no `src/test` or `src/androidTest` source set at all**; the most safety-critical code in the app has zero coverage.
6. Release signing keystore, then the Play Console submission checklist in Section 10.

~~A13~~ → ~~A15~~ → ~~A11~~ → ~~A12~~ → ~~A9/A10~~ → ~~A14~~ → ~~A16/A17~~ → ~~U1/U2~~ → ~~U3~~ → ~~U4~~ → ~~F1~~ → ~~U5–U9, U11–U13, U17~~ → **F2** → calibrate → U10/U14/U15/U16.

Rationale: A13 is a hard blocker and the riskiest refactor, so do it while the codebase is still small. U1/U2 unblock everything underground. F2 must precede U5–U9 because it sets the thresholds those tasks encode.

---

## 9. Blocked / Needs Field Testing

### Hard blockers

| Item | Blocker |
|---|---|
| ~~Any Play Store submission~~ | ~~`applicationId` is `com.example.stop_snoozer`~~ — **cleared 2026-08-08**, now `com.stopsnoozer.app` |
| iOS entirely | No Mac; Xcode is macOS-only |
| v2 threshold values (U5–U9) | No field data yet — F2 must run first |
| Release signing | **Gradle wired 2026-08-10.** `build.gradle.kts` loads `key.properties` behind a file-exists guard and uses a real `release` config when present; without it the build still succeeds but warns and falls back to debug signing. Blocked only on your keystore — see `PLAY_SUBMISSION.md` §1. |
| **Shipped database asset** | `assets/uk.db.gz` is **schema v2 with a single `StopPoints` table** (353,363 rows) — the topology tables are not merely empty, they are absent. Every underground journey falls back to GPS until `python tools/build_naptan_db.py --all` is run and the asset committed. This is issue I-02 and it gates F2. |

### Must be answered by field testing

1. **Does the barometer reliably distinguish the specific Northern line stations on this route?** Platform depths vary; some adjacent stations may be too similar to separate.
2. **How much of the route now has Boldyn coverage?** The rollout is active — Euston–Bank is being covered and Northern line tunnels were targeted for late summer 2026. This is a moving target.
3. **Does the accelerometer footprint discriminate the Kennington branch within one inter-station gap?** Research says ~90% at ≥3 stops; one gap is materially less certain.
4. **What does `getAllCellInfo()` actually return on the target device in a No Service tunnel?** Behaviour is vendor-dependent.

### Thresholds that would change the architecture

| If | Then |
|---|---|
| Boldyn coverage becomes continuous on the route | Promote Cell-ID toward primary, barometer to fallback |
| Barometric station-ID tests below ~80% | Lean harder on accelerometer footprint + timing prior |
| Branch discrimination exceeds ~95% | Suppress the Kennington prompt for regular commuters; keep as low-confidence fallback |
| TfL deploys network-wide BLE beacons | Promote BLE above Wi-Fi (no throttling) |

---

## 10. Compliance Checklist

### Android manifest

- [x] `android:foregroundServiceType="location"` on the tracking service
- [x] `FOREGROUND_SERVICE_LOCATION`
- [x] `USE_EXACT_ALARM` (+ `SCHEDULE_EXACT_ALARM` with `maxSdkVersion="32"`)
- [x] `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`
- [x] `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`
- [x] `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`, `RECEIVE_BOOT_COMPLETED`
- [x] **Not** `MODIFY_PHONE_STATE` — unavailable to third-party apps
- [x] `READ_PHONE_STATE` (ServiceState / SignalStrength callbacks) — A15
- [x] `ACTIVITY_RECOGNITION` — A15
- [x] Runtime guard: `AlarmManager.canScheduleExactAlarms()` before scheduling — A18a

- [x] `targetSdk` / `compileSdk` pinned to **36** — mandatory for new Play submissions from 31 Aug 2026
- [ ] Verify on real API 36 hardware that a `location` FGS may start from `BOOT_COMPLETED`. `BootReceiver` now survives a refusal, but resumed-after-reboot tracking depends on it (I-27)

### Google Play submission

Wording for every item below is written out in `PLAY_SUBMISSION.md`; what is
unticked is the *submitting*, not the drafting.

- [x] `applicationId` changed off `com.example.*` — now `com.stopsnoozer.app` (A13)
- [x] **Prominent in-app disclosure built** — `prominent_disclosure_dialog.dart`, shown in the runtime flow immediately before the OS prompt, and structurally unbypassable (I-04)
- [x] Release signing config wired (keystore still yours to generate)
- [ ] Background Location Permissions Declaration Form — text drafted, §2
- [ ] Demo video — ≤30 s, shot list in §3
- [ ] Data Safety form — answers drafted, §4. **Includes the postcodes.io transmission (I-49)**, which the on-device exemption does not cover
- [ ] Foreground service type declared in Play Console with description and user impact
- [ ] `USE_EXACT_ALARM` justified under the "dedicated alarm app" carve-out — declare by leading the store title/description with "alarm"

### Legal

- [x] OGL v3.0 attribution displayed in-app (required for NaPTAN) — `AttributionCard`, task A12. *(This box was left unticked in error when A12 completed on 2026-08-08.)*
- [x] Privacy disclosure for locally-recorded BSSIDs / cell IDs — task U17, `AttributionCard`. *(Also unticked in error.)*
- [x] **PECR reg. 6 consent** before reading Wi-Fi/cell identifiers, with withdrawal and erasure (I-36 / I-37). Note the legal test is *access to terminal equipment*, not transmission — "it never leaves the device" is not a defence
- [x] Privacy policy written — `docs/index.md`
- [ ] Privacy policy **hosted** and linked in Play Console *and* in-app — §5
- [ ] TfL attribution + app key registration; do not imply official TfL endorsement. Non-endorsement wording is in place; the **app key is still not registered** (I-30)

---

## 11. Field Test Protocol

**This is the one thing no public source can answer, and it decides every v2 threshold.**

Ride **Tooting Broadway → Euston on both Northern line branches** with an instrumented build (task F1), logging continuously:

| Log | Why |
|---|---|
| Barometric pressure (hPa, timestamped) | Establishes real station-depth signatures and noise floor — sets the U5 thresholds |
| Accelerometer (3-axis, high rate) | Stop/start signatures and per-segment vibration footprint — sets U6 |
| Wi-Fi scan results (SSID + BSSID + observed throttling) | Measures real scan cadence against platform dwell time; seeds the fingerprint DB |
| `getAllCellInfo()` **with `getTimestampMillis()`** | Reveals whether this device returns stale cached cells in No Service — validates D4's filter |
| `ServiceState` transitions | Marks true network entry/exit for U10 |
| Manual ground-truth markers | A tap at each real arrival, to score everything against |

**Capture both branches** — the Charing Cross and Bank routes — because branch discrimination (open question 3) cannot be assessed from one.

Also log at least one journey with a **mid-tunnel hold** if one occurs. That is the negative case D6 exists to reject, and it is the hardest thing to get right without real data.

---

## 12. Accuracy Expectations

| Scenario | Realistic reliability |
|---|---|
| Above-ground rail/bus (pure GPS geofencing) | **~98%+** |
| Underground, pre-selected route, fused sensors | **~85–90%** per journey, improving toward high-90s where Wi-Fi/cell hits exist at the destination |
| Underground, no pre-selection | ~85% |
| Barometer alone (Tokyo Metro study) | ~85% |
| Accelerometer alone at ≥3 stops (Royal Holloway) | ~90%, approaching 100% at ~4 continuous stops |

**Nothing in this category is 100%.** Transit's production underground prediction is right ~90% of the time. Citymapper asks users to confirm at the station. Google Maps disables transit routing offline entirely.

The above-ground case is the strongest product and covers a large share of UK commuting. It is also the part that already works.

---

## 13. Cost Reality

| Item | Cost |
|---|---|
| Cloud backend / hosting | **£0** — genuinely serverless |
| Map APIs | **£0** — no maps, text UI |
| NaPTAN / TfL / Translink data | **£0** — attribution required |
| TfL Unified API / Darwin OpenLDBWS | **£0** — free tiers |
| Google Play registration | **$25** one-time |
| Apple Developer Program | **$99/year** |
| Mac for iOS builds | Required — Xcode is macOS-only |

Operating cost is genuinely near zero. "Zero cost to build and ship" is not accurate.

---

## 14. Key Sources

**Platform documentation**
Android: Wi-Fi scanning throttling (4 scans / 2 min), foreground service types, exact alarm permissions, `TelephonyManager.getAllCellInfo()` caching, `CellInfo.getTimestampMillis()`, Activity Recognition / Transition API · AOSP: `ServiceStateTracker.java` (`LAST_CELL_INFO_LIST_MAX_AGE_MS = 2000`), `requestNetworkScan()` permissions · Apple: `CLLocationManager` region monitoring (20-region limit), TN3111 (no Wi-Fi scanning API), App Store Guidelines 2.5.4 / 5.1.1 / 5.1.5

**Academic research**
Nguyen et al. (2019), *Sensors* 19(19):4184, Royal Holloway — accelerometer footprint matching, London Underground, ~90% at ≥3 stops · Hua et al. (2016), IEEE TIFS — metro rider tracking, ~89% over 4 stations · Bonné (2014), ACM SIGSPATIAL — SubwayPS, 85.8% station detection · Watanabe et al. (2012), ISWC — "At Which Station Am I?", 85% barometric station ID, Tokyo Metro

**Industry**
Transit engineering blog (Oct 2024) — "No GPS required," the Mixer, 90% accuracy · Citymapper Get Off Alerts documentation · Snips — barometer-based station counting, >90%

**Transit data & coverage**
NaPTAN (DfT, OGL v3.0) — schema confirmed via `department-for-transport-public/Open_NaPTAN` · TfL Unified API — `Line/{id}/Route/Sequence/{direction}`, StopPoint data · TfL / Virgin Media — station Wi-Fi coverage (95–97%, no tunnels) · TfL / Boldyn Networks — 4G/5G rollout, 62 of 121 subterranean stations, Northern line tunnels targeted late summer 2026 · dontkillmyapp.com — OEM background-execution restrictions

---

## 15. Change Log

| Date | Change |
|---|---|
| 2026-08-08 | Document created. Consolidated the four-round technical review into a single reference. Audited the working tree at `58bca0f` and populated Section 8 from verified code state rather than from the plan's aspirations. Recorded three findings the review had not caught: the `applicationId` Play Store blocker, the absence of OGL attribution, and that the disproven Wi-Fi identity model is still live in `SnoozeTrackingService`. |
| 2026-08-08 | **v1 completed and v2 engine built.** A9, A10, A11, A12, A14, A16, A17 done; U1–U9, U11, U12, U13, U17 and F1 done; U10/U14 partial. New native classes: `UndergroundEngine`, `JourneyPlan`, `SensorLogger`, `CellObserver`, `WifiPresenceDetector`, `OemBatteryHelper`, `AlarmSelfTest`. New Dart: `RouteTopologyRepository`, `route_select/`, attribution/OEM/self-test cards. Schema → v4 with in-place migration (see below). 26 tests passing, `analyze` clean, debug APK builds. **All `CALIBRATE` thresholds in `UndergroundEngine` remain provisional until F2 runs.** |
| 2026-08-10 | **Play compliance (Stage 1 of the external research).** Prominent background-location disclosure built and made structurally unbypassable; PECR reg. 6 consent flow for Wi-Fi/cell reads, with withdrawal + erasure in System Health; `compileSdk`/`targetSdk` pinned to 36; release signing config wired behind a file-exists guard; `BootReceiver`'s FGS start hardened against the Android 15+ refusal. Privacy policy written (`docs/index.md`); declaration wording, video shot list and Data Safety answers written (`PLAY_SUBMISSION.md`). Closed I-04, I-35, I-36, I-37; advanced I-01, I-27. **Found:** the consent flag was per-instance and would have disabled learning permanently; withdrawing consent erased nothing; and the app's only runtime network call is `postcodes.io`, not TfL — logged as I-49, and the one thing the Data Safety on-device exemption does not cover. `analyze` clean, 26 tests pass, Java compiles. **None of the new UI has been exercised on a device.** |
| 2026-08-09 | **Real TfL data ingested.** Platform depths and inter-station run times from TfL FOI releases replaced the geometric estimates, with the 100 m tunnel-datum correction validated against four independently published figures (`tools/ingest_tfl_reference.py`, 13 tests). Depth re-keyed to `(stop_id, line_id)` — Bank is 20.5 m on the Central and 29.6 m on the Northern, so a station-level average would have been ~9 m wrong at exactly the interchanges that need precision. Closed 16 register items including I-05, I-06, I-07, I-08, I-18, I-33. Removed two UI lies (I-10 DND toggle, I-11 fake 16 KB check) rather than implementing them. **Corrected an arithmetic error** in the register: an earlier revision claimed "28 of 49 resolved" when the per-severity counts summed to 16. |
| 2026-08-08 | **A13 + A15 + A18 complete and verified.** `applicationId`/`namespace` → `com.stopsnoozer.app`; native packages moved with `git mv`; the 5 hardcoded launcher-alias strings in `MainActivity.switchLauncherIcon()` updated (these would have silently broken theme icon switching); iOS bundle id aligned; `ANDROID_CODE_EXPLAINED.md` references updated. Added `READ_PHONE_STATE` + `ACTIVITY_RECOGNITION`. Fixed two alarm-reliability bugs in `AlarmScheduler` found while checking the exact-alarm compliance item (A18a/A18b). Verified by clean debug APK build, merged-manifest inspection, `flutter analyze` (no issues), and `flutter test` (passing). Also noted the debug-keystore release-signing blocker. |

---

*This document supersedes `StopSnoozer_Master_Document.md` and the Round 1–2 understanding that preceded the "presence not identity" insight and the "No Service" clarification. The README at repo root still describes the disproven architecture and is scheduled for rewrite in task A16.*
