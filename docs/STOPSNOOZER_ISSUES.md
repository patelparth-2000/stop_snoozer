# StopSnoozer — Issues, Risks & Concerns Register

**Every known problem with this app, current and anticipated.**

| | |
|---|---|
| **Created** | 2026-08-08 |
| **Last updated** | 2026-08-10 |
| **Scope** | Verified against the working tree — not a generic checklist |
| **Companion docs** | [STOPSNOOZER_PLAN.md](STOPSNOOZER_PLAN.md) · [STOP_SNOOZER_CONTINUATION.md](STOP_SNOOZER_CONTINUATION.md) · [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) |
| **Status** | **21 of 50 resolved, 29 open** (2026-08-10). Remaining work is concentrated in the field test, engine correctness, and product gaps. |

> **Correction (2026-08-09):** an earlier revision of this file claimed "28 of 49
> resolved". That was an arithmetic error on my part — the per-severity counts
> summed to 16, not 28. Corrected throughout; see the summary table.

Items marked **[verified]** were confirmed by reading the code during this audit.
Items marked **[risk]** are anticipated rather than observed.

**Severity**

| | Meaning |
|---|---|
| **P0** | Blocks shipping, or the app lies to the user about whether it will wake them |
| **P1** | Real defect a user will hit; degrades trust |
| **P2** | Incomplete work, dead code, or maintenance debt |
| **P3** | Future concern, watch item, or product gap |

---

## Resolution log — 2026-08-10

External research on Play policy, UK privacy law and barometric altimetry.
Acting on it closed **5 items**, advanced two more, and surfaced one new one.
Everything here is Stage 1 (release blockers); Stages 2–4 of that research —
the fusion-engine extraction, absolute platform altitudes, drift compensation
and the correctness fixes — are **not** done and remain open below.

| Item | Resolution |
|---|---|
| I-04 | Prominent disclosure built and, critically, made *unbypassable*: `SplashCubit.requestPermissions()` takes the disclosure as a parameter, so the background-location request is unreachable unless it returned `true`. Declaration wording, video shot list and Data Safety answers written up in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) |
| I-27 | `compileSdk`/`targetSdk` pinned to **36** (mandatory for new Play submissions from 31 Aug 2026) rather than inherited from the Flutter SDK. `BootReceiver`'s foreground-service start hardened — see below |
| I-35 | Privacy policy written at `docs/index.md`, structured for GitHub Pages. Names the developer, discloses background location specifically, covers sensors and radio identifiers, states retention and deletion |
| I-36 | Consent UI built. `ProminentDisclosureDialog.showRadioScanConsent` at first journey setup; answer persisted; consent restored at startup **before** anything can observe a radio identifier |
| I-37 | Erasure control shipped: System Health → Privacy & Learned Data. Withdrawing consent also wipes what was learned under it |

Advanced but not closed:

| Item | State |
|---|---|
| I-01 | Gradle signing config wired with a file-exists guard, `key.properties.example` added, `key.properties`/`*.jks` git-ignored. **Still needs your keystore** — a missing `key.properties` now logs a warning and falls back to debug signing so fresh checkouts still build |
| I-29 | Deliberately **not** changed. `getExternalFilesDir()` is what makes `adb pull` work, and F2 is the next task. Moving to `getFilesDir()` is a pre-release gate, not a now-fix |

Also found while implementing:

- **The consent flag was per-instance, which would have made learning
  permanently dead.** `RouteTopologyRepository` is constructed ad hoc at several
  call sites (`RouteSelectCubit`, `DatabaseInitHandler`, …), so an instance
  field meant every freshly-built repository had `_consentGranted == false` and
  every write silently no-opped — failing safe, but also failing forever. Now a
  static loaded once at startup. This is the same class of bug as I-05: a
  mechanism that exists, is correct in isolation, and never runs.

- **Withdrawing consent did not erase anything.** A toggle that only flips a
  flag leaves data gathered under the old consent sitting in the database, which
  is not what withdrawal means under UK GDPR. `setFingerprintConsent(false)` now
  deletes the fingerprints as part of the withdrawal.

- **`BootReceiver` could crash the app on every boot.** Android 15 began
  refusing foreground-service starts from `BOOT_COMPLETED` for a set of service
  types that has grown since, and a refusal arrives as an exception. From a boot
  receiver that is a crash at every power-on. Now wrapped, so a refusal degrades
  to "tracking resumes when the user next opens the app". The user's alarms are
  unaffected either way — they are re-armed via `setAlarmClock()` on a separate
  path. **Whether `location` is actually in the restricted set at API 36 is
  unverified on hardware** — see I-27.

