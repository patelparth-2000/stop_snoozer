# StopSnoozer — Complete UI & Screen Reference

> Single-file reference for every screen, sheet, dialog, overlay and widget in the current Flutter app.
> Generated from source at `lib/` on 2026-08-10. Branch: `main`.

---

## 1. At a Glance

| Item | Value |
|---|---|
| App name | **StopSnoozer** |
| Tagline | "Never Miss Your Stop Again" |
| Platform | Android (primary), iOS project exists but deferred |
| Purpose | Location/sensor-triggered alarm that wakes you when you reach your transit stop — works above ground (GPS geofence) and underground (Wi-Fi SSID + motion/pressure sensors) |
| Data | 100% offline. Bundled UK NaPTAN SQLite stop database. No account, no cloud sync |
| Architecture | MVVM + BLoC/Cubit (`flutter_bloc`), `go_router` with `StatefulShellRoute` |
| Total Dart files | 85 (~15,000 lines) |
| **Routed screens** | **8** (5 tab screens + 3 full-screen takeovers) |
| **Modal sheets** | **4** |
| **Dialogs** | **5** (2 custom + 3 system pickers) |
| **Overlays** | **1** (onboarding) |
| Fonts | `Sora` (headings/labels), `Inter` (body) — via `google_fonts` |
| Themes | 5 dark colour themes, runtime-swappable + separate logo colour |

---

## 2. Navigation Map

```
main.dart
  └── ThemeService.load()          ← restores saved theme before first frame
       └── StopSnoozerApp (MaterialApp.router)
            └── appRouter (initialLocation: /splash)
                 │
                 ├── /splash          ← FULL SCREEN (no bottom nav)
                 ├── /alarm           ← FULL SCREEN (no bottom nav)
                 ├── /route-select    ← FULL SCREEN (no bottom nav)  ⚠ orphaned, see §11
                 │
                 └── StatefulShellRoute.indexedStack  ← AppShell + bottom nav
                      ├── [0] /dashboard   "Home"      🏠
                      ├── [1] /search      "Search"    🔍
                      ├── [2] /queue       "Queue"     ▶
                      ├── [3] /calendar    "Alarms"    ⏰
                      └── [4] /settings    "Settings"  ⚙
```

**Page transition:** all routes use a 200 ms `FadeTransition` (`_fade()` helper in `app_router.dart`).

**Long-lived Cubits** (created once at file scope in `app_router.dart:24-27`, shared across the whole shell so tab state survives switching):
- `DashboardCubit`
- `TripConfigCubit`
- `CommuteAlarmsCubit`
- `SearchCubit`

Per-route Cubits (created fresh on entry): `SplashCubit`, `DatabaseInitHandler`, `AlarmCubit`, `SystemHealthCubit`, `RouteSelectCubit`.

**Typical user flow:**
```
Splash → (permissions) → Dashboard → [Onboarding overlay, first launch only]
   → Search → tap stop → Queue (leg added) → "Arm System" → Dashboard (tracking)
   → …travel… → native service fires → Alarm screen → dismiss → next leg / done
```

---

## 3. Persistent Shell — Bottom Navigation Bar

**File:** `lib/app/shell/app_shell.dart`

