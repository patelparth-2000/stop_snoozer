# StopSnoozer — Google Play Submission Pack

**Everything needed to get through review, and the exact wording to paste.**

| | |
|---|---|
| **Created** | 2026-08-10 |
| **Package** | `com.stopsnoozer.app` |
| **Target API** | 36 (mandatory for new Play submissions from 31 Aug 2026) |
| **Companion docs** | [STOPSNOOZER_ISSUES.md](STOPSNOOZER_ISSUES.md) · [docs/index.md](docs/index.md) |

> Review is probabilistic. Meeting every documented requirement maximises the
> odds but does not guarantee approval. Budget for one or two resubmission
> rounds; the usual cause is the video or the disclosure, not the written
> justification.

---

## What is already done in code

| Requirement | Where | State |
|---|---|---|
| `location` foreground service type | `AndroidManifest.xml` `<service>` | ✅ declared |
| `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT` | `AndroidManifest.xml` | ✅ declared |
| `SCHEDULE_EXACT_ALARM` capped at API 32 | `AndroidManifest.xml` | ✅ correct |
| Prominent disclosure before the OS prompt | `lib/presentation/shared/widgets/prominent_disclosure_dialog.dart` | ✅ built |
| Disclosure gates the permission call | `SplashCubit.requestPermissions()` | ✅ unreachable unless accepted |
| PECR consent for Wi-Fi/cell reads | `ProminentDisclosureDialog.showRadioScanConsent` | ✅ built |
| Consent withdrawal + erasure | System Health → Privacy & Learned Data | ✅ built |
| `targetSdk`/`compileSdk` = 36 | `android/app/build.gradle.kts` | ✅ pinned |
| Release signing config | `android/app/build.gradle.kts` | ⚠️ wired, needs your keystore |
| Privacy policy | `docs/index.md` | ⚠️ written, needs hosting |
| Declaration form | this document | ⬜ needs submitting |
| Demo video | this document | ⬜ needs recording |

---

## 1. Release signing (I-01)

Gradle is already wired. You need to supply the keystore.

```bash
keytool -genkey -v -keystore C:/keys/stopsnoozer-upload.jks \
        -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then `cp android/key.properties.example android/key.properties` and fill it in.
Both `key.properties` and `*.jks` are git-ignored.

**Enrol in Play App Signing** (the Console default). Google then holds the app
signing key and you hold only the *upload* key — which means a lost upload key
is recoverable through Play support instead of permanently orphaning the app.
Back the `.jks` up in two places: encrypted cloud, and offline.

Build:

```bash
flutter build appbundle --release
```

If `key.properties` is missing the build still succeeds but is **debug-signed**
and Play will reject it. Gradle prints a warning to that effect — check for it
before uploading.

---

## 2. Background Location Permissions Declaration

**Play Console → App content → App access + Sensitive app permissions → Location permissions**

**Q: Does your app meet the Location permissions policy?** → *Yes.*

**Q: Describe the feature that requires background location.** Paste:

> StopSnoozer is a commuter alarm that wakes users at their chosen rail or
> Underground stop. On deep-tube sections there is no GPS and no mobile signal,
> so the app must continue running its sensor-based (barometer + accelerometer)
> stop-detection engine while the phone is locked and the app is not in the
> foreground, then fire a full-screen alarm at the destination. The journey is
> always initiated by an explicit user action — the user selects a route and taps
> "Start Tracking" — and runs in a `location`-type foreground service with a
> persistent notification for its whole duration. Background location (Cell-ID
> and Wi-Fi presence) is used only as an opportunistic corroborator of the
> offline sensor engine on above-ground and connected sections. Without
> background operation the alarm cannot fire, which is the entire purpose of the
> app.

**Why this framing:** Play's policy explicitly favours the foreground-service
path for work "initiated as a continuation of an in-app user-initiated action".
Route selection → "Start Tracking" is exactly that, so lead with it.

---

## 3. Demo video

**≤ 30 seconds. Unlisted YouTube link (preferred) or a Google Drive MP4.**

It must show, **in this order**:

1. The **prominent disclosure dialog** appearing — legible on screen.
2. The user tapping **Allow**, then granting the OS permission.
3. The feature **actually using** background location: minimise the app or lock
   the screen, then show the arrival alarm firing.

A simulated or route-preview run is acceptable for step 3, as long as it
demonstrates the background behaviour. The disclosure dialog being visible is
non-negotiable — its absence is the single most common cause of a second round.

### Shot list (fits in 30 s)

| Time | Shot |
|---|---|
| 0–4 s | App launch → permission sheet |
| 4–11 s | Tap "Grant Permissions & Continue" → **disclosure dialog on screen, readable** |
| 11–15 s | Tap "Allow" → Android's "Allow all the time" prompt → grant |
| 15–20 s | Pick origin/destination → route select → "Start Tracking" |
| 20–24 s | Press Home / lock the screen. Persistent tracking notification visible |
| 24–30 s | Full-screen alarm fires over the lock screen |

Record with `adb shell screenrecord --time-limit 30 /sdcard/demo.mp4`, then
`adb pull /sdcard/demo.mp4`.

---

## 4. Data Safety form

**Play Console → App content → Data safety**

The governing rule: data that is **only processed on the device and never sent
off it does not need to be declared as collected**. That covers almost
everything StopSnoozer does.

> Do not confuse this with the *ephemeral* exemption. Ephemeral is for data that
> **is** transmitted off-device but held only transiently. On-device is the
> stronger, cleaner exemption and it is the one that applies here.

| Data type | Collected? | Notes |
|---|---|---|
| Precise location | **No** | Used on-device to fire the alarm; never transmitted |
| Approximate location | **Yes** — see below | Only the postcode lookup |
| Wi-Fi BSSIDs / Cell IDs | **No** | On-device only, consent-gated, never transmitted |
| Barometer / accelerometer readings | **No** | On-device only |
| Saved stops, alarms, settings | **No** | Local database only |
| Crash logs / diagnostics | **No** | No crash SDK in v1 — see the warning below |
| Personal identifiers, contacts, financial | **No** | Not touched |

### The postcode lookup needs declaring

`lib/data/services/postcode_geocoder.dart` sends a user-typed UK postcode to
**api.postcodes.io** to convert it to coordinates. This is the app's only
runtime network call, and it **is** off-device transmission, so the on-device
exemption does not cover it.

Recommended answers:

- **Data type:** Location → Approximate location
- **Collected:** Yes · **Shared:** Yes (a third-party API we do not operate)
- **Purpose:** App functionality
- **Required or optional:** Optional — only sent if the user searches by
  postcode rather than by stop name
- **Processed ephemerally:** Yes — not retained by StopSnoozer after the request

Declaring it is cheap; under-declaring is an enforcement trigger. A mismatch
between this form and the privacy policy is itself a flagged trigger, so keep
[docs/index.md](docs/index.md) in step with whatever you answer here.

> **If you later add Crashlytics or Sentry** (I-44), that is off-device
> transmission: flip crash logs and diagnostics to *collected*, and update the
> privacy policy in the same release.

---

## 5. Privacy policy hosting (I-35)

The policy is written and ready at [`docs/index.md`](docs/index.md).

To host it free on GitHub Pages:

1. Push `docs/` to `main`.
2. Repo → **Settings → Pages** → Source: *Deploy from a branch* →
   Branch `main`, folder `/docs` → Save.
3. Wait for the build, then confirm the page loads at:
   **`https://patelparth-2000.github.io/stop-snoozer/`**