- **The research's Data Safety advice missed this app's only network call.** It
  reasoned about TfL API requests, but nothing calls TfL at runtime — U15 was
  never started. The actual off-device transmission is
  `PostcodeGeocoder` sending user-typed postcodes to `api.postcodes.io`. Logged
  as I-49; the on-device exemption does not cover it.

---

## Resolution log — 2026-08-09

External research supplied two authoritative TfL datasets and settled several
platform questions. Acting on it closed **16 items**. What changed:

| Item | Resolution |
|---|---|
| I-05 | `CellObserver.observeFresh()` now polled on the Wi-Fi cadence; registered cells feed corroboration |
| I-06 | `SensorLogger` ground-truth + `ServiceState` wired; `FieldTestPanel` gives a large one-handed marker button |
| I-07 | Replaced blind advance with `corroborateArrival()` — timing-gated and debounced per index |
| I-08 | Belief state checkpointed with a monotonic/wall-clock pair; reboot detected and belief invalidated |
| I-10 | DND toggle **removed**. `USAGE_ALARM` audio already passes DND by default — the toggle was both fake and unnecessary |
| I-11 | Fake button removed; real check in `tools/check_16kb_alignment.sh` |
| I-12 | `DbStats` queries live values; also surfaces whether topology is installed |
| I-18 | `ServiceStateListener` added, completing the cellular half of U10 |
| I-20 | `StationDepths` populated from TfL FOI data — **269/269 stations, 314 (stop,line) pairs** |
| I-21 | `RunTimes` replaced with real TfL figures — **736 legs**; Kennington→Oval is 95 s, not the 120 s guess |
| I-25 | Rate cut 50→20 Hz, 5 s sensor batching, GPS stopped on submersion |
| I-28 | Verified empirically: 10 bundled `.so` files, all 16 KB aligned |
| I-33 | `pruneFingerprints()` now actually called, at startup |
| I-36 | Fingerprint writes gated behind explicit consent at the single write path |
| I-37 | `deleteAllFingerprints()` added |
| I-46 | Timing gate made asymmetric: floor 0.85× unimpeded, ceiling 3.0× peak |

Also fixed, found while implementing:

- **The Circle line would have had no barometer at all.** The depth spreadsheet
  has no Circle column — 66 run-time legs, zero depth rows — so the strict
  `(stop_id, line_id)` join returned NULL for every Circle station and silently
  disabled the barometric half of the fusion test. 33 of its 34 stations do have
  a depth under District/Met/H&C, so `buildPlan` now falls back to the mean of
  the station's other platforms, flags it as `depthIsFallback`, and the engine
  widens its tolerance 1.6× to account for interchange variation.

- **Depth is per-platform, not per-station.** Bank is 20.5 m on the Central line
  and 29.6 m on the Northern. `StationDepths` was re-keyed to
  `(stop_id, line_id)`; a station-level average would have been ~9 m wrong at
  precisely the interchanges where the barometer needs precision. Schema → v5.
- **A trap in the depth spreadsheet.** Column 23 is an unlabelled cross-line
  "Mean". Forward-filling the last line header attributes it to Waterloo & City,
  inventing depths for ~270 stations that line does not serve. Each line header
  now owns exactly its own two columns.
- **My own 16 KB script was initially wrong.** `unzip -Z1 "$APK" 'lib/*'`
  silently matched nothing, so it reported "no native libraries" for an APK
  containing ten — the same falsely-reassuring failure as the button it replaced.
  Now lists all entries and filters in-script, and refuses to report a pass if
  `zipalign` is unavailable.
- **`max(unimpeded, peak)` was the wrong prior.** It inflated the timing floor
  (Oval→Kennington 102 s → 168 s), which would reject legitimate fast off-peak
  runs. Both values are now stored separately and used for opposite bounds.

---

## The five to fix first

1. **[I-02] Regenerate the asset** with `--all` so topology and reference data
   actually ship. One command, and nothing underground works without it.
2. **[I-03 / F2] Run the field test.** Everything needed now exists — real
   depths, real run times, working logging, ground-truth markers. Only physical
   access to the route is missing.
3. **[I-01] Generate the release keystore.** Gradle is wired; only the `.jks`
   and `key.properties` are missing. See [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) §1.
