# StopSnoozer

> **Never Miss Your Stop Again.**

StopSnoozer is an offline-first geolocation alarm for UK public transport. It tracks a multi-leg journey and wakes you before your stop — above ground with GPS, and underground with sensor fusion where GPS cannot reach.

**Android-first. Offline data layer. No backend, no account, no map SDK fees.**

> Implementation status, task tracking, and the full technical rationale live in **[STOPSNOOZER_PLAN.md](STOPSNOOZER_PLAN.md)**. Read that before changing detection behaviour — it records what was tried, what was disproven, and why the current design is shaped this way.

---

## What actually works, and how well

Honesty here matters more than marketing: this is an alarm app, and users decide whether to trust it.

| Scenario | Mechanism | Realistic reliability |
|---|---|---|
| Above-ground rail, bus, tram | GPS geofencing | **~98%** |
| Underground, route pre-selected | Barometer + accelerometer + timing fusion | **~85–90%** |
| Underground, no barometer on device | Timing + accelerometer only | Lower; the app wakes you one stop early and says so |

Nothing in this category is 100%. Transit's production underground prediction is right about 90% of the time; Citymapper asks users to confirm at the station; Google Maps disables offline transit routing entirely. When StopSnoozer is unsure it wakes you **early with an honest message** rather than guessing silently.

---

## How underground tracking works

GPS is unavailable in deep tube, and the handset often reports literal **No Service** — so there is no cell signal to trilaterate either. What remains:

| Rank | Signal | Role |
|---|---|---|
| 1 | **Barometer** | Primary. ~0.12 hPa per metre, so a 20–30 m descent is 2.4–3.6 hPa — far above sensor noise. Gives station depth and network entry/exit. |
| 2 | **Accelerometer** | Stop/start detection from magnitude variance. |
| 3 | **Timing prior** | Known inter-station run times gate every candidate arrival. |
| 4 | **Wi-Fi presence** | Opportunistic corroboration. Throttled to 4 scans / 2 min by Android. |
| 5 | **Cell-ID** | Opportunistic only, with a mandatory staleness filter. |

### The rule that matters most

**Trains hold in tunnels.** An accelerometer full stop is therefore *not* evidence of arrival. An arrival is declared only when all three conditions agree:

```
arrival ⟺ accelerometer full stop
        ∧ barometric settle near the expected station depth
        ∧ elapsed time inside the expected run-time window
```

A mid-tunnel hold satisfies the first and fails the third. Dropping any one condition reintroduces over-counting, which is the failure that wakes people at the wrong station.

### Route pre-selection is mandatory

Most destinations are reachable by several routes, and telling them apart from sensors needs roughly three stops of evidence — long after a branch decision is made. So the route is resolved **before** the journey, while the user is above ground and online. Where a line genuinely splits (the Northern line at Kennington), the app asks. It does not guess.

Direction is *inferred*, not asked: only one ordering places your origin before your destination.

### Belief, not a counter

The engine maintains a confidence value. Partial matches still advance position but cost confidence; when confidence falls too low on approach to your stop, the alarm fires **one station early** with an explanation.

---

## Project layout

```
lib/
├── core/                      constants, theme, utils
├── data/
│   ├── models/                StopPoint, TripLeg, CommuteAlarm, …
│   ├── repositories/          stop points, trip groups, route topology, alarm history
│   └── services/              SQLite, GPS, platform channel
└── presentation/
    ├── splash/ dashboard/ search/ trip_config/ calendar/
    ├── route_select/          U4 — underground route pre-selection
    ├── alarm/                 full-screen alert + slide-to-dismiss
    └── system_health/         permissions, OEM battery, alarm self-test, attribution

android/app/src/main/java/com/stopsnoozer/app/
├── SnoozeTrackingService.java  foreground service — GPS + underground orchestration
├── UndergroundEngine.java      barometer/accelerometer/timing fusion + confidence
├── JourneyPlan.java            resolved route handed over from Dart
├── SensorLogger.java           CSV logging for field calibration
├── CellObserver.java           Cell-ID with mandatory staleness filter
├── WifiPresenceDetector.java   Wi-Fi presence (not identity)
├── AlarmScheduler.java         AlarmManager scheduling + exact-alarm guard
├── AlarmSelfTest.java          "test your alarm" end-to-end verification
├── OemBatteryHelper.java       manufacturer background-restriction deep links
├── CommuteAlarmReceiver.java   alarm wake-up entry point
└── BootReceiver.java           re-schedules alarms after reboot
```

