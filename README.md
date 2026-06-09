# StopSnoozer

> **Never Miss Your Stop Again.**

StopSnoozer is a 100% offline, zero-backend geolocation alarm app built for UK public transit commuters. It tracks your multi-leg journey in real time and wakes you up before you miss your stop — whether you are above ground on a train or deep underground on the Tube.

---

## Features

- **Multi-leg trip playlists** — chain as many stops as you need in a single journey
- **GPS geofencing** — precise radius-based wake-up triggers above ground (100 m – 1,000 m configurable)
- **Underground Wi-Fi sensing** — detects station Wi-Fi SSIDs (e.g. `LUL-Free-Wifi`) when GPS is unavailable
- **iOS dead-reckoning fallback** — uses `CMMotionManager` accelerometer data to count platform stops when neither GPS nor Wi-Fi is available
- **Defcon or subtle alarm styles** — choose between a gentle pulse vibration or a full-volume wake-up drill per stop
- **Slide-to-dismiss alarm** — full-screen high-contrast alert with a drag-to-clear safety lock
- **Offline-first** — 15+ seeded UK NaPTAN transit stops bundled in a local SQLite database; designed to expand to 500,000+ records via a compressed `uk.db.gz` asset
- **Battery-aware** — foreground service with battery optimisation exemption request and DND bypass toggle
- **Zero map SDK** — no Google Maps API fees; entirely text and icon driven

---

## Architecture

This project follows a strict **MVVM** architecture with **BLoC/Cubit** as the ViewModel engine.

```
View (Widget)  →  observes  →  Cubit/State
Cubit          →  calls     →  Repository / Service
Repository     →  queries   →  DatabaseService / LocationService
Native layer   →  streams   →  LocationTrackingBloc via EventChannel
```

| Layer | Responsibility |
|---|---|
| **View** | Renders state from `BlocBuilder`. Zero business logic. |
| **Cubit (ViewModel)** | Owns state, handles user intent, calls data layer |
| **Repository** | Single access point for stop-point data |
| **Service** | SQLite, GPS, platform channels — all singletons |
| **BLoC** | `LocationTrackingBloc` — wires native EventChannel alarms directly into state transitions |

---

## Project Structure

```
lib/
├── main.dart
├── app/
│   ├── app.dart                          # MaterialApp.router
│   └── router/app_router.dart            # GoRouter — 6 named routes
├── core/
│   ├── constants/
│   │   ├── color_constants.dart          # Luminous Noir palette — every colour token
│   │   ├── string_constants.dart         # Every UI string — zero hardcoded text in views
│   │   ├── asset_constants.dart          # All asset paths
│   │   └── app_constants.dart            # Spacing, radii, durations, thresholds
│   ├── theme/app_theme.dart              # Full dark ThemeData (Sora + Inter fonts)
│   └── utils/
│       ├── distance_utils.dart           # Haversine distance + bounding-box
│       └── number_formatters.dart        # Metres, miles, percentage helpers
├── data/
│   ├── models/
│   │   ├── stop_point.dart               # StopPoint model (Equatable)
│   │   └── trip_leg.dart                 # TripLeg, AlarmStyle, LegStatus enums
│   ├── repositories/
│   │   └── stop_points_repository.dart   # Search + nearby stop queries
│   └── services/
│       ├── database_service.dart         # SQLite singleton with seeded UK stops
│       ├── location_service.dart         # Geolocator wrapper with isolate tracking
│       ├── platform_channel_service.dart # MethodChannel command dispatcher
│       └── location_tracking_bloc.dart   # Full BLoC — EventChannel → state stream
└── presentation/
    ├── shared/widgets/
    │   ├── snoozer_button.dart            # Reusable button (primary / secondary / ghost / danger)
    │   ├── snoozer_card.dart              # Reusable surface card with glow support
    │   └── transport_mode_icon.dart       # Transport mode icon + colour resolver
    ├── splash/                            # SplashCubit + 3 components
    ├── dashboard/                         # DashboardCubit + 5 components
    ├── search/                            # SearchCubit (debounced) + 2 components
    ├── trip_config/                       # TripConfigCubit + 4 components
    ├── alarm/                             # AlarmCubit + animated pulse + slide-to-dismiss
    └── system_health/                     # SystemHealthCubit + 3 components
```