4. **[I-13] Engine stops at the first alarm target** — multi-leg is a headline
   feature and only the first leg alarms.
5. **[I-23] Native unit tests** for the fusion engine — still the least-tested,
   most safety-critical code in the app.

Then the Play paperwork itself (§2–§5 of the submission pack): the wording is
written, the submitting is not done.

---

## 1. Shipping blockers

### I-01 · P0 · Release signing needs a keystore — *Gradle side done 2026-08-10*
`android/app/build.gradle.kts` now loads `key.properties` behind a file-exists guard and uses a real `release` signing config when it is present. Without it the build still succeeds (so a fresh checkout is not broken) but logs a warning and falls back to debug signing.
**Blocked on:** your keystore. I cannot generate a signing identity for you. Command and Play App Signing guidance in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) §1.

### I-02 · P0 · Shipped database has no route topology **[verified — re-checked 2026-08-10]**
`assets/uk.db.gz` predates the topology work. Inspected directly: the asset is **schema `user_version = 2` and contains exactly one table, `StopPoints` (353,363 rows)**. The topology tables are not merely empty — they are absent from the asset entirely, and only come into existence when Dart's `_migrate()` creates them on first launch. Route pre-selection therefore shows *"Route data not installed"* and every underground journey silently falls back to GPS.
An earlier revision of this entry said "the tables exist but are empty", which is true of the *runtime* database after migration but not of the shipped asset. The distinction matters: nothing ships the depths and run times ingested on 2026-08-09 until this is regenerated.
**Fix:** `python tools/build_naptan_db.py --all` (not `--with-topology` alone — that omits the FOI depths and run times), then commit the regenerated asset.

### I-03 · P0 · Every fusion threshold is unvalidated **[verified]**
All constants marked `CALIBRATE` in `UndergroundEngine.java` are literature-derived starting values. The engine has never seen real Tube data. Shipping underground detection on these numbers means shipping an alarm whose accuracy is genuinely unknown.
**Blocked on:** the F2 field test — physical access to the route.

### I-04 · P0 · ~~Play Console submission artifacts not prepared~~ — **RESOLVED 2026-08-10** (code) / pending submission
Prominent disclosure built at `lib/presentation/shared/widgets/prominent_disclosure_dialog.dart` and wired so the OS background-location prompt is *unreachable* unless it was accepted — that ordering is the single most common rejection ("BACKGROUND_LOCATION permission user consent/runtime requested before Prominent Disclosure"), so it is enforced structurally rather than by convention. The `location` FGS type and the exact-alarm/full-screen-intent permissions were already declared correctly.
Declaration wording, the ≤30 s video shot list, and the Data Safety answers are in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md). **What remains is submitting them**, which needs a Play Console account.

---

## 2. Correctness defects

### I-05 · P0 · `CellObserver` is constructed but never polled **[verified]**
`SnoozeTrackingService.java` creates `cellObserver` in `startUndergroundTracking()` and nulls it in `stopUndergroundTracking()`. `observeFresh()` has **no callers**.
Consequence: U12 is marked complete but contributes nothing at runtime. The staleness filter — the entire reason the class exists — never executes.
**Fix:** poll on a throttled cadence around expected arrival windows, and feed accepted observations to `UndergroundEngine.confirmPosition()` via fingerprint match.

### I-06 · P0 · Ground-truth and service-state logging are unwired **[verified]**
`SensorLogger.logGroundTruth()`, `logServiceState()` and `logNote()` have **no callers anywhere**.
Consequence: the field-test logs will contain sensor traces with nothing to score them against. You cannot tell a correctly-detected arrival from a lucky one, which defeats the purpose of F1. This makes I-03 unfixable until resolved.
**Fix:** a debug UI with a large "I am arriving now" button, plus a `PhoneStateListener`/`TelephonyCallback` for service state.

### I-07 · P1 · Wi-Fi presence advances position unconditionally **[verified]**
`SnoozeTrackingService.evaluateWifiResults()` calls
`undergroundEngine.confirmPosition(undergroundEngine.currentIndex() + 1, "wifi_presence")`
on *any* station-grade SSID sighting — and `confirmPosition()` resets confidence to 1.0.
Consequence: two scans at the same platform advance the index twice. Wi-Fi bleeding through a tunnel near a station does the same. This can walk the tracker ahead of reality **and** mask the error by restoring full confidence, defeating the fail-safe.
**Fix:** debounce per station (advance at most once per arrival window), require the timing gate to agree, and prefer a fingerprint match over blind increment.