Put that URL in **two** places — Play Console → App content → Privacy policy,
**and** inside the app. Play checks both.

Before submitting, re-read the policy against reality: it names you as the
developer, gives your contact address, specifically discloses **background**
location, and describes the sensor and radio data. All four are things reviewers
check for and are the usual reasons a policy is rejected as inadequate.

---

## 6. Exact alarms and full-screen intent

No form to fill in — but make the carve-out self-evident.

Play's sensitive-permissions policy reserves `USE_EXACT_ALARM` for "apps whose
core, user-facing functionality genuinely requires precise timing, like
dedicated alarm, timer, or calendar applications". StopSnoozer is a dedicated
alarm app, so it qualifies. `USE_FULL_SCREEN_INTENT` is auto-granted on Android
14+ on the same basis.

**Action:** lead the store title and the first line of the description with
*alarm*, so a reviewer sees the justification without having to look for it.
Something like "StopSnoozer — Commuter Alarm: never miss your stop."

### Fallback if the carve-out is ever refused

Already partly in place (`SCHEDULE_EXACT_ALARM` is declared for API ≤ 32). If
Play ever rejects the carve-out, the degradation path is:

1. `AlarmManager.canScheduleExactAlarms()`
2. If false → `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`
3. If declined → `setAndAllowWhileIdle()` / `setWindow()` (10-minute minimum
   window), and tell the user in the UI that timing is now approximate.

---

## 7. Pre-submission checklist

- [ ] `android/key.properties` present; Gradle prints no debug-signing warning
- [ ] Enrolled in Play App Signing; `.jks` backed up in two places
- [ ] `flutter build appbundle --release` succeeds
- [ ] `tools/check_16kb_alignment.sh` passes on the release artifact
- [ ] Privacy policy live at the Pages URL and linked in-app **and** in Console
- [ ] Data Safety answers match the privacy policy line for line
- [ ] Location declaration submitted with the wording in §2
- [ ] Video ≤ 30 s, unlisted, shows disclosure → grant → background alarm
- [ ] Store title/description lead with "alarm"
- [ ] Tested on a real **API 36** device — see the open risk below
- [ ] Tested on a real Xiaomi/Samsung/Huawei device (I-26)

---

## Open risks to verify before you rely on them

**Boot-time foreground-service start (API 36).** Android 15 began refusing
foreground-service starts from `BOOT_COMPLETED` for a set of service types, and
that set has grown since. Whether `location` is in the restricted set at API 36
has **not been verified on a real device** for this app. `BootReceiver` now
wraps the start in a try/catch so a refusal degrades to "tracking resumes when
the user next opens the app" instead of crashing at every boot — but confirm the
actual behaviour on an API 36 device and check logcat for
`ForegroundServiceStartNotAllowedException`. The user's alarms themselves do not
depend on this path: they are re-armed via `setAlarmClock()`, which is
Doze-exempt and independent.

**Legacy Wi-Fi identity scaffolding (I-19).** `ACTION_START_WIFI`, `targetSsid`,
`TargetStop.ssid` and the `wifi_ssid` column are dead code from the disproven
SSID-identity model. Removing them before submission drops the surface a
reviewer can ask about, and lets any now-unused permissions come out of the
manifest. Not a blocker, but cheap.

**Thresholds are uncalibrated (I-03).** Nothing here changes the fact that the
underground engine has never met a train. Do not describe accuracy in the store
listing.