Custom-built nav bar (not Material's `BottomNavigationBar`).

| # | Icon | Label | Route |
|---|---|---|---|
| 0 | `home_rounded` | Home | `/dashboard` |
| 1 | `search_rounded` | Search | `/search` |
| 2 | `playlist_play_rounded` | Queue | `/queue` |
| 3 | `alarm_rounded` | Alarms | `/calendar` |
| 4 | `settings_rounded` | Settings | `/settings` |

**Features:**
- Height 60 dp + bottom safe-area padding
- Active tab: animated **under-slung 2 dp neon indicator pill** (width animates 0 → 28 dp over 200 ms, `Curves.easeOut`)
- Active icon + label tinted `ColorConstants.primary`; inactive `textDisabled`
- Label weight bumps to `w600` when active
- **Re-tapping the active tab** resets that branch to its initial route
- **Leaving the Search tab auto-clears search state** (`SearchCubit.clear()`)
- 1 px top divider border, `surfaceSecondary` background
- `ThemeScope.watch(context)` — rebuilds the whole shell when the theme changes

---

## 4. Screen 1 — Splash

| | |
|---|---|
| **Route** | `/splash` (initial route, outside shell) |
| **Files** | `presentation/splash/splash_screen.dart`, `splash_viewmodel.dart` |
| **State** | `SplashCubit` → `SplashState` + `DatabaseInitHandler` (a real `Bloc`, not Cubit) |
| **Components** | `SplashLogoWidget`, `SplashProgressBar`, `SplashPermissionSheet` |

### Layout
```
┌──────────────────────────────┐
│  Radial gradient background  │  surfaceTertiary → surfaceBase, radius 1.2
│                              │
│         [Spacer]             │
│        ◉ 96×96 glowing       │  pulsing bell icon, glow 8→28 blur, 1500 ms loop
│      StopSnoozer  (28 sp)    │
│  Never Miss Your Stop Again  │
│                              │
│   ▓▓▓▓▓░░░░░  62 %           │  ← only during DB decompression
│         [Spacer]             │
├──────────────────────────────┤
│  ▁▁▁ (drag handle)           │  ← Permission sheet, slides up over the stack
│  Before we begin             │
│  [5 permission rows]         │
│  [ Grant Permissions ]       │
│  [ Skip for now ]            │
└──────────────────────────────┘
```

### Phases (`SplashPhase`)
1. **`waiting`** — DB init running. Shows logo + progress bar.
2. **`permissions`** — DB ready, one or more permissions missing. Shows the permission sheet.
3. **`ready`** — navigates to `/dashboard`.

### Database initialisation (`DatabaseInitHandler`)
States: `DatabaseInitialState` → `DatabaseDecompressingState(progress)` → `DatabaseReadyState` / `DatabaseErrorState(msg)`

- If `db.isReady`, skips straight to ready (warm start)
- Otherwise decompresses the bundled NaPTAN DB with live progress callbacks
- **Awaits** `RouteTopologyRepository.loadConsent()` — nothing may read a radio identifier before the stored consent answer is in memory (fails closed = denied)
- **Fire-and-forget** `RouteTopologyRepository().maintain()` — ages out stale Wi-Fi fingerprints without delaying the splash
- On error → `SplashProgressBar` renders `_ErrorState`: red error icon + "Something went wrong" + the exception message

### Progress bar
- Label "Decompressing UK Stop Database"
- 4 dp rounded `LinearProgressIndicator`, primary fill on `surfaceElevated` track
- Right-aligned percentage in Sora w600

### Permission sheet (`SplashPermissionSheet`)
Bottom-anchored card, `surfaceModal`, 24 dp top corner radius, drag handle.

| Icon | Permission | Description |
|---|---|---|
| `location_on_rounded` | Precise Location | Required for GPS geofencing above ground |
| `location_searching_rounded` | Background Location | Must be "Allow all the time" — required for alarms to fire when the app is closed |
| `notifications_rounded` | Notifications | To alert you when approaching your stop |
| `battery_charging_full_rounded` | Battery Optimisation Exemption | Prevents the OS from killing the tracking service |
| `phone_android_rounded` | Alarm Display (full-screen intent) | Required on Android 14+ to show the alarm over the lock screen |

**Row states:** granted → green `successGlow` tile + green icon + trailing `check_circle_rounded`. Not granted → `primarySubtle` tile + primary icon, no check.

**Conditional explainer:** if the user was shown the background-location disclosure and *declined it* (`bgDisclosureDeclined`, distinct from never being asked), an extra grey info box appears: *"Without background location, alarms can only fire while StopSnoozer is open and on screen."*

**Buttons:** `Grant Permissions & Continue` (primary) · `Skip for now` (ghost)

### Permission request sequence (`SplashCubit.requestPermissions`)
Order is a **Play Store policy requirement**, not a UI choice:
1. Request `locationWhenInUse`
2. If granted and `locationAlways` not yet held → **show `ProminentDisclosureDialog.showBackgroundLocation()` first**
3. Request `locationAlways` **only if** the disclosure returned `true`
4. Request `notification`
5. Request `ignoreBatteryOptimizations`
6. Check + request full-screen-intent permission via platform channel

Advances to `ready` once location (any) **and** notifications are granted. `Skip for now` jumps straight to `ready`.

---

## 5. Screen 2 — Dashboard (Home tab)

| | |
|---|---|
| **Route** | `/dashboard` — shell tab 0 |
| **Files** | `presentation/dashboard/dashboard_screen.dart`, `dashboard_viewmodel.dart` |
| **State** | `DashboardCubit` → `DashboardState` (shared, long-lived) |
| **Components** | `DashboardAppBar`, `LocationDetectionCard`, `_ProximitySuggestionCard`, `TransportChipsRow`, `_SavedStopsSection` → `SavedLocationCard`, `JourneyTimeline` → `JourneyLegTile`, `_BottomBar` |

### Layout (top → bottom)
```
┌────────────────────────────────────────┐
│ StopSnoozer                 ⏰  🎨  ⚙  │  App bar
│ Good morning, Commuter                 │
├────────────────────────────────────────┤
│ ● DETECTED NEAR │ Oxford Circus        │  Location detection card
├────────────────────────────────────────┤
│ 🚇 Are you near Oxford Circus?      ›  │  Proximity suggestion (conditional)
│    Tap to prime your destination stop  │
├────────────────────────────────────────┤
│ (🚇 Tube) (🚌 Bus) (🚆 Rail) …         │  Horizontal transport chips
├────────────────────────────────────────┤
│ SAVED STOPS                            │  (conditional)
│ 🚇 Victoria         ● Tracking active ⬤ │  swipe-left to delete
│ 🚌 Camden Town                       ○ │
├────────────────────────────────────────┤
│ Active Journey                         │  Journey timeline (scrollable)
│  ●──  🚇 Waterloo        [ACTIVE]      │
│  │      500 m wake radius              │
│  ○──  🚌 Elephant & C.   [QUEUED]      │
├────────────────────────────────────────┤
│  [ 🔍 Search Destination / New Trip ]  │  Sticky bottom CTA
└────────────────────────────────────────┘
```

### Features

**App bar (`DashboardAppBar`)**
- Brand label "StopSnoozer" (11 sp, primary, letterspaced) above a time-based greeting
- Greeting logic: `< 12:00` → "Good morning, Commuter" · `< 17:00` → "Good afternoon" · else "Good evening"
- Three 42×42 icon buttons: **⏰ Alarms** → `/calendar` · **🎨 Palette** → opens `ThemePickerSheet` · **⚙ Settings** → `/settings`

**Location detection card**
- Animated pulse dot: green with breathing glow (1500 ms `easeInOut`) when located; static grey while locating
- Text flips between `LOCATING…` and `DETECTED NEAR` + the nearest stop name (ellipsised)
- Trailing 12 dp spinner while locating

**Proximity suggestion card** — shown only when: location is resolved **and** nearby stops exist **and** there is no active trip. Tapping goes to `/search`. Tube-coloured border.

**Transport chips row** — horizontally scrollable pills for each of the up-to-8 nearby stops, showing mode icon + mode label. Hidden when empty.

**Saved stops section** — shown only when saved locations exist.
- `SavedLocationCard` per stop: mode icon, name, and (when active) a green dot + "Tracking active" caption
- **Toggle switch** arms/disarms tracking for that stop
- **Swipe left to delete** (`Dismissible`, dark-red background with trash icon)
- Active cards get a 3 dp primary left border

**Journey timeline** — vertical connected timeline of the armed trip.
- Per leg: status dot (primary=active w/ glow · green=complete w/ glow · grey outline=queued), 1 px gradient connector line (60 dp), and a card with mode icon, stop name, `N m wake radius`, and a status badge (`ACTIVE` / `QUEUED` / `COMPLETE`)
- Active leg card: `primarySubtle` fill, 3 dp primary left border, 16 dp primary glow shadow
- **Empty state:** route icon + "No active trip" / "Search for a destination to get started"

**Bottom bar** — full-width primary `SnoozerButton`: "Search Destination / Plan New Trip" with search icon. Sticky, above the nav bar, with 1 px top divider.

**Onboarding overlay** — rendered in a `Stack` above the Scaffold on first launch only (see §12).

### Cubit behaviour (`DashboardCubit`)

**`load()`** (runs on first frame):
1. Loads saved locations first, so the list never flickers empty if location fails
2. **Re-arms every active saved location** with the native service — this is what makes tracking survive app kills and device reboots
3. Independently fetches current location → queries 8 nearest stops → sets `detectedStopName`
4. Checks `checkPendingTripGroup()` — if a group-based commute alarm fired while the app was dead, loads the whole group so all legs track in sequence
5. Checks `checkPendingAlarm()` — if a proximity alarm fired while killed, records the event and re-raises the alarm state

**`toggleSavedLocation(id)`** — multiple locations can be active at once; **all are tracked in parallel and whichever is reached first fires**. Builds a `targets` array and pushes it in one `updateTrackingTargets` call. Turning the last one off calls `stopTracking()` + `stopAlarm()`.

**`loadTrip(legs)`** — marks leg 0 `active`, the rest `queued`, starts tracking leg 0, and auto-saves the destination into Saved Stops.

**`_startTrackingActive`** — picks the native strategy: `startHybridSensing` when the stop has a `wifiSsid` (underground), otherwise `startGeofence` (GPS). Sets `TrackingMode` to `subterranean` / `aboveGround`.

**`advanceLeg()`** — called on alarm dismiss. Marks the current leg complete, activates + starts tracking the next; if none remain, clears the trip after a 2 s delay.

**Native alarm stream listener** — `_onNativeAlarm` records an `AlarmEvent` in history and pushes alarm state (stop, distance, `firedAt` timestamp, countdown seconds).

**Warning SnackBar** — when `warningMessage` is set, shows a 5 s dark SnackBar with a **"Settings"** action that opens Android Wi-Fi settings.

---

## 6. Screen 3 — Search

| | |
|---|---|
| **Route** | `/search` — shell tab 1 |
| **Files** | `presentation/search/search_screen.dart`, `search_viewmodel.dart` |
| **State** | `SearchCubit` → `SearchState` (shared, long-lived) |
| **Components** | `SearchOmnibar`, `SearchFilterBar`, `_ModeBanner`, `StopResultCard`, `_PlaceholderState` |

### Layout
```
┌────────────────────────────────────────┐
│ [←] [🔍 Station, stop or area…    ✕/◌] │  Omnibar
├────────────────────────────────────────┤
│ (All) (Bus) (Tube & DLR) (Rail)        │  Filter chips
├────────────────────────────────────────┤
│ 📍 Postcode detected — nearest stops   │  Mode banner (conditional)
├────────────────────────────────────────┤
│ 🚇 Oxford Circus         [Stop A]   ›  │  Result cards
│    Tube                       0.4 mi   │
│ 🚌 Oxford Circus         [Stop C]   ›  │
│    Bus                        0.5 mi   │
└────────────────────────────────────────┘
```

### Features

**Omnibar (`SearchOmnibar`)**
- Optional 44×52 back button → returns to `/queue` if legs exist, else `/dashboard`
- 52 dp tall field, **autofocus on entry**
- Focus animation: border thickens to 1.5 px + primary tint + soft primary glow shadow (150 ms)
- Trailing slot: spinner while searching → **✕ clear** button when text present → nothing when empty
- Hint: "Station, stop or area…"

**Filter bar (`SearchFilterBar`)** — 4 horizontally scrollable pill chips. Active chip = solid primary fill with `surfaceBase` text and w700 weight. Changing a filter **immediately re-runs the current query** with the new DB type list.

| Filter | Maps to DB `transit_type` |
|---|---|
| All | *(no filter)* |
| Bus | `bus` |
| Tube & DLR | `underground`, `dlr`, `tram` |
| Rail | `train`, `overground` |

**Search behaviour**
- 300 ms debounce (`AppConstants.searchDebounceMs`)
- **Automatic postcode detection** — `PostcodeGeocoder.isPostcode()` on every keystroke. UK postcode pattern → geocodes and returns the nearest stops instead of a name search
- **Duplicate-name disambiguation** — the Cubit computes the set of names appearing more than once; only those cards render their NaPTAN indicator badge (e.g. `Stop A`, `opp Church`)

**Banners**
- Postcode mode → primary-glow banner, `location_on_outlined`, "Postcode detected — showing nearest stops"
- Postcode failure → red banner, `error_outline_rounded`, "Postcode not found — check spelling and try again"

**Result card (`StopResultCard`)**
- 3 dp **mode-coloured left border**: green (tube/DLR/tram) · coral (bus) · sky blue (rail/overground/ferry)
- 40 dp mode icon tile
- **Live query highlighting** — matching substrings inside the stop name render in primary/w700 (`_HighlightedText` walks all occurrences, case-insensitive)
- Indicator badge when the name is ambiguous
- Mode label caption + distance in miles (only in postcode/proximity mode) + chevron

**Empty states**
- No query → centred search icon + "Search for a stop" / "Start typing a station, stop or area"
- No results → `No stops found for "query"`

**Selecting a stop** → `TripConfigCubit.addLeg(stop)` then navigates to `/queue`.

---

## 7. Screen 4 — Queue / Trip Config

| | |
|---|---|
| **Route** | `/queue` — shell tab 2 |
| **Files** | `presentation/trip_config/trip_config_screen.dart`, `trip_config_viewmodel.dart` |
| **State** | `TripConfigCubit` → `TripConfigState` (shared, long-lived) |
| **Components** | `TripLegConfigCard` → `WakeRadiusSlider`, `TripConfigFooter`, `_ModeToggle`, `_GroupCard`, `_AddLegSheet`, `_EmptyState` |

### Layout
```
┌────────────────────────────────────────┐
│ Review Your Trip Playlist  [🔖 Save Gp]│  Header
├────────────────────────────────────────┤
│ [ 📍 Single Stop ][ 🔀 Trip Group ]    │  Mode toggle
├────────────────────────────────────────┤
│ ⣿ 🚇 LEG 1                      ✕  ⌃  │  Reorderable leg card (expanded)
│      Waterloo                          │
│   ───────────────────────────────      │
│   WAKE RADIUS              [500 m]     │
│   ●━━━━━━━━━━━━━○━━━━━━━━━             │
│   100 m                     1000 m     │
├────────────────────────────────────────┤
│         [ + Add Transit Step ]         │
├────────────────────────────────────────┤
│ [ Clear ]  [ 🛡 Arm System         ]   │  Footer
└────────────────────────────────────────┘
```

### Two modes (`QueueMode`)

**A. Single Stop** — the working queue you actually arm.
- **`ReorderableListView`** — drag legs by the `drag_indicator_rounded` handle to change order
- Each `TripLegConfigCard`:
  - 3 dp primary left border
  - Header: drag handle · mode icon · `LEG N` label (9 sp primary) · stop name · red ✕ remove button · expand/collapse chevron
  - **Tap the header to collapse/expand** (300 ms `AnimatedSize`)
  - Body: **Wake Radius slider** — 100 m to 1000 m, 18 divisions, live pill readout showing the current value, min/max captions beneath
- `+ Add Transit Step` button at the bottom opens the Add-Leg sheet
- **Empty state:** playlist icon + "No stops added yet" + tappable "+ Add Transit Step"

**B. Trip Group** — saved reusable multi-stop routes.
- Card list of saved groups: route icon, name, "N stops" subtitle
- **Load** button → loads the group's legs into the queue and auto-switches back to Single Stop mode
- Trash icon → deletes the group
- **Empty state:** bookmarks icon + "No saved groups yet" + "Switch to Single Stop, add stops, then tap 'Save Group' to create one."

**Mode toggle** — segmented control, 3 dp inner padding, animated (150 ms) primary tint + border on the active half.

### Header actions
- **`🔖 Save Group`** chip — only visible when legs exist *and* Single Stop mode is active. Opens a dialog with a text field ("Group name…"); blank names fall back to `Trip N`. Confirms with a "Trip group saved" SnackBar.

### Footer (`TripConfigFooter`)
- **Clear** (secondary, flex 1) — wipes the queue and returns to `/dashboard`
- **🛡 Arm System** (primary, flex 2) — disabled unless legs exist **and** Single Stop mode is active. Builds armed legs (first `active`, rest `queued`), hands them to `DashboardCubit.loadTrip()`, navigates to `/dashboard`

### Back-navigation guard
`PopScope(canPop: false)` — pressing back with legs in the queue shows a **"Leave queue?"** confirmation dialog ("Your current stops will be cleared." · **Stay** / **Leave** in red).

### Add-Leg sheet (`_AddLegSheet`)
Modal bottom sheet, drag handle, "Add a Leg" title:
- **Search a Stop** — amber-bordered primary tile ("Find by name or postcode") → closes the sheet and goes to `/search`
- **OR LOAD A SAVED GROUP** — listed below when groups exist; tapping loads the group and shows a `Loaded "name"` SnackBar

---

## 8. Screen 5 — Alarms / Commute Schedule (Calendar tab)

| | |
|---|---|
| **Route** | `/calendar` — shell tab 3 |
| **Files** | `presentation/calendar/calendar_screen.dart`, `calendar_viewmodel.dart` |
| **State** | `CommuteAlarmsCubit` → `CommuteAlarmsState` (shared, long-lived) |
| **Components** | `AlarmCard`, `CreateAlarmSheet`, `_HistorySection` → `_HistoryTile`, `_InfoBanner` |

### Layout
```
┌────────────────────────────────────────┐
│ COMMUTE ALARMS              [ + Add ]  │  Header
│ Scheduled Windows                      │
├────────────────────────────────────────┤
│ 08:15 AM                    [✎]  ⬤    │  Alarm card (swipe ← to delete)
│ → 🚇  Office via Northern Line         │
│ (M)(T)(W)(Th)(F)(Sa)(Su)               │
├────────────────────────────────────────┤
│ 06:30 PM                    [✎]  ○     │  Inactive alarm (dimmed)
│ → 🚌  Home                             │
│ [Only on Aug 14]                       │
├────────────────────────────────────────┤
│ RECENT ACTIVITY            Clear all   │  History
│ ● Waterloo                             │
│   Mon 10/8  8:22 AM        142 m away  │
├────────────────────────────────────────┤
│ ⓘ Tracking starts precisely at your    │  Info banner
│   configured departure times…          │
├────────────────────────────────────────┤
│      ‹ Back to Dashboard               │  Footer
└────────────────────────────────────────┘
```

### Features

**Header** — "COMMUTE ALARMS" eyebrow + "Scheduled Windows" title + a glowing primary **`+ Add`** button (12 dp blur shadow).

**Alarm cards (`AlarmCard`)**
- **Swipe left to delete** (`Dismissible`, endToStart, dark-red `#7F1D1D` background)
- 3 dp primary left border when active, grey when off
- Row 1: **28 sp time** (`08:15 AM`) · 32×32 **edit ✎** button · **on/off Switch**
- Row 2: arrow + mode emoji + route label
- Row 3: either seven **day pills** (M T W Th F Sa Su — active days filled primary) or a single **one-off chip** ("Only on Aug 14")
- Inactive alarms render every element in `textDisabled`

**History section** — appears only when the alarm-fire log is non-empty.
- "RECENT ACTIVITY" label with a **Clear all** action
- Per tile: green dot · stop name · `Mon 10/8  8:22 AM` · right-aligned distance (`142 m away`, or `at stop` when under 10 m) in green

**Info banner** — 3 dp primary left border: *"Tracking starts precisely at your configured departure times. StopSnoozer stays dormant outside these windows, drawing zero background battery."*

**Footer** — subtle "‹ Back to Dashboard" text link.

**Loading state** — 24 dp centred primary spinner.

**Empty state** — `alarm_off_rounded` + "No scheduled commutes" + "Tap 'Add' to automate your tracking windows."

### Cubit behaviour
- `load()` fetches alarms and history in parallel (`Future.wait`)
- `add` / `toggle` / `updateAlarm` all **schedule or cancel the native `AlarmManager` alarm** via `PlatformChannelService.scheduleCommuteAlarm` / `cancelCommuteAlarm`
- Alarm list is kept **sorted by departure time** (hour × 60 + minute)
- `updateAlarm` always cancels the old native alarm before rescheduling

---

## 9. Screen 6 — Settings / System Health

| | |
|---|---|
| **Route** | `/settings` — shell tab 4 |
| **Files** | `presentation/system_health/system_health_screen.dart`, `system_health_viewmodel.dart` |
| **State** | `SystemHealthCubit` → `SystemHealthState` (per-route) |
| **Components** | `OemBatteryCard`, `AlarmSelfTestCard`, `SensorStatusCard`, `LearnedDataCard`, `AttributionCard`, `_DndInfoCard`, `_StorageStatsCard`, `_AlarmPreferencesCard` |

Header: **"System Permissions & Background Compliance"**. Footer: version string `v1.0.0-stable | Build 1000`.

**Auto-refresh:** the content widget is a `WidgetsBindingObserver` — it re-runs `cubit.init()` every time the app returns to the foreground, so permission toggles flipped in Android Settings reflect immediately.

### Section 1 — OS Bypass Authorization

**Battery optimisation card**
- Status dot (mint green = authorized / coral red = restricted) + title + **AUTHORIZED / RESTRICTED** badge
- Body: "Custom manufacturer software can kill background tracking. Whitelist StopSnoozer to guarantee alarms fire while asleep."
- Button: `Grant Whitelist Exemption` → becomes a disabled secondary `Whitelist Active` once granted; shows a spinner while requesting

**OEM battery card (`OemBatteryCard`)** — *conditional*. Renders **only** when the device manufacturer is a known extra-killer (Xiaomi/MIUI, Huawei, Oppo, Vivo, …) **and** the specific settings Activity actually resolves. Explains that these OEMs run a proprietary killer on top of AOSP, and offers an `Open <OEM> Settings` button.

**DND info card (`_DndInfoCard`)** — informational, not interactive. Explains that the alarm plays with `AudioAttributes.USAGE_ALARM` so Android's Do Not Disturb lets it through with no extra permission. *(This deliberately replaced a former "DND bypass" toggle that only flipped local state and never requested `ACCESS_NOTIFICATION_POLICY` — it advertised a guarantee the app did not have.)*

### Section 2 — Alarm Delivery Verification

**`AlarmSelfTestCard`** — answers the question permission checkmarks cannot: *will an alarm actually fire on this phone?*

Four states (`SelfTestState`):

| State | Body text | Action |
|---|---|---|
| `idle` | "Schedules a real alarm 10 seconds from now… Leave the app or lock your screen after starting — that is exactly what this checks." | **Run Alarm Test** |
| `armed` | "Armed. Lock your screen and wait…" *(or an inexact-alarm variant warning it may take up to a minute)* | **Waiting for alarm…** (loading) |
| `passed` | "Passed — the alarm fired while the app was in the background." | ✓ green "Alarm delivery verified" + **Test again** |
| `failed` | "No alarm fired within the expected window… the most common cause is a manufacturer battery manager." | **Try Again** + **Fix in \<OEM\> Settings** (card gains a red border) |

**Named blocking warnings** rendered above the action when detected:
- Exact alarms turned off → "Alarms will still fire, but may be several minutes late — enough to miss a stop."
- Notifications blocked → "You will not see or hear the alarm."
- Battery optimisation active → "Android may stop tracking while your screen is off."

Resolution reads the **native fired-timestamp**, not a Dart timer — a timer-only implementation would wrongly report a pass if the OS had killed the process. Grace period: +8 s for exact alarms, +60 s for inexact.

### Section 3 — Hardware Sensor Diagnostics

Four cards:
1. `_PermissionStatusCard` — "Background Location Lifecycle (Always Allow)" with dot + badge
2. `SensorStatusCard` — "GPS Geofence Kernel" (`gps_fixed_rounded`)
3. `SensorStatusCard` — "Underground Wi-Fi Scanner" (`wifi_rounded`)
4. `SensorStatusCard` — "Underground Detection (Wi-Fi SSID Scanning)" (`explore_rounded`)

`SensorStatus` renders as: **Online / Active** (green + glowing dot) · **Standby / Idle** (grey) · **Unavailable** (red).

### Section 4 — Alarm Preferences (`_AlarmPreferencesCard`)

- **Alert Style** — three chips: `Screen` · `Notification` · `Both`, with a live explanation line:
  - Screen → "Alarm screen opens — no notification banner."
  - Notification → "Notification with Stop button — no full-screen takeover."
  - Both → "Alarm screen + notification banner with Stop button."
- **Alarm Tone** — music icon + current ringtone name + a **Change** pill that opens the **native Android ringtone picker** (shows an inline spinner while open)
- Values are read from and written to native via `getAlarmSettings` / `setAlarmSettings`

### Section 5 — Offline Storage Status (`_StorageStatsCard`)

All values are **queried live from SQLite**, never hardcoded:

| Row | Example |
|---|---|
| Stops indexed | `353,363` |
| Database size | `16.5 MB` |
| Page size | `4,096 B` |
| Schema version | `v3` |
| Fast search index | `FTS5 active` / `not built` |
| *(divider)* | |
| Route sequences | count or `none` |
| Inter-station times | count |
| Platform depths | count |

If topology is missing, an inline info note appears: *"No Underground route map installed — stop-by-stop tracking is unavailable. GPS alarms work normally."*

### Section 6 — Privacy & Learned Data (`LearnedDataCard`)

Consent control and erasure for on-device radio fingerprints (PECR reg. 6 + UK GDPR erasure).

- **Switch** — toggling on shows `ProminentDisclosureDialog.showRadioScanConsent()`; toggling off is **immediate and destructive** by design
- Body text swaps between the on and off explanation ("…Stored on this device only, never sent anywhere." / "Off. Arrival detection uses only the pressure and motion sensors and journey timing.")
- Live counter: `N identifiers learned`
- **Erase learned data** — red danger button, shown only when the count is above zero

### Section 7 — Data Sources & Licences (`AttributionCard`)

Legally required attribution, all text `SelectableText`:
1. **NaPTAN** — OGL v3.0 attribution statement + licence URL + copy-to-clipboard button
2. **Transport for London** — TfL Open Data + OS Crown copyright + explicit non-affiliation disclaimer + URL
3. **On-device data & privacy** — no upload, no account, fingerprints never transmitted

---

## 10. Screen 7 — Alarm (full-screen takeover)

| | |
|---|---|
| **Route** | `/alarm` (outside shell — **no bottom nav**) |
| **Files** | `presentation/alarm/alarm_screen.dart`, `alarm_viewmodel.dart` |
| **State** | `AlarmCubit` → `AlarmState` |
| **Components** | `AlarmHeader`, `AlarmDestinationInfo`, `SlideToDismissBar`, `_SnoozeChip` |

Receives `stop`, `distance`, `firedAt`, `countdownSecs` via `state.extra`. **Countdown is resynchronised from the native `firedAt` epoch-ms**, so relaunching mid-alarm shows the correct remaining seconds rather than restarting. Falls back to a placeholder stop for deep links.

### Phase A — Countdown (`_CountdownScreen`)
Shown when `countdownSeconds > 0`.
```
                              [✕]
            Approaching
          Oxford Circus
              ╭─────╮
              │  4  │          160×160 circle, 72 sp number
              ╰─────╯
     Alarm starting in 4 seconds
        Dismiss now to cancel
```
- 3 px primary-tinted ring, `primarySubtle` fill
- Ticks down once per second via `Timer.periodic`; at zero it flips to `isRinging`
- Top-right ✕ dismisses immediately (cancels before the ringtone starts)

### Phase B — Ringing (`_RingingScreen`)
```
                              [✕]
              ◉  (pulsing ⚠ 80×80)
            WAKE UP!               40 sp w900, primary + 24 blur glow
      ┌──────────────────────┐
      │     APPROACHING      │
      │  🚇  Oxford Circus   │
      │   [ Approx 180 m Away ] │
      └──────────────────────┘
      (💤 Snooze 5 min) (💤 Snooze 10 min)
   >>> Slide Fully to Safe Zone to Stop Audio >>>
      [ ⬤━━━━━━━━━━━━━━━━━━━━━━━ ]
```
- **Animated background** — `ColorTween` from `surfaceBase` to `#1A0A00` (deep amber-black), repeating with reverse over 1500 ms
- **`AlarmHeader`** — 80 dp circle with a warning icon, scale-pulsing 0.92 ↔ 1.08, 32 dp red glow shadow; "WAKE UP!" beneath
- **`AlarmDestinationInfo`** — card with primary-glow border: "APPROACHING" eyebrow, mode icon + stop name, and a pill reading `Approx N m Away`
- **Snooze chips** — 5 min and 10 min. Snoozing calls the native `snoozeAlarm`, returns to `/dashboard`, and shows a 4 s SnackBar: *"Snoozed N min — alarm will re-check your location"*
- **`SlideToDismissBar`** — 52 dp draggable red thumb on a rounded track; the track fills with `errorGlow` as you drag; fires at **90 % progress** (`AppConstants.dismissThreshold`); springs back to 0 if released early

**On dismiss:** cancels the countdown timer → calls native `stopAlarm()` → invokes `onDismissed` (wired to `DashboardCubit.advanceLeg`) → navigates to `/dashboard`.

---

## 11. Screen 8 — Route Select (Underground pre-selection)

| | |
|---|---|
| **Route** | `/route-select` (outside shell) |
| **Files** | `presentation/route_select/route_select_screen.dart`, `route_select_viewmodel.dart` |
| **State** | `RouteSelectCubit` → `RouteSelectState` |
| **Components** | `_JourneyHeader`, `_OptionTile`, `_PlanPreview`, `_NoBarometerNotice`, `_LoggingToggle`, `FieldTestPanel`, `_Blocked` |

> ⚠ **Currently unreachable from the UI.** The route is registered and fully implemented, but **no screen navigates to `/route-select`** — nothing calls `context.go('/route-select')`. It requires `origin` and `destination` in `state.extra`; reaching it without both renders the `_RouteSelectMisuse` fallback ("Pick a start and destination first."). See §16.

### Purpose
Resolves **line → direction → branch** into one unambiguous station sequence *before* an underground journey begins. Pre-selection is not a UX preference: discriminating between branches from sensors alone takes roughly three stops of evidence — long after the branch decision has already been made.

### Blocked states (`_Blocked`)
Each names the exact cause and what still works, then offers **"Use GPS Alarm Instead"**:

| Blocker | Message |
|---|---|
| `noTopologyData` | "Route data not installed" — no Underground line map in this build; includes the rebuild command `python tools/build_naptan_db.py --with-topology` |
| `notConnected` | "No direct route" — no single line connects the two stops |
| `noSensors` | "Sensors unavailable" — device has no motion sensor |

### Resolver flow (`_Resolver`)
1. **Journey header** — origin (`trip_origin_rounded`) → connector line → destination (`place_rounded`)
2. **"Which line?"** — only rendered when more than one line serves *both* endpoints. A single shared line is auto-selected rather than making the user tap the only choice
3. **"This line splits — which way?"** — the Kennington case. Only shown when topology says the line genuinely diverges between these stops. Each option shows a branch label + `next: <station>`. Explanatory copy: *"Both branches serve your line, so the app cannot tell them apart from sensors alone until it is too late."*
   - **Direction is derived, never asked** — only one ordering puts origin before destination
4. **Resolved plan** — `N stops` label + `_PlanPreview`: a dotted station list where the target stop renders in primary/w700. Legs with no timing prior get a `schedule_rounded` tooltip icon ("No timing data for this leg")
5. **No-barometer notice** — red-bordered warning when the device lacks a pressure sensor: *"Tracking will rely on timing alone and will wake you one stop early rather than risk overshooting."*
6. **Sensor logging toggle** — off by default; writes a per-journey CSV to the device for threshold calibration. Honest copy: *"Nothing is uploaded."*
7. **Start Tracking** button — becomes a disabled "Tracking Active". Before starting, asks for **radio-scan consent** once (`ProminentDisclosureDialog.showRadioScanConsent`); declining is not a blocker
8. **`FieldTestPanel`** — appears after tracking starts, only if logging was enabled

### Field Test Panel
Ground-truth marking for calibration. Deliberately large and single-tap — designed for one-handed use, standing on a moving train, without looking.
- **`ARRIVED AT PLATFORM`** — 64 dp full-width primary button, **heavy haptic feedback** on tap
- Secondary outlined pair: **Tunnel hold** · **Doors open**
- Live "N marked" counter + last-marker timestamp in green
- Selectable log directory path at the bottom

---

## 12. Onboarding Overlay

**File:** `presentation/onboarding/onboarding_overlay.dart`
**Trigger:** first launch only — gated on the `onboarding_shown` `SharedPreferences` flag; rendered in a `Stack` above the Dashboard.

Full-screen 82 % black scrim with a 3-page `PageView`:

| # | Icon | Title | Body |
|---|---|---|---|
| 1 | `search_rounded` | Search for your stop | Tap the search bar and find any bus stop, tube station or rail platform in the UK. |
| 2 | `sensors_rounded` | Arm your journey | Set your destination stop. StopSnoozer tracks your location in the background — even when the app is closed. |
| 3 | `notifications_active_rounded` | Get alerted when you arrive | Your phone rings and a full-screen alarm appears the moment you reach your stop. Never miss it. |

**Features:** 96 dp glowing circular icon per page · **Skip** link top-right · animated page dots (active dot stretches 6 → 20 dp) · button label changes `Next` → **`Get Started`** on the last page · marks the pref as shown on completion *or* skip.

---

## 13. Modal Sheets & Dialogs

### 13.1 `CreateAlarmSheet` — Add / Edit Commute Alarm
**File:** `presentation/calendar/components/create_alarm_sheet.dart` (1,078 lines — the largest UI file)
**Opened from:** Calendar `+ Add` button (create) and each alarm's ✎ button (edit, prefilled)
**Height:** up to 92 % of screen, scrollable, keyboard-aware (`viewInsets` padding)

| Section | Controls |
|---|---|
| **Departure Time** | Tappable row → themed `showTimePicker`; displays `08:15 AM` at 22 sp |
| **Destination** | Segmented toggle: **Single Stop** ↔ **Trip Group** |
| ↳ Single Stop | `_StopSearchField` — 400 ms debounced search with postcode detection, results sorted rail/tube-first, capped at 8, each with a mode emoji + indicator; ✕ clears the selection |
| ↳ Trip Group | Selectable list of saved groups (check icon on selection) + **`+ New Group`** |
| ↳ Inline group builder | Group-name field · stop search (capped at 6) · numbered stop list with ✕ removal · **Cancel** / **Save Group** |
| **Route Label** | Free-text field, e.g. "Office via Northern Line"; auto-fills from the stop or group name |
| **Schedule** | **Repeat weekly** switch. OFF → date row opening a themed `showDatePicker` (today → +365 days). ON → 7 weekday chips (M T W Th F Sa Su); enabling repeat with no days selected auto-selects Mon–Fri |
| **Save** | Full-width amber `Save Alarm` button |

**Validation SnackBars:** "Please select a trip group." · "Selected group has no stops." · "Please select a destination stop." · "Please select at least one day." · "Please pick a date for the one-off alarm." · "Add at least one stop to the group."

**Note:** this sheet uses its own hardcoded palette (`_bg`, `_card`, `_amber`, `_slate`, `_muted`, `_border`) rather than `ColorConstants`, so it stays amber regardless of the selected theme.

### 13.2 `ThemePickerSheet`
**File:** `presentation/shared/widgets/theme_picker_sheet.dart`
**Opened from:** Dashboard app bar 🎨 palette button

Two independently-selectable rows:
- **APP THEME** — 5 swatches (52×52 rounded tiles previewing each theme's `surfaceBase` + `primary` dot), with a 2 px primary border + 10 dp glow when selected, and the theme's first word as a caption. Selecting **also switches the Android launcher icon** (`PlatformChannelService.switchLauncherIcon`)
- **LOGO COLOUR** — 5 circular dots, chosen independently of the app theme

Both persist to `SharedPreferences` and apply instantly via `ThemeService` (a `ChangeNotifier` that mutates `ColorConstants` in place).

### 13.3 `_AddLegSheet` (Queue)
See §7 — "Search a Stop" tile + saved-group quick-load list.

### 13.4 `ProminentDisclosureDialog`
**File:** `presentation/shared/widgets/prominent_disclosure_dialog.dart`

Policy-critical consent dialog. **`barrierDismissible: false`** and wrapped in `PopScope(canPop: false)` — a back gesture resolves to `false`, so dismissal can never read as consent. The OS permission request is made **only** on a `true` result.

Layout: 48 dp icon tile · 19 sp title · body · a grey footer box · **Allow** (primary) · **Deny** (ghost).

| Variant | Title | Purpose |
|---|---|---|
| `showBackgroundLocation()` | "Location while the app is closed" | Play-mandated wording, shown immediately before the OS background-location prompt |
| `showRadioScanConsent()` | "Help StopSnoozer learn your stations" | PECR reg. 6 consent for reading nearby Wi-Fi/cell identifiers |

### 13.5 Small dialogs
- **Save as Trip Group** (Queue header) — text field + Cancel / Save
- **Leave queue?** (Queue back-nav) — Stay / Leave (red)

### 13.6 System pickers
- Android **time picker** — dark-themed via inline `ColorScheme.dark`
- Android **date picker** — same treatment
- Android **ringtone picker** — native, opened over the platform channel from Settings

---

## 14. Shared Widgets

| Widget | File | Description |
|---|---|---|
| `SnoozerButton` | `shared/widgets/snoozer_button.dart` | The app's only button primitive. 4 variants — **primary** (solid, 20 dp glow, radius 16), **secondary** (elevated fill), **ghost** (transparent), **danger** (red tint). Supports optional leading icon, loading spinner, disabled state, and full-width/hug sizing |
| `TransportModeIcon` | `shared/widgets/transport_mode_icon.dart` | Rounded tile with a mode icon at 15 % alpha tint. Maps 7 modes to icon + colour, plus a static `label()` helper (Tube · Bus · Rail · DLR · Overground · Tram · Ferry) |
| `ProminentDisclosureDialog` | `shared/widgets/prominent_disclosure_dialog.dart` | See §13.4 |
| `ThemePickerSheet` | `shared/widgets/theme_picker_sheet.dart` | See §13.2 |
| `ThemeScope` | `core/theme/theme_scope.dart` | `InheritedWidget` used by every screen (`ThemeScope.watch(context)`) to rebuild on theme change |

---

## 15. Design System

### Colour themes (`core/theme/app_themes.dart`)
5 dark themes, each defining `surfaceBase`, `surfaceSecondary`, `surfaceElevated`, `surfaceModal`, `primary`, `divider`, and three text tiers:

| # | Name | Background | Primary |
|---|---|---|---|
| 0 | **Solar Eclipse** *(default)* | `#0F1115` near-black | `#FFB000` amber |
| 1 | **Deep Navy** | `#070E1C` navy | `#38BDF8` sky blue |
| 2 | **Forest Night** | `#071A0A` dark green | `#4ADE80` emerald |
| 3 | **Volcanic** | `#1C0A08` crimson-black | `#FB7185` coral rose |
| 4 | **Galactic** | `#0D0B1F` indigo-violet | `#C084FC` amethyst |

`ThemeService` mutates the static fields on `ColorConstants` in place, then notifies listeners — that is why every screen calls `ThemeScope.watch(context)`.

### Never-themed colours
Semantic and transport colours stay constant across all themes:
- `success` `#4CAF50` · `error` `#FFB4AB`
- Transport tints: **tube/DLR/tram** `#10B981` green · **bus** `#FF6B6B` coral · **rail/overground** `#38BDF8` sky blue

### Spacing (8 px baseline grid)
`spaceXs 4` · `spaceSm 8` · `spaceMd 16` · `spaceLg 24` · `spaceXl 32` · `spaceXxl 48` · `containerMargin 24`

### Radii
`radiusSm 8` · `radiusMd 12` · `radiusLg 16` · `radiusXl 24` · `radiusFull 999`

### Motion
`durationFast 150 ms` · `durationNormal 300 ms` · `durationSlow 600 ms` · `durationPulse 1500 ms`

### Behavioural constants
| Constant | Value |
|---|---|
| Default wake radius | 500 m |
| Wake radius range | 100 – 1000 m (18 slider divisions) |
| Location poll interval | 5,000 ms |
| Wi-Fi scan interval | 8,000 ms |
| Slide-to-dismiss threshold | 0.9 |
| Search debounce | 300 ms |
| Search max results | 50 |
| Search radius (proximity) | 2.0 km |

### Typography
- **Sora** — headings, titles, buttons, numeric displays, badges (weights 600–900)
- **Inter** — body copy, descriptions, captions (weights 400–600)

---

## 16. Data Models Surfaced in the UI

| Model | Key UI-relevant fields |
|---|---|
| `StopPoint` | `id`, `name`, `latitude`, `longitude`, `mode` (7-value `TransitMode`), `lines`, `wifiSsid` (non-null ⇒ underground sensing), `indicator` (NaPTAN, e.g. "Stop A"), `distanceKm` |
| `TripLeg` | `stop`, `wakeRadiusMetres` (default 500), `alarmStyle` (`subtlePulse` / `defconDrill`), `status` (`queued` / `active` / `complete`) |
| `TripGroup` | `id`, `name`, `legs[]` — JSON-serialised for storage |
| `SavedLocation` | `stopId`, `stopName`, lat/lon, `mode`, `wifiSsid`, `radius`, `isActive` |
| `CommuteAlarm` | `departureHour`/`Minute`, stop details, `routeLabel`, `weekdays[]` (1=Mon…7=Sun), `specificDate` (one-off), `isActive`, `tripGroupId`. Derived getters: `timeLabel`, `modeEmoji`, `dayChips`, `specificDateLabel` |
| `AlarmEvent` | `stopId`, `stopName`, `firedAt`, `distanceMetres` — powers the Recent Activity history list |

---

## 17. Native Capabilities Reachable from the UI

Exposed through `PlatformChannelService` (`data/services/platform_channel_service.dart`, 31 methods + 1 stream):

| Group | Methods |
|---|---|
| **Tracking** | `startGeofence`, `startWifiSensing`, `startHybridSensing`, `updateTrackingTargets`, `stopTracking` |
| **Alarm control** | `alarmStream` (listener), `stopAlarm`, `snoozeAlarm`, `checkPendingAlarm` |
| **Commute scheduling** | `scheduleCommuteAlarm`, `cancelCommuteAlarm`, `checkPendingTripGroup` |
| **Permissions** | `checkBatteryOptimizationStatus`, `requestBatteryOptimizationExemption`, `checkFullScreenIntentPermission`, `requestFullScreenIntentPermission` |
| **Wi-Fi** | `checkWifiEnabled`, `openWifiSettings` |
| **Alarm preferences** | `getAlarmSettings`, `setAlarmSettings`, `openRingtonePicker` |
| **Underground** | `startUndergroundTracking`, `getUndergroundCapability` (barometer / accelerometer) |
| **Field testing** | `markGroundTruth`, `getSensorLogDir` |
| **Diagnostics** | `getAlarmDiagnostics`, `runAlarmSelfTest`, `cancelAlarmSelfTest`, `getOemBatteryInfo`, `openOemBatterySettings` |
| **Theming** | `switchLauncherIcon` |

---

## 18. Feature Matrix by Screen

| Feature | Splash | Dash | Search | Queue | Alarms | Settings | Alarm | RouteSel |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Permission requests | ✅ | | | | | ✅ | | |
| DB decompression + progress | ✅ | | | | | | | |
| Live location detection | | ✅ | | | | | | |
| Nearby-stop discovery | | ✅ | | | | | | |
| Offline stop search | | | ✅ | | ✅ | | | |
| Postcode geocoding | | | ✅ | | ✅ | | | |
| Transit-type filtering | | | ✅ | | | | | |
| Query highlighting | | | ✅ | | | | | |
| Duplicate disambiguation | | | ✅ | | | | | |
| Multi-leg queue + reorder | | | | ✅ | | | | |
| Wake-radius adjustment | | | | ✅ | | | | |
| Trip groups (save/load/delete) | | | | ✅ | ✅ | | | |
| Saved stops + parallel tracking | | ✅ | | | | | | |
| Swipe-to-delete | | ✅ | | | ✅ | | | |
| Journey timeline / leg status | | ✅ | | | | | | |
| Scheduled commute alarms | | | | | ✅ | | | |
| Weekly repeat + one-off dates | | | | | ✅ | | | |
| Alarm-fire history | | | | | ✅ | | | |
| Countdown + slide-to-dismiss | | | | | | | ✅ | |
| Snooze (5 / 10 min) | | | | | | | ✅ | |
| Alarm self-test | | | | | | ✅ | | |
| OEM battery-killer handling | | | | | | ✅ | | |
| Sensor diagnostics | | | | | | ✅ | | |
| Ringtone + alert-style prefs | | | | | | ✅ | | |
| Live DB statistics | | | | | | ✅ | | |
| Privacy consent + data erasure | | | | | | ✅ | | |
| Licence attribution | | | | | | ✅ | | |
| Theme + launcher-icon switching | | ✅ | | | | | | |
| Underground route pre-selection | | | | | | | | ✅ |
| Sensor logging / field test | | | | | | | | ✅ |
| Onboarding | | ✅ | | | | | | |

---

## 19. Known Gaps & Dead Code

Findings from reading the current source — recorded so they are not mistaken for working features.

**Unreachable route**
- `/route-select` is fully implemented (screen + cubit + topology repository + field-test panel) but **nothing navigates to it**. `grep` for `context.go('/route-select')` returns zero call sites. Underground route pre-selection is therefore inaccessible to users today.

**Unused components** — built, compiled, but referenced by no screen:
- `presentation/trip_config/components/alarm_style_toggle.dart` — consequently **per-leg alarm style (Subtle Pulse vs Defcon Drill) cannot be changed in the UI**, even though `TripLeg.alarmStyle` exists, is persisted in trip groups, and is passed to the native layer. Every leg uses the `defconDrill` default.
- `presentation/system_health/components/health_tab_bar.dart` — leftover from when Settings was a tabbed screen
- `presentation/system_health/components/permission_toggle_row.dart`
- `presentation/shared/widgets/snoozer_card.dart`
- `presentation/shared/widgets/app_logo.dart`

**Theme inconsistency**
- `CreateAlarmSheet`, `_AddLegSheet` and `_GroupCard` use hardcoded amber/slate colour constants instead of `ColorConstants`, so they do not follow the selected theme.

**Other observations**
- The app is **dark-mode only** — `AppTheme.dark` is the sole theme; there is no light palette.
- `StringConstants` retains several unused strings from removed features (`healthTabDashboard`, `healthDndTitle`, `healthDeadRecLabel`, `dashboardIdleBattery`, `searchHint`, …).
- `SystemHealthState.selectedTab` and `dndBypassEnabled` are vestigial — nothing reads them now that the tab bar and DND toggle are gone.

---

*End of reference.*