### I-08 · P1 · Underground belief state is lost on process restart **[verified]**
`resumeFromPrefs()` restarts the engine from the plan's `startIndex`. The in-memory `currentIndex` and confidence are gone.
Consequence: after an OEM kill mid-journey, the app believes the user is back at the boarding station and will not alarm at the right place. Currently mitigated only by the fail-safe firing early — which will not trigger, because confidence resets to full.
**Fix:** persist `currentIndex`, confidence and `lastArrivalElapsedMs` on every advance; on resume, restore them *and* apply a confidence penalty for the gap.

### I-09 · P1 · Per-leg alarm style ignored in multi-target mode **[verified]**
`startGeofence`/`startHybridSensing` accept `alarmStyle`, but `updateTrackingTargets` does not send it and native `TargetStop` has no such field. Every leg falls back to the global setting.
Consequence: a user who sets a gentle alert for one leg and a loud one for another gets the same alert for both.

### I-10 · P1 · DND-bypass toggle is cosmetic **[verified]**
`system_health_viewmodel.dart` — `toggleDndBypass()` only flips local state. No `NotificationManager.INTERRUPTION_FILTER` policy request, no `ACCESS_NOTIFICATION_POLICY` permission declared.
Consequence: the UI advertises that alarms will pierce Do Not Disturb. They will not. For an alarm app this is the worst class of bug — a promise the user relies on while asleep.
**Fix:** either implement it (request `ACCESS_NOTIFICATION_POLICY`, set channel `setBypassDnd(true)`) or remove the toggle. Do not leave it as-is.

### I-11 · P1 · "Verify 16 KB Page Size Alignment" button is theatre **[verified]**
`system_health_screen.dart` — `_verify()` waits 1.2 s and then unconditionally reports success. It checks nothing.
Consequence: a compliance claim manufactured out of a delay. Remove it or make it read `PRAGMA page_size`.

### I-12 · P1 · Storage statistics are hardcoded **[verified]**
`system_health_screen.dart` shows literal `'16.5 MB'`, `'353,363 nodes'`, `'16,384 B'`. These do not reflect the actual database and will be wrong the moment the asset is regenerated (which I-02 requires).
**Fix:** query `COUNT(*)`, the file size, and `PRAGMA page_size`.

### I-13 · P1 · Engine stops at the first alarm target **[verified]**
`UndergroundEngine.advanceTo()` sets `finished = true` on the first `isAlarmTarget`. `JourneyPlan` supports several, and multi-leg journeys are a headline feature.
Consequence: only the first underground leg of a multi-leg trip alarms.

### I-14 · P2 · Early-nudge state is not persisted **[verified]**
`nudgedStopIds` is an in-memory `HashSet`. After a service restart the nudge can fire a second time for the same stop.

### I-15 · P2 · Self-test can leave stale pending-alarm prefs **[verified]**
`ACTION_SELF_TEST_FIRE` routes through `triggerAlarm()`, which writes `pending_alarm_stop_id`/`stop_name`. If the user dismisses via notification rather than opening the app, Dart's `checkPendingAlarm()` may later surface a phantom "Alarm Test" arrival.

### I-16 · P2 · `onSurfaced()` does not stop the engine **[verified]**
On surfacing, GPS is started but the engine keeps running. Both can now fire for the same stop.
Currently benign because `alarmFired` guards a double alarm, but the two subsystems disagree about position with no arbitration.

### I-17 · P2 · No user-facing way to end underground tracking
`route_select` starts tracking; nothing stops it short of the generic "Stop Tracking" notification action. There is no journey-complete state and no UI reflecting live engine position.

---

## 3. Incomplete work and dead code

### I-18 · P2 · U10 partially wired **[verified]**
Barometric entry/exit and GPS handback work. Missing: station-entrance geofencing from NaPTAN coordinates, and `ServiceStateListener` for cellular loss/reacquisition. The expected-transition design is therefore only half-implemented.

### I-19 · P2 · Legacy Wi-Fi identity code paths remain **[verified — re-counted 2026-08-10]**
`ACTION_START_WIFI`, `targetSsid`, `PREF_TRACKING_SSID`, `TargetStop.ssid`, the `wifi_ssid` column, and `wifiSsid` on `StopPoint` / `SavedLocation` / `CommuteAlarm` all survive.
**An earlier revision said "11 references". The real figure is 536 matching lines across 17 files** — the bulk (455) is `lib/data/services/stop_points_db.dart`, because every row of the ~430-stop dev seed carries a `wifi_ssid` value. Excluding the seed data it is roughly 80 sites, still an order of magnitude more than recorded.
More importantly there is still a **live query** on the disproven model: `stop_points_db.dart:435` does `where: 'wifi_ssid = ?'`. This is not purely dead scaffolding.
Concern: a future contributor can reasonably assume it works. Removing it also lets unused permissions come out of the manifest, which reduces Play scrutiny. Marked for removal, not yet removed.