Architecture is **MVVM with BLoC/Cubit** as the ViewModel layer, `go_router` for navigation.

The fusion engine lives in the **native foreground service**, not in Dart — Dart is not guaranteed to be alive in the background, and an alarm that depends on it would be an alarm that sometimes does not fire. Dart owns the topology database and resolves the route; native owns the sensors.

---

## Building the stop database

The app ships a compressed NaPTAN database at `assets/uk.db.gz`. To regenerate:

```bash
# Stops only
python tools/build_naptan_db.py

# Stops + TfL route topology (required for underground tracking)
python tools/build_naptan_db.py --with-topology
```

`--with-topology` fetches line route sequences from the TfL Unified API and derives branch points and estimated run times. **Without it the topology tables are created empty** and the app falls back to GPS geofencing — the route-selection screen says so explicitly rather than failing silently.

The script requires a Python whose bundled SQLite has FTS5; it aborts with a clear message otherwise.

> `SCHEMA_VERSION` in the script and `StopPointsDb._requiredVersion` in `lib/data/services/stop_points_db.dart` **must match**. An on-device database below that version is migrated in place, not re-extracted — see the note on `_migrate()` for why.

---

## Running

```bash
flutter pub get
flutter run
```

Without `assets/uk.db.gz` the app seeds ~430 development stops so search and navigation still work.

### Tests

```bash
flutter test
```

Data-layer tests run against real SQLite via `sqflite_common_ffi`, covering FTS5 query construction (including hostile input), search ranking, route topology resolution, branch detection, and fingerprint accumulation.

---

## Field calibration (required before trusting v2)

Every threshold in `UndergroundEngine` is marked `CALIBRATE` and is a literature-derived starting value, **not** a measured one. Platform depths, real run times, this device's accelerometer noise floor, and what `getAllCellInfo()` returns in a No Service tunnel cannot be looked up — they must be measured.

`SensorLogger` writes a CSV per journey to
`/Android/data/com.stopsnoozer.app/files/sensor_logs/`.

Ride the target route with logging enabled, on **both branches** of any split, and capture at least one run containing a mid-tunnel hold — that is the negative case the fusion test exists to reject. See the field-test protocol in the plan.

---

## Permissions

| Permission | Why |
|---|---|
| `ACCESS_FINE_LOCATION` + `ACCESS_BACKGROUND_LOCATION` | GPS geofencing while backgrounded |
| `FOREGROUND_SERVICE_LOCATION` | Persistent tracking service |
| `USE_EXACT_ALARM` | Scheduled commute alarms |
| `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT` | The alarm itself |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE` | Wi-Fi presence corroboration |
| `READ_PHONE_STATE` | `ServiceState` — detects Underground entry/exit |
| `ACTIVITY_RECOGNITION` | Low-power secondary motion confirmation |
| `RECEIVE_BOOT_COMPLETED` | Re-arm alarms after reboot |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Stop the OS killing tracking |

**Not** `MODIFY_PHONE_STATE` — it is signature/system-only and unavailable to Play Store apps. That restriction is precisely why Cell-ID is opportunistic rather than primary.

### Will alarms actually fire on your phone?

Several manufacturers (Xiaomi/MIUI, Huawei, Oppo, Vivo, …) run a proprietary process killer *in addition to* Android's battery optimisation, and granting the standard exemption does not stop it. **Settings → Alarm Delivery Verification** schedules a real alarm through the full pipeline and reports whether the OS delivered it, with a deep link into the manufacturer's own settings when it fails.

---

## Privacy

All data — stops, journeys, alarms, fingerprints — stays on the device. There is no account, no backend, and nothing is uploaded.

To improve underground detection the app may record nearby Wi-Fi BSSIDs and mobile cell identifiers alongside confirmed stations. These are stored locally, never transmitted, and aged out over time.

---

## Attribution

Contains public sector information licensed under the **Open Government Licence v3.0**.

Stop locations derive from **NaPTAN** (UK Department for Transport). Line and route data from **TfL Open Data**; contains OS data © Crown copyright and database rights.

StopSnoozer is an independent app and is **not** affiliated with, endorsed by, or operated by Transport for London.

---

## Licence

Private — all rights reserved.