---

## Screens

| Screen | Route | Description |
|---|---|---|
| Splash | `/splash` | Database init progress + permission requests |
| Dashboard | `/dashboard` | Active journey timeline, nearby transport chips |
| Search | `/search` | Debounced stop search with transport mode icons |
| Trip Config | `/trip-config` | Reorderable leg list, radius slider, alarm style toggle |
| Active Alarm | `/alarm` | Full-screen pulsing alert + slide-to-dismiss bar |
| System Health | `/system-health` | Sensor diagnostics, battery whitelist, DND bypass |

---

## Design System — Luminous Noir

| Token | Value | Usage |
|---|---|---|
| Primary (Amber) | `#FFB000` | Active states, CTAs, alarm glow |
| Surface Base | `#0F131D` | App background |
| Surface Secondary | `#1C1F2A` | Cards and list items |
| Surface Elevated | `#262A35` | Chips, toggles, elevated surfaces |
| Text Primary | `#DFE2F1` | Main readable text |
| Text Secondary | `#C1C7CF` | Labels and captions |
| Error (Coral) | `#FFB4AB` | Alarm state, slide-to-dismiss |
| Success (Green) | `#4CAF50` | Online sensors, granted permissions |

**Fonts:** Sora (headlines / labels) · Inter (body / captions)

---

## Dependencies

| Package | Purpose |
|---|---|
| `flutter_bloc` | Cubit/BLoC state management |
| `go_router` | Declarative navigation with deep-link support |
| `sqflite` + `path_provider` | Local SQLite database |
| `geolocator` | GPS location stream |
| `permission_handler` | Runtime permission requests |
| `google_fonts` | Sora + Inter font loading |
| `equatable` | Value equality for models and states |
| `provider` | BlocProvider composition in router |

---

## Platform Support

### Android
- **Min SDK:** Flutter default (API 21+)
- **Foreground Service:** `SnoozeTrackingService.java` — persists tracking when app is backgrounded
- **Above ground:** `FusedLocationProviderClient` with 5 s update interval
- **Underground:** `WifiManager` SSID scan loop every 8 s via `BroadcastReceiver`
- **Alarm dispatch:** Broadcasts `com.stopsnoozer.app.ALARM_TRIGGER` intent and launches app directly to `/alarm` route
- **16 KB page-size compliant** — uses only platform SDK calls, no custom native libraries

### iOS
- **Above ground:** `CLCircularRegion` monitoring — iOS kernel wakes the app even when fully suspended at 0% battery draw
- **Underground:** `CMMotionManager` device motion at 10 Hz; counts acceleration → stationary transitions to detect platform arrivals
- **Fallback:** 7-minute fixed timer per stop if motion hardware is unavailable
- **Haptic feedback:** `UINotificationFeedbackGenerator` repeating every 1 s until alarm is dismissed

---

## Getting Started

### Prerequisites
- Flutter SDK `>=3.11.5`
- Dart SDK `>=3.11.5`
- Android Studio or Xcode (for device/simulator builds)

### Install & Run

```bash
# Clone and install dependencies
flutter pub get

# Run on connected device or emulator
flutter run
```

### Adding the UK Stops Database

Place the compressed NaPTAN database at `assets/data/uk.db.gz` to replace the seeded mock stops. The app will automatically detect and decompress it on first launch via `DatabaseService`.

---

## Permissions Required

| Permission | Platform | Reason |
|---|---|---|
| `ACCESS_FINE_LOCATION` + `ACCESS_BACKGROUND_LOCATION` | Android | GPS geofencing |
| `ACCESS_WIFI_STATE` | Android | Underground SSID scanning |
| `FOREGROUND_SERVICE_LOCATION` | Android | Persistent background tracking |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Android | Prevent OS from killing the service |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | iOS | Background region monitoring |
| `NSMotionUsageDescription` | iOS | Dead-reckoning stop detection |

---

## License

Private — all rights reserved.