### I-20 · P2 · `StationDepths` is empty with no automated source **[verified]**
No open dataset publishes platform depths. Every station without one disables the barometric half of the fusion test there. Handled correctly (lower confidence) but materially weakens accuracy.
**Fix:** derive from F2 barometric logs, station by station.

### I-21 · P2 · Run times are geometric estimates **[verified]**
`_estimate_run_time()` uses straight-line distance × 1.25 ÷ 9.2 m/s. Verified against the fixture: Oval→Kennington estimates 120 s where reality is nearer 90 s.
Consequence: the timing gate — the condition that rejects tunnel holds — is calibrated against fiction. Widen tolerances or replace with measured values.

### I-22 · P2 · U15 and U16 not started
No `WorkManager` TfL/Darwin caching (so no delay-aware timing), no Activity Transition API confirmation.

### I-23 · P2 · No tests for any native code **[verified]**
26 Dart tests exist; `UndergroundEngine`, the fusion rule, the confidence machine, `CellObserver`'s staleness filter and `AlarmScheduler` have **zero** coverage. The most safety-critical logic in the app is the least tested.
**Fix:** the fusion logic is pure arithmetic over injected samples — extract it behind an interface and unit-test it with synthetic pressure/accel traces, including a simulated tunnel hold.

### I-24 · P2 · Widget test is trivial
`widget_test.dart` asserts the app renders. No screen has behavioural coverage.

---

## 4. Platform and OS risks

### I-25 · P1 · [risk] Battery cost of the underground engine is unmeasured
`SENSOR_DELAY_GAME` (~50 Hz) accelerometer plus a foreground service plus GPS in parallel, for an entire commute. Never profiled.
Concern: if this drains meaningfully, users disable the app and the accuracy work is irrelevant. Also invites OEM killers, worsening I-26.
**Fix:** profile a full journey; consider dropping to `SENSOR_DELAY_UI` and only raising the rate inside expected arrival windows.

### I-26 · P1 · OEM background killers
Mitigated by A9/A10 but not solved — it cannot be solved from inside the app. Some devices will kill tracking whatever we do. The self-test at least makes it visible.

### I-27 · P2 · [risk] Android version drift — *partly addressed 2026-08-10*
Background location, exact alarms and foreground service types have tightened every release since Android 12. Assume further restriction. `USE_EXACT_ALARM` depends on Play's "dedicated alarm app" carve-out continuing to accept this app's justification — StopSnoozer qualifies on its face, and the store listing should lead with "alarm" so a reviewer sees that without looking.
`compileSdk`/`targetSdk` are now pinned to **36** rather than inherited from the Flutter SDK, and `BootReceiver` no longer crashes if the OS refuses its foreground-service start.
**Still open, and the reason this stays on the list:** whether a `location`-type FGS may be started from `BOOT_COMPLETED` at API 36 has **not been verified on hardware**. Test on a real API 36 device and watch logcat for `ForegroundServiceStartNotAllowedException`. Alarms do not depend on that path — they are re-armed via `setAlarmClock()` — but resumed tracking after a reboot does.

### I-28 · P2 · [risk] 16 KB page-size requirement
Android 15+ requires 16 KB page alignment for native libraries. The app ships no custom `.so`, but `play-services-location` and sqflite do. Verify at release build time rather than assuming.

### I-29 · P2 · Sensor logs use app-external storage **[verified]**
`getExternalFilesDir()` — fine for `adb pull`, but the logs contain a movement trace and are readable by anything with access to the device's storage. Acceptable for a field-test build; reconsider before shipping logging to users.

---

## 5. External dependencies

### I-30 · P2 · TfL API used without an app key **[verified]**
`build_naptan_db.py` calls the Unified API unauthenticated. Fine at build-time volume, but rate limits apply and the terms expect registration for sustained use.

### I-31 · P2 · [risk] TfL response shape is a hard dependency
Topology ingestion relies on `orderedLineRoutes[].naptanIds`. A schema change silently produces empty topology — the code degrades gracefully but you would not notice until someone reports GPS fallback.
**Fix:** assert a minimum row count post-ingest and fail the build if it is not met.

### I-32 · P3 · [risk] Boldyn 4G/5G rollout is a moving target
Northern line tunnel coverage was targeted for late summer 2026. If coverage becomes continuous, Cell-ID should be promoted toward primary and the architecture rebalanced. Re-evaluate after F2.

### I-33 · P3 · [risk] Wi-Fi infrastructure churn invalidates fingerprints
TfL is migrating Virgin Media → Boldyn. BSSIDs will change wholesale. `pruneFingerprints()` exists (120-day default) but has **no caller** — nothing ages the data out yet.

### I-34 · P3 · NaPTAN data goes stale with no update path
The database is baked into the APK. Stops close, move and get renamed. Today the only refresh is an app update.

---

## 6. Legal, privacy and compliance

### I-35 · P1 · ~~No privacy policy document exists~~ — **RESOLVED 2026-08-10** (written) / pending hosting
Written at `docs/index.md`, structured so GitHub Pages can serve it from `main` → `/docs` at `https://patelparth-2000.github.io/stop-snoozer/`. Names the developer and a contact address, discloses **background** location specifically, covers the sensor and radio data, and states retention and deletion — the four things a reviewer checks for.
**What remains:** enable Pages, then put the URL in Play Console *and* in the app. Steps in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) §5.

### I-36 · P1 · ~~BSSID/cell collection consent under UK GDPR~~ — **RESOLVED 2026-08-10**
The earlier note here reasoned from UK GDPR and treated "device-local, never transmitted" as close to sufficient. That is the wrong test. **PECR reg. 6 governs the act of gaining access to information stored in terminal equipment, not its onward transmission** — reading a Wi-Fi scan engages it whether or not anything is sent. Consent was therefore required, not merely advisable.
Now: `ProminentDisclosureDialog.showRadioScanConsent` at first journey setup, answer persisted, restored at startup *before* anything can observe an identifier, and declining leaves the app fully functional (which is what makes the consent freely given). The consent flag was also moved from a per-instance field to a static — see the 2026-08-10 log for why it would otherwise never have worked.

### I-37 · P2 · ~~Fingerprint data has no user-facing delete~~ — **RESOLVED 2026-08-10**
System Health → Privacy & Learned Data shows the learned-identifier count, an erase button, and a consent toggle. Withdrawing consent erases what was gathered under it, rather than only flipping the flag.

### I-49 · P2 · Postcode lookup transmits off-device and must be declared **[verified]**
`lib/data/services/postcode_geocoder.dart` sends a user-typed UK postcode to `api.postcodes.io`. This is the app's **only** runtime network call — nothing contacts TfL at runtime, because U15 was never started (I-22).
It matters because the Data Safety "on-device processing" exemption explicitly does not cover data that leaves the device, so answering "no data collected" across the board would be a misdeclaration — and a Data Safety answer that contradicts the privacy policy is itself an enforcement trigger.
Recommended declaration (Location → Approximate location; collected + shared; App functionality; optional; processed ephemerally) is in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md) §4, and the policy at `docs/index.md` already describes it.
Note the search path matters: searching by **stop name** runs entirely against the bundled offline database and makes no request. Only a postcode-shaped query triggers this.

### I-38 · P2 · TfL attribution obligations
Non-endorsement wording is in place. Not yet verified: TfL's trademark rules on using line names and colours, if the UI ever adopts official line branding.

---

## 7. Product gaps

### I-39 · P3 · iOS unsupported
Deferred by decision D10. Needs a Mac and $99/yr. The Android detection stack does not port: no Wi-Fi scanning, no granular cell reads, and background CoreMotion dead-reckoning is not sanctioned by Apple. Expect a materially weaker feature set.

### I-40 · P3 · No cloud sync — device migration loses everything
Saved stops, alarms, trip groups and learned fingerprints are local-only. A new phone starts from nothing. Conflicts with the zero-cost goal; a local export/import file would be a cheap middle ground.

### I-41 · P3 · No light mode
Five dark themes; no light or system-following variant.

### I-42 · P3 · Accessibility not assessed
No audit of screen-reader labels, contrast ratios, or scaling. The slide-to-dismiss alarm gesture in particular may be difficult for motor-impaired users, and there is no alternative dismissal path.

### I-43 · P3 · English-only, UK-only
No localisation. Data model and detection assumptions are UK-specific.

### I-44 · P3 · No crash reporting or diagnostics
Nothing reports failures from the field. Given how device-dependent the alarm pipeline is (I-26), you will not learn why alarms fail for real users.

### I-45 · P3 · No alarm history
No record of fired/missed alarms, which would be the cheapest possible signal of real-world accuracy.

---

## 8. Design tensions worth revisiting

### I-46 · Timing rejection costs no confidence — deliberate, but unproven
`onFullStopDetected()` returns without penalty when the timing gate rejects a stop, on the reasoning that correctly rejecting a tunnel hold is the system working.
Tension: if run-time priors are wrong (see I-21), the gate will reject *real* arrivals with no confidence cost, so the tracker falls behind while still reporting high confidence — the fail-safe never fires. This coupling makes I-21 more dangerous than it first appears.
**Watch for this specifically in F2 logs.**

### I-47 · Barometric baseline is captured once, at first reading
`surfacePressureHpa` is set on the first sample and never re-established. Weather drift over a long journey, or starting the app already underground, corrupts every depth reading thereafter.
**Fix:** re-baseline on each confirmed surface transition; refuse depth matching if the baseline was captured below ground.

### I-48 · Absolute vs relative depth
Depth is relative to the boarding surface, but `StationDepths` will be absolute depth below ground level — and ground level itself varies across London. Matching one against the other assumes the boarding station's surface is a good reference for the whole line. Over a long route this drifts.

---

## Summary by severity

| Severity | Total | Resolved | Open |
|---|---|---|---|
| **P0** | 6 | 3 | 3 |
| **P1** | 12 | 9 | 3 |
| **P2** | 19 | 8 | 11 |
| **P3** | 10 | 1 | 9 |
| **Design tensions** | 3 | 1 | 2 |
| **Total** | **50** | **21** | **29** |

Resolved: I-04, I-05, I-06, I-07, I-08, I-10, I-11, I-12, I-18, I-20, I-21,
I-25, I-28, I-33, I-35, I-36, I-37, I-46 — plus I-27 in part (SDK pinned, boot
path hardened; API 36 FGS behaviour still unverified on hardware) and I-01 in
part (Gradle wired; keystore outstanding).

Counts changed from 49 to 50 with the addition of I-49.

**Read the P1 column with care.** Nine of twelve resolved looks close to done,
but every one of the three remaining P0s is either a field test the code cannot
substitute for (I-03), a one-command asset regeneration (I-02), or a keystore
only you can generate (I-01). None of them get closer by writing more code.

---

## OPEN ISSUES — ordered by priority

### 🔴 HIGH — blocks release, or the app is wrong in a way users feel

| # | ID | Issue | Effort |
|---|---|---|---|
| 1 | **I-02** | **Shipped asset is still the old v2 build.** None of the new depth/run-time/topology data is in the app. Underground tracking shows "Route data not installed" and falls back to GPS. | One command: `python tools/build_naptan_db.py --all` |
| 2 | **I-13** | **Engine stops at the first alarm target.** `finished = true` fires on the first `isTarget`, so only the first underground leg of a multi-leg journey alarms — and multi-leg is a headline feature. | Small |
| 3 | **I-03** | **Fusion thresholds still uncalibrated.** Everything needed now exists; no part of the engine has met a train. | Needs F2 |
| 4 | **I-01** | **No release keystore.** Gradle is wired and git-ignored; the `.jks` and `key.properties` are missing, so release builds are still debug-signed. | Needs your keystore |
| 5 | **I-23** | **Zero tests for the fusion engine.** The most safety-critical code in the app is the least tested; the arithmetic is pure and injectable, so this is cheap to fix. | Medium |
| 6 | **Play paperwork** | Declaration form, ≤30 s video, Data Safety answers, Pages hosting. All wording is written in [PLAY_SUBMISSION.md](PLAY_SUBMISSION.md); the submitting is not done. | Needs Play Console |

### 🟠 MEDIUM — real defects and debt, not release-blocking

| # | ID | Issue |
|---|---|---|
| 9 | **I-16** | `onSurfaced()` starts GPS but never stops the engine — both subsystems then run with no arbitration over position. Currently masked by the `alarmFired` guard. |
| 10 | **I-47** | Barometric baseline is captured once at first reading and never re-established. Starting the app already underground, or weather drift on a long journey, corrupts every depth reading after it. |
| 11 | **I-48** | Depth is measured *relative* to the boarding surface, but `StationDepths` is *absolute* below street level — and street level varies across London. Drifts over a long route. |
| 12 | **I-09** | Per-leg alarm style ignored in multi-target mode: `TargetStop` has no style field, so every leg uses the global setting. |
| 13 | **I-17** | No way to end underground tracking from the UI, and no journey-complete state. |
| 14 | **I-19** | Legacy Wi-Fi identity scaffolding still present (`ACTION_START_WIFI`, `targetSsid`, `wifi_ssid` column — 11 references). A future contributor could reasonably assume it works. |
| 15 | **I-14** | Early-nudge `nudgedStopIds` is in-memory only; a service restart can re-fire the nudge for the same stop. |
| 16 | **I-15** | Self-test can leave `pending_alarm_*` prefs behind, surfacing a phantom "Alarm Test" arrival later. |
| 17 | **I-31** | TfL topology ingestion depends on `orderedLineRoutes[].naptanIds`; a schema change silently yields empty topology. Needs a minimum-row assertion. |
| 18 | **I-30** | TfL API called without an app key — fine at build volume, but rate-limited and against the spirit of their terms. Registration is still free; the 500 req/min product covers this comfortably. |
| 18b | **I-49** | Postcode lookup transmits to `api.postcodes.io` — the app's only runtime network call, and the one thing the Data Safety on-device exemption does not cover. |
| 19 | **I-26** | OEM background killers. Mitigated by A9/A10, not solvable from inside the app. |
| 20 | **I-29** | Sensor logs sit in app-external storage — fine for field testing, reconsider before shipping logging to users. |
| 21 | **I-24** | Widget tests still assert only that the app renders. |
| 22 | **I-22** | U15 (`WorkManager` TfL/Darwin cache) and U16 (Activity Transition API) not started. |

### 🟢 LOW — watch items and product gaps

| # | ID | Issue |
|---|---|---|
| 23 | **I-27** | Android version drift — background location, exact alarms and FGS types have tightened every release; assume further restriction. |
| 24 | **I-32** | Boldyn 4G/5G rollout is a moving target; if coverage becomes continuous, Cell-ID should be promoted toward primary. |
| 25 | **I-34** | NaPTAN data goes stale with no update path short of an app release. |
| 26 | **I-38** | TfL trademark rules unverified if the UI ever adopts official line names/colours. |
| 27 | **I-44** | No crash reporting — given how device-dependent the alarm pipeline is, real-world failures will be invisible. |
| 28 | **I-45** | No alarm history; the cheapest possible signal of real accuracy. |
| 29 | **I-42** | Accessibility unassessed — the slide-to-dismiss gesture in particular has no alternative dismissal path. |
| 30 | **I-40** | No cloud sync; a new phone starts from nothing. |
| 31 | **I-41** | No light mode. |
| 32 | **I-43** | English-only, UK-only. |
| 33 | **I-39** | iOS unsupported (deferred by D10; needs a Mac). |

---

## Honest assessment

The above-ground product is close to shippable, and after 2026-08-10 the
procedural blockers are procedural in a narrower sense than before: the
disclosure, the consent flow, the erasure control, the SDK target and the
signing wiring are all in the tree, and the declaration wording, video shot
list and Data Safety answers are written down. What is left of the Play work is
account-bound — generate a keystore, enable Pages, record 30 seconds of screen,
paste four blocks of text. None of it is design work any more.

Two cautions about that. First, the compliance code is **built but unexercised**
— the disclosure and consent dialogs have not been run on a device, only
compiled and analysed. Second, none of it makes the app more likely to wake
anyone up. The three items that decide whether this product actually works —
the uncalibrated thresholds, the unregenerated asset, and the untested fusion
engine — are exactly where they were.

The underground product has moved from *"implemented, never validated"* to
**"implemented on real data, not yet field-verified."** That is a genuine step —
depths and run times are now authoritative rather than invented, the datum
correction is validated against four independently published figures, and the
logging needed to score a real journey exists. But no part of it has met a train.
It should still not be presented to users as a reliability figure.

The two UI lies (I-10, I-11) are gone. Both were removed rather than
implemented, which was the right call in each case: the DND toggle was
unnecessary because alarm-attributed audio already passes DND, and the 16 KB
check was meaningless at runtime because alignment is a property of the built
artifact. Worth noting that my replacement for the second one was itself wrong
on the first attempt and reported a false pass — the failure mode is easy to
reproduce, which is why the script now refuses to pass when it cannot actually
run the check.
