# Android Folder — Full Code Explanation

This document explains every updated file inside `android/app/src/main/`, what each line does, why it exists, and exactly how it connects to the Flutter/Dart code in `lib/`.

---

## How Android and Flutter Talk to Each Other

Flutter is a cross-platform framework. It cannot directly call Android APIs. The bridge is called a **Platform Channel**. There are two kinds used here:

| Channel type | Dart side | Android side | Direction |
|---|---|---|---|
| `MethodChannel` | `_method.invokeMethod(...)` | `setMethodCallHandler` | Dart → Android (one-time call/response) |
| `EventChannel` | `_alarm.receiveBroadcastStream()` | `setStreamHandler` | Android → Dart (continuous stream) |

Both channels use a string name as identifier. The names must match exactly on both sides:

- **MethodChannel name:** `com.stopsnoozer.app/location`
- **EventChannel name:** `com.stopsnoozer.app/alarm_stream`

The single Dart file that owns both channels is:
`lib/data/services/platform_channel_service.dart` → `PlatformChannelService`

---

## File 1 — `AndroidManifest.xml`

**Path:** `android/app/src/main/AndroidManifest.xml`
**Purpose:** The operating system reads this file before launching the app. It declares every permission the app needs, every Android component (Activity, Service, BroadcastReceiver), and metadata Flutter needs.

### Line-by-line

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
```
Root tag. `xmlns:android` declares the XML namespace so all `android:` attributes are valid.

---

### Permissions block

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```
Allows the app to start a foreground service (`SnoozeTrackingService`). Without this, `startForeground()` crashes on Android 9+.

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```
Android 14 (API 34) introduced fine-grained foreground service types. Because the service declares `foregroundServiceType="location"`, this specific permission is also required.

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```
GPS-level location. Required for the `FusedLocationProviderClient` GPS requests inside `SnoozeTrackingService`.

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```
Cell/WiFi triangulation level location. Required for the network location fallback callback in `startAboveGroundTracking()`.

```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```
Allows location access while the app is NOT in the foreground. This is what lets the tracking service keep polling GPS even when the user is looking at another app or the screen is off.

```xml
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```
Allows reading the list of visible WiFi networks. Used by `wifiManager.getScanResults()` in the underground/subterranean tracking mode.

```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
```
Allows triggering a new WiFi scan via `wifiManager.startScan()`. Without this, the app can only read cached results.

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
```
Keeps the CPU running while the foreground service is active. Prevents the phone from sleeping and missing a GPS fix when the screen is off.

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```
Android 13+ requires explicit permission to show any notification. Required for the tracking notification and alarm notification posted by `SnoozeTrackingService`.

```xml
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```
Allows the app to ask the user to exclude it from Doze/battery optimisation. Dart side calls `requestBatteryOptimization` through the MethodChannel.

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```
Allows `BootReceiver` to be woken up after the phone restarts. Without this, the broadcast `ACTION_BOOT_COMPLETED` would never reach the app.

```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```
Android 14+ requires explicit declaration to show a full-screen notification (the lock-screen alarm). Used in `showAlarmNotification()`.

```xml
<uses-permission android:name="android.permission.INTERNET" />
```
Network access. Needed by the Google Play Services location library (FusedLocationProviderClient) which uses Google servers for WiFi positioning.

```xml
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```
Android 13+ (API 33+) allows exact alarms without asking the user. Exact alarms are needed by `AlarmScheduler.setAlarmClock()` so alarms fire at precisely the right time even in Doze.

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"
    android:maxSdkVersion="32" />
```
Same concept but for Android 12 and below (API ≤ 32). `maxSdkVersion="32"` means this declaration is ignored on API 33+ where `USE_EXACT_ALARM` takes over instead.

---

### `<application>` block

```xml
android:label="StopSnoozer"
```
The app name shown on the home screen and in the app drawer.

```xml
android:name="${applicationName}"
```
The application class. Flutter replaces this placeholder at build time with its own `FlutterApplication` class which initialises the Flutter engine.

```xml
android:icon="@mipmap/ic_launcher"
```
The default square launcher icon. Points to the PNG files in `mipmap-mdpi`, `mipmap-hdpi`, etc., or the adaptive icon XML in `mipmap-anydpi-v26/`.

```xml
android:roundIcon="@mipmap/ic_launcher_round"
```
The circular version used on launchers that display round icons (Pixel, Samsung One UI). Added in a recent commit alongside the round variants for every theme.

---

### Main Activity

```xml
<activity android:name=".MainActivity" ... >
```
Declares the main Flutter activity. `.MainActivity` is shorthand for `com.stopsnoozer.app.MainActivity`.

```xml
android:exported="true"
```
Allows Android to launch this activity from outside the app (e.g., from a notification tap).

```xml
android:launchMode="singleTop"
```
If `MainActivity` is already at the top of the back stack, Android reuses it instead of creating a new instance. This is why `onNewIntent()` exists in `MainActivity.kt` — to handle the alarm intent when the activity is already open.

```xml
android:taskAffinity=""
```
Empty task affinity prevents the app from sharing a task with any other app, isolating its back stack.

```xml
android:configChanges="orientation|keyboardHidden|..."
```
Lists every configuration change that Flutter wants to handle itself (in Dart) without Android destroying and recreating the Activity. Standard Flutter boilerplate.

```xml
android:windowSoftInputMode="adjustResize"
```
When the keyboard appears, the layout resizes to accommodate it. Required by Flutter for proper text field behaviour.

```xml
<meta-data android:name="io.flutter.embedding.android.NormalTheme" ... />
```
Tells the Flutter engine to switch from the launch splash theme to the normal app theme once Flutter is ready to render. Flutter boilerplate.

```xml
<intent-filter>
    <action android:name="com.stopsnoozer.app.ALARM_TRIGGER" />
    <category android:name="android.intent.category.DEFAULT" />
</intent-filter>
```
Lets the Activity be started directly by an alarm intent containing the action string `com.stopsnoozer.app.ALARM_TRIGGER`. This is how the alarm notification's tap opens the app on top of the lock screen.

---

### Activity-alias block (launcher icon switching)

Each `<activity-alias>` is a "virtual" launcher shortcut pointing to the real `.MainActivity`.

```xml
<activity-alias android:name=".MainActivityAlias_Amber" ... android:enabled="true">
```
The **Amber** alias. `android:enabled="true"` means this is the currently visible launcher icon. All other aliases start with `android:enabled="false"`.

```xml
android:icon="@mipmap/ic_launcher"
android:roundIcon="@mipmap/ic_launcher_round"
```
Points to the Amber-theme adaptive icon XML files.

```xml
<activity-alias android:name=".MainActivityAlias_Navy" ... android:enabled="false">
    android:icon="@mipmap/ic_launcher_navy"
    android:roundIcon="@mipmap/ic_launcher_round_navy">
```
Navy theme. Disabled by default. `MainActivity.kt`'s `switchLauncherIcon(1)` enables this and disables Amber.

The same pattern repeats for Forest (index 2), Volcanic (index 3), Galactic (index 4).

**How Dart triggers this:** `ThemeService.setTheme(index)` calls `PlatformChannelService.instance.switchLauncherIcon(index)` → MethodChannel → `switchLauncherIcon()` in `MainActivity.kt`.

---

### Service and Receivers

```xml
<service android:name=".SnoozeTrackingService"
    android:exported="false"
    android:stopWithTask="false"
    android:foregroundServiceType="location" />
```
- `exported="false"` — only this app can start the service, not other apps.
- `stopWithTask="false"` — the service keeps running even when the user swipes the app from Recents. `SnoozeTrackingService.onTaskRemoved()` also schedules an AlarmManager ping as a backup.
- `foregroundServiceType="location"` — required on Android 10+ so the OS knows why this service needs a foreground notification.

```xml
<receiver android:name=".CommuteAlarmReceiver" android:exported="false" />
```
`AlarmScheduler` sends broadcast intents to this receiver when a scheduled alarm fires. `exported="false"` is safe because the AlarmManager intent is sent internally.

```xml
<receiver android:name=".BootReceiver" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```
`exported="true"` is required for system broadcasts. `BOOT_COMPLETED` fires after a normal reboot. `QUICKBOOT_POWERON` fires after a fast-boot (some HTC/Huawei devices).

```xml
<meta-data android:name="flutterEmbedding" android:value="2" />
```
Tells Flutter to use the v2 embedding API (current standard). Flutter boilerplate.

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.PROCESS_TEXT" />
        <data android:mimeType="text/plain" />
    </intent>
</queries>
```
Android 11+ package visibility: declares that this app queries for apps that handle text selection actions. Flutter inserts this automatically to support copy/paste context menus.

---

## File 2 — `MainActivity.kt`

**Path:** `android/app/src/main/kotlin/com/stopsnoozer/app/MainActivity.kt`
**Purpose:** The single Activity of the app. Hosts the Flutter UI. Implements the MethodChannel (Dart calls into Android) and the EventChannel (Android pushes alarm events to Dart).

### Imports

```kotlin
import android.app.Activity
import android.app.NotificationManager
```
`Activity` is needed for `RESULT_OK` in `onActivityResult` (ringtone picker). `NotificationManager` is used to check `canUseFullScreenIntent()` on Android 14.

```kotlin
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
```
- `BroadcastReceiver` — local receiver that listens for alarm trigger broadcasts from the service.
- `ComponentName` — used to enable/disable activity-aliases by their fully-qualified class name.
- `PackageManager` — `setComponentEnabledSetting()` switches which alias is active.

```kotlin
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
```
- `RingtoneManager` — opens the system alarm ringtone picker.
- `Build` — version checks for API-level-specific code paths.
- `PowerManager` — `isIgnoringBatteryOptimizations()` check.

```kotlin
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
```
- `FlutterActivity` — the base class. Provides the Flutter rendering surface and engine lifecycle.
- `FlutterEngine` — the Dart VM + rendering pipeline. Channel objects need the engine's `binaryMessenger`.

---

### Companion Object

```kotlin
companion object {
    private const val LOCATION_CHANNEL     = "com.stopsnoozer.app/location"
    private const val ALARM_CHANNEL         = "com.stopsnoozer.app/alarm_stream"
    private const val REQUEST_CODE_RINGTONE = 42
}
```
- `LOCATION_CHANNEL` — must match `_method` in `PlatformChannelService`.
- `ALARM_CHANNEL` — must match `_alarm` in `PlatformChannelService`.
- `REQUEST_CODE_RINGTONE = 42` — arbitrary integer used to identify the ringtone picker in `onActivityResult`.

```kotlin
private var pendingRingtoneResult: MethodChannel.Result? = null
```
Holds the pending Dart `result` callback while the native ringtone picker is open. The picker is asynchronous — the method call returns only when the picker closes.

---

### Lock screen behaviour

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    if (intent?.getBooleanExtra("alarmFromService", false) == true) {
        applyAlarmWindowFlags()
    }
    super.onCreate(savedInstanceState)
}
```
Called when Android creates the Activity. Checks if it was launched by a notification that includes `alarmFromService = true` (set in `SnoozeTrackingService.showAlarmNotification()`). If so, applies flags before `super.onCreate()` so the window is configured before Flutter renders.

```kotlin
override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    if (intent.getBooleanExtra("alarmFromService", false)) {
        applyAlarmWindowFlags()
    }
}
```
Called when the Activity already exists (because of `launchMode="singleTop"`) and receives a new intent. Same check — an alarm notification tap while the app is open.

```kotlin
private fun applyAlarmWindowFlags() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
        setShowWhenLocked(true)
        setTurnScreenOn(true)
    } else {
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )
    }
}
```
- `setShowWhenLocked(true)` (API 27+) — draws the activity over the lock screen.
- `setTurnScreenOn(true)` (API 27+) — wakes the screen when the activity is shown.
- Below API 27, the deprecated `WindowManager.LayoutParams` flags achieve the same result.

---

### configureFlutterEngine

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    setupMethodChannel(flutterEngine)
    setupAlarmEventChannel(flutterEngine)
}
```
Called by Flutter after the engine is initialised. This is the correct place to register channels because the `binaryMessenger` is ready.

---

### setupMethodChannel — every case

```kotlin
MethodChannel(engine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
    .setMethodCallHandler { call, result -> ... }
```
Registers a handler. For every `invokeMethod(name, args)` call from Dart, Android receives `call.method` (the name) and `call.argument<T>(key)` (each argument). It must call `result.success(value)`, `result.error(code, msg, detail)`, or `result.notImplemented()`.

#### `startGeofence`
```kotlin
"startGeofence" -> {
    val intent = Intent(this, SnoozeTrackingService::class.java).also {
        it.action = SnoozeTrackingService.ACTION_START_GEOFENCE
        it.putExtra("stopId",       call.argument<String>("stopId")     ?: "")
        it.putExtra("stopName",     call.argument<String>("stopName")   ?: "")
        it.putExtra("lat",          call.argument<Double>("lat")        ?: 0.0)
        it.putExtra("lon",          call.argument<Double>("lon")        ?: 0.0)
        it.putExtra("radiusMetres", (call.argument<Double>("radiusMetres") ?: 500.0).toFloat())
        it.putExtra("alarmStyle",   call.argument<String>("alarmStyle") ?: "defconDrill")
    }
    ContextCompat.startForegroundService(this, intent)
    result.success(null)
}
```
Builds an Intent directed at `SnoozeTrackingService`, sets the action to `ACTION_START_GEOFENCE`, and packs every argument from Dart into Intent extras. `ContextCompat.startForegroundService` is used (instead of `startService`) because the service must display a notification immediately — required for foreground services on API 26+.

#### `startWifiSensing`
Same structure. Action is `ACTION_START_WIFI`. No `lat/lon/radius/alarmStyle` needed — only `targetSsid` for the underground SSID match.

#### `updateTrackingTargets`
```kotlin
val targetsJson = try {
    val list = call.argument<List<Map<String, Any?>>>("targets") ?: emptyList()
    org.json.JSONArray(list.map { org.json.JSONObject(it.filterValues { v -> v != null } as Map<*, *>) }).toString()
} catch (_: Exception) { "[]" }
```
Dart sends a `List<Map<String,dynamic>>`. This code converts it into a JSON string because Intents cannot hold arbitrary nested Dart objects — a `String` extra can survive Intent delivery across processes. `filterValues { v -> v != null }` strips null values so `JSONObject` does not crash.

#### `startHybridSensing`
Combines GPS + WiFi. Passes all parameters: `lat/lon/radius` (for GPS geofencing) and `targetSsid` (for underground WiFi). Action is `ACTION_START_HYBRID`.

#### `stopTracking`
Sends `ACTION_STOP` to the service. The service then calls `dismissAlarm()` → `stopSensors()` → `stopSelf()`.

#### `stopAlarm`
Sends `ACTION_STOP_ALARM`. Like `stopTracking` but only stops the alarm sound and notification; it does not stop location tracking if remaining targets exist.

#### `snoozeAlarm`
```kotlin
val minutes = call.argument<Int>("minutes") ?: 5
```
Reads the snooze duration from Dart (default 5). Sends `ACTION_SNOOZE` with `EXTRA_SNOOZE_MINUTES`. The service silences the ringtone and re-arms tracking after the delay.

#### `checkWifiEnabled`
```kotlin
val wm = applicationContext.getSystemService(WIFI_SERVICE) as android.net.wifi.WifiManager
result.success(wm.isWifiEnabled)
```
Returns a boolean to Dart. `applicationContext` is used (not `this`) because `WifiManager` must be obtained from the application context on some devices.

#### `openWifiSettings`
Opens the system WiFi settings screen via a standard Android intent action. Dart calls this when `checkWifiEnabled()` returns false and the user needs to turn WiFi on.

#### `checkBatteryOptimization`
```kotlin
val pm = getSystemService(POWER_SERVICE) as PowerManager
result.success(pm.isIgnoringBatteryOptimizations(packageName))
```
Returns `true` if the app is already excluded from battery optimisation (Doze). Dart uses this to know whether to show the "disable battery optimisation" prompt.

#### `requestBatteryOptimization`
Checks the same flag. If not already excluded, opens the system dialog that lets the user whitelist the app. Returns the current state after the intent is fired (the dialog is async, so the returned value may still be `false` until the user confirms).

#### `openRingtonePicker`
```kotlin
pendingRingtoneResult = result
val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
    putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,  false)
    putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select Alarm Tone")
    if (curUri != null) putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(curUri))
}
startActivityForResult(intent, REQUEST_CODE_RINGTONE)
```
The result object is saved because `startActivityForResult` is asynchronous — the method call returns only inside `onActivityResult`. The existing ringtone URI is pre-selected in the picker. `TYPE_ALARM` filters the list to alarm tones only.

#### `getAlarmSettings`
Reads from `SharedPreferences` under key `PREFS_NAME` (`snoozer_prefs`). Returns a Map with `alarmType`, `ringtoneUri`, `ringtoneName`. Dart reads this at app start to display the user's previously chosen alarm sound.

#### `setAlarmSettings`
Writes `alarmType`, `ringtoneUri`, `ringtoneName` into `SharedPreferences`. Dart calls this when the user changes their alarm settings in the settings screen.

#### `canUseFullScreenIntent`
```kotlin
val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    nm.canUseFullScreenIntent()
} else { true }
```
Android 14 (API 34, code name "Upside Down Cake") added runtime permission for full-screen intents. Below 14, returns `true` always. Dart calls this in the system health screen.

#### `requestFullScreenIntent`
Opens the special settings page (`android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENTS`) introduced in Android 14. Below 14, does nothing.

#### `scheduleCommuteAlarm`
```kotlin
AlarmScheduler.scheduleAndSave(
    this, id, hour, minute,
    stopId, stopName, lat, lon,
    ssid, radius, weekdays, specDate, tripGroupId
)
```
Passes all alarm parameters to `AlarmScheduler`. `weekdays` arrives as a JSON string (`"[1,3,5]"` = Mon/Wed/Fri). `specificDate` is a `"YYYY-MM-DD"` string for one-off alarms. `tripGroupId` links all legs of a multi-stop journey so Dart can reload them when the app wakes up.

#### `checkPendingTripGroup`
```kotlin
val tripGroupId = prefs.getString("pending_trip_group_id", null)
if (tripGroupId != null) prefs.edit().remove("pending_trip_group_id").apply()
result.success(tripGroupId)
```
`CommuteAlarmReceiver` writes `pending_trip_group_id` into SharedPreferences when a group alarm fires. This method reads and clears it. Dart calls this on app resume (in `SplashViewModel`) to load the correct trip.

#### `cancelCommuteAlarm`
Delegates to `AlarmScheduler.cancelAndRemove(this, id)` which cancels the PendingIntent and removes the alarm from the persisted JSON.

#### `checkPendingAlarm`
```kotlin
val stopId = prefs.getString("pending_alarm_stop_id", null)
```
`SnoozeTrackingService.triggerAlarm()` writes alarm data to SharedPreferences before broadcasting — this is a fallback for when the app is killed before the broadcast arrives. Dart calls this on startup to show the alarm screen if needed. The data is cleared once read.

#### `switchLauncherIcon`
```kotlin
val index = call.argument<Int>("index") ?: 0
switchLauncherIcon(index)
```
Passes the theme index to `switchLauncherIcon()` (described below). Dart calls this from `ThemeService.setTheme()`.

---

### onActivityResult — Ringtone picker result

```kotlin
val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
} else {
    data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
}
```
Android 13 (Tiramisu) deprecated the single-argument `getParcelableExtra`. The type-safe version is used on API 33+ with the `Uri::class.java` hint.

```kotlin
val name = try {
    RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Selected Alarm"
} catch (_: Exception) { "Selected Alarm" }
```
Resolves the human-readable ringtone name from the URI. Falls back to "Selected Alarm" if anything fails.

```kotlin
getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE).edit()
    .putString(SnoozeTrackingService.PREF_RINGTONE_URI,  uri.toString())
    .putString(SnoozeTrackingService.PREF_RINGTONE_NAME, name)
    .apply()
pending.success(mapOf("uri" to uri.toString(), "name" to name))
```
Persists the ringtone immediately into the same SharedPreferences the service reads at alarm time. Then resolves the pending Dart `result` with a Map containing the URI string and name.

---

### switchLauncherIcon

```kotlin
private fun switchLauncherIcon(themeIndex: Int) {
    val aliases = listOf(
        "com.stopsnoozer.app.MainActivityAlias_Amber",
        "com.stopsnoozer.app.MainActivityAlias_Navy",
        "com.stopsnoozer.app.MainActivityAlias_Forest",
        "com.stopsnoozer.app.MainActivityAlias_Volcanic",
        "com.stopsnoozer.app.MainActivityAlias_Galactic"
    )
    val pm = packageManager
    aliases.forEachIndexed { i, alias ->
        val state = if (i == themeIndex)
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        else
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        pm.setComponentEnabledSetting(
            ComponentName(this, alias),
            state,
            PackageManager.DONT_KILL_APP
        )
    }
}
```
- The `aliases` list index matches the theme index in `ThemeService.all[]` (0=Amber, 1=Navy, 2=Forest, 3=Volcanic, 4=Galactic).
- For every alias, it either enables or disables it with `setComponentEnabledSetting`.
- `DONT_KILL_APP` prevents Android from killing the process when the launcher icon changes. Without this flag, changing the icon would restart the app.
- The result: the home screen launcher icon changes immediately to the selected theme's icon.

---

### setupAlarmEventChannel

```kotlin
EventChannel(engine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
    .setStreamHandler(object : EventChannel.StreamHandler {
        private var receiver: BroadcastReceiver? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    val payload = mapOf(
                        "stopId"         to (intent.getStringExtra("stopId")   ?: ""),
                        "stopName"       to (intent.getStringExtra("stopName") ?: ""),
                        "distanceMetres" to intent.getFloatExtra("distanceMetres", 0f).toDouble(),
                        "firedAt"        to intent.getLongExtra("firedAt", 0L),
                        "countdownSecs"  to intent.getIntExtra("countdownSecs", 5)
                    )
                    events.success(payload)
                }
            }
            ContextCompat.registerReceiver(
                this@MainActivity, receiver,
                IntentFilter(SnoozeTrackingService.ACTION_ALARM_TRIGGER),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
        }

        override fun onCancel(arguments: Any?) {
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            receiver = null
        }
    })
```
- `onListen` is called when Dart subscribes with `receiveBroadcastStream()`.
- A `BroadcastReceiver` is registered at that point to listen for `ACTION_ALARM_TRIGGER` broadcasts sent by `SnoozeTrackingService.triggerAlarm()`.
- When the broadcast arrives, `events.success(payload)` pushes the Map down the stream to Dart.
- `RECEIVER_NOT_EXPORTED` means only broadcasts from this same app can be received (security).
- `onCancel` is called when Dart cancels the subscription. The receiver is unregistered to prevent leaks.
- On the Dart side, `PlatformChannelService.alarmStream` returns this as a `Stream<Map<String,dynamic>>`, which `DashboardViewModel` or alarm viewmodels listen to.

---

## File 3 — `AlarmScheduler.java`

**Path:** `android/app/src/main/java/com/stopsnoozer/app/AlarmScheduler.java`
**Purpose:** Handles scheduled commute alarms. Persists alarm data to SharedPreferences and registers exact-time alarms via `AlarmManager.setAlarmClock()`.

### Why `setAlarmClock()`?
Android has several alarm APIs:
- `set()` — inexact, batched, can fire late.
- `setExact()` — exact, but silenced in Doze.
- `setAndAllowWhileIdle()` — exact, fires in Doze but only once every ~9 minutes.
- `setAlarmClock()` — fires **even in deep Doze** and shows a **clock icon in the Android status bar**. This is the correct API for user-visible, time-critical alarms.

### Constants

```java
static final String PREFS_NAME = "commute_alarm_schedules";
static final String KEY_ALARMS = "scheduled_alarms";
```
Separate SharedPreferences file (not shared with `SnoozeTrackingService`). `KEY_ALARMS` stores a JSON object where each key is an `alarmId` and the value is the alarm's full configuration.

---

### `scheduleAndSave()`

```java
save(ctx, alarmId, hour, minute, stopId, stopName, lat, lon, ssid, radius, weekdaysJson, specificDate, tripGroupId);
```
Persists the alarm first. This way, even if the process is killed before `AlarmManager` fires, `rescheduleAllFromPrefs()` can restore it after reboot.

```java
long fireAt = nextFireTime(hour, minute, weekdaysJson, specificDate);
if (fireAt < 0) return;
```
Calculates the next UTC millisecond when this alarm should fire. Returns -1 if the date is in the past (one-off) or no weekday matches — in that case the alarm is saved but not registered.

```java
PendingIntent trigger = buildPendingIntent(ctx, alarmId, ...);
```
The broadcast that fires when the alarm triggers. Points to `CommuteAlarmReceiver`.

```java
Intent launchIntent = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
PendingIntent showPi = PendingIntent.getActivity(ctx, 0, launchIntent != null ? launchIntent : new Intent(), PendingIntent.FLAG_IMMUTABLE);
```
`AlarmManager.AlarmClockInfo` requires a second `PendingIntent` that is shown to the user if they tap the clock icon in the status bar. Here it opens the main app.

```java
am.setAlarmClock(new AlarmManager.AlarmClockInfo(fireAt, showPi), trigger);
```
Registers the alarm. `AlarmClockInfo` wraps both the fire-time and the show-intent.

---

### `cancelAndRemove()`

```java
PendingIntent pi = PendingIntent.getBroadcast(ctx, Math.abs(alarmId.hashCode()), intent,
        PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
if (pi != null && am != null) am.cancel(pi);
remove(ctx, alarmId);
```
`FLAG_NO_CREATE` returns `null` if no matching PendingIntent exists (meaning the alarm was never registered or already fired). `Math.abs(alarmId.hashCode())` converts the string ID into an integer request code — the same value used when registering, so Android can match them. After cancelling, the JSON entry is also removed from SharedPreferences.

---

### `rescheduleNext()`

Called by `CommuteAlarmReceiver` after a recurring alarm fires. Reads the alarm's data from SharedPreferences and calls `scheduleAndSave()` again. `nextFireTime()` will calculate the next occurrence (e.g., next Monday if today's Monday alarm just fired).

---

### `rescheduleAllFromPrefs()`

Called by `BootReceiver` after device reboot. Reads every alarm from SharedPreferences and re-registers all of them with `AlarmManager`. Required because `AlarmManager` is cleared when the device powers off.

---

### `save()` helper

Builds a `JSONObject` for the alarm and stores it under the `alarmId` key inside the master `JSONObject`. Writing the whole string back each time is simple and safe for the small number of alarms users typically create.

---

### `nextFireTime()`

```java
// ── One-off date ──
if (specificDate != null && !specificDate.isEmpty()) {
    String[] parts = specificDate.split("-");
    target.set(Calendar.YEAR,         Integer.parseInt(parts[0]));
    target.set(Calendar.MONTH,        Integer.parseInt(parts[1]) - 1);  // Calendar months are 0-based
    target.set(Calendar.DAY_OF_MONTH, Integer.parseInt(parts[2]));
    return target.getTimeInMillis() > now.getTimeInMillis()
            ? target.getTimeInMillis() : -1;
}
```
Parses `"YYYY-MM-DD"`. `Calendar.MONTH` is zero-based (January = 0), so `-1` is applied.

```java
// ── Weekly recurring ──
for (int offset = 0; offset <= 7; offset++) {
    Calendar candidate = (Calendar) target.clone();
    if (offset > 0) candidate.add(Calendar.DAY_OF_MONTH, offset);

    int calDow = candidate.get(Calendar.DAY_OF_WEEK);
    int ourDow = calDow > 1 ? calDow - 1 : 7;   // 1=Mon … 7=Sun
```
`offset=0` checks today. Iterating through 7 days guarantees the next matching weekday is found. `Calendar.DAY_OF_WEEK` is `SUNDAY=1 … SATURDAY=7`. The Flutter model uses `1=Mon … 7=Sun`. The conversion `calDow > 1 ? calDow - 1 : 7` maps Sunday from `1` to `7` and shifts all others down by 1.

```java
    if (days.getInt(d) == ourDow && candidate.getTimeInMillis() > now.getTimeInMillis()) {
        return candidate.getTimeInMillis();
    }
```
Both conditions must hold: the weekday matches AND the time is in the future (so today's alarm at 7am doesn't fire again at 7:01am).

---

### `buildPendingIntent()` helper

```java
return PendingIntent.getBroadcast(ctx, Math.abs(alarmId.hashCode()), i,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
```
`FLAG_UPDATE_CURRENT` replaces any existing PendingIntent with the same request code, updating the extras. `FLAG_IMMUTABLE` prevents other apps from modifying the intent. The request code is the same hash as used in `cancelAndRemove`, ensuring uniqueness per alarm.

---

## File 4 — `SnoozeTrackingService.java`

**Path:** `android/app/src/main/java/com/stopsnoozer/app/SnoozeTrackingService.java`
**Purpose:** The core background service. Tracks the user's location (GPS) or underground station proximity (WiFi) and fires the alarm when they arrive. Keeps the alarm sound playing until dismissed.

### Action constants

```java
static final String ACTION_START_GEOFENCE = "com.stopsnoozer.app.START_GEOFENCE";
static final String ACTION_START_WIFI     = "com.stopsnoozer.app.START_WIFI";
static final String ACTION_START_HYBRID   = "com.stopsnoozer.app.START_HYBRID";
static final String ACTION_UPDATE_TARGETS = "com.stopsnoozer.app.UPDATE_TARGETS";
static final String ACTION_ADD_TARGET     = "com.stopsnoozer.app.ADD_TARGET";
static final String ACTION_STOP           = "com.stopsnoozer.app.STOP_TRACKING";
static final String ACTION_ALARM_TRIGGER  = "com.stopsnoozer.app.ALARM_TRIGGER";
static final String ACTION_STOP_ALARM     = "com.stopsnoozer.app.STOP_ALARM";
static final String ACTION_SNOOZE         = "com.stopsnoozer.app.SNOOZE_ALARM";
static final String EXTRA_SNOOZE_MINUTES  = "snoozeMinutes";
```
Action strings must be unique per application. `static final` makes them accessible from `MainActivity.kt` without creating a service instance.

### SharedPreferences keys

```java
static final String PREFS_NAME         = "snoozer_prefs";
static final String PREF_ALARM_TYPE    = "alarm_type";
static final String PREF_RINGTONE_URI  = "alarm_ringtone_uri";
static final String PREF_RINGTONE_NAME = "alarm_ringtone_name";
private static final String PREF_TRACKING_ACTION    = "tracking_action";
private static final String PREF_TARGETS_JSON       = "tracking_targets_json";
private static final String PREF_TRACKING_STOP_ID   = "tracking_stop_id";
...
```
Tracking state keys (`PREF_TRACKING_*`) are private because only this service reads/writes them. The alarm settings keys (`PREF_ALARM_*`) are package-private because `MainActivity` also reads them for the ringtone picker.

### State fields

```java
private FusedLocationProviderClient fusedClient;
private LocationCallback locationCallback;            // GPS callback
private LocationCallback networkLocationCallback;     // WiFi/cell fallback
private WifiManager wifiManager;
private BroadcastReceiver wifiScanReceiver;
private Handler wifiScanHandler;
private Runnable wifiScanRunnable;
private Ringtone alarmRingtone;
private Handler soundHandler;
private Runnable pendingSoundRunnable;
private volatile boolean alarmFired = false;
private String currentAlarmStyle = "defconDrill";
```
- `fusedClient` — Google's fused location provider, combines GPS + network + sensor fusion.
- `volatile boolean alarmFired` — shared between UI thread (triggers) and a delayed handler (sound). `volatile` ensures visibility across threads without a lock.
- `pendingSoundRunnable` — the 500ms delayed sound start, stored so it can be cancelled if the user dismisses before it fires.

---

### `onCreate()`

```java
fusedClient  = LocationServices.getFusedLocationProviderClient(this);
wifiManager  = (WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
wifiScanHandler = new Handler(Looper.getMainLooper());
soundHandler    = new Handler(Looper.getMainLooper());
```
Initialises all resources. `getApplicationContext()` for `WifiManager` is required — using the service context can cause a memory leak.

---

### `isActivelyTracking()`

```java
return locationCallback != null || networkLocationCallback != null || wifiScanRunnable != null;
```
Any non-null sensor registration means the service is currently tracking. Used to avoid redundant `resumeFromPrefs()` calls.

---

### `onStartCommand()`

```java
if (intent == null || intent.getAction() == null) {
    if (!isActivelyTracking()) resumeFromPrefs();
    return START_STICKY;
}
```
`intent == null` happens when Android auto-restarts the service after an OOM kill (because of `START_STICKY`). `intent.getAction() == null` happens when `BootReceiver` starts the service without an action. Both cases restore state from SharedPreferences.

```java
startForeground(TRACKING_NOTIF_ID, buildTrackingNotification("StopSnoozer is watching your route…"));
```
Android 8+ requires foreground services to call `startForeground()` within 5 seconds of `onStartCommand()`. This posts the persistent notification.

Each `case` in the `switch`:
- Reads extras from the intent.
- Saves state to SharedPreferences (so the service can resume after a kill).
- Starts the appropriate sensor(s).

---

### `startAboveGroundTracking()`

```java
LocationRequest gpsRequest = new LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
        .setMinUpdateIntervalMillis(3_000L)
        .build();
```
GPS updates every 5 seconds, minimum interval 3 seconds. High accuracy = GPS chip + network.

```java
LocationRequest networkRequest = new LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 10_000L)
        .setMinUpdateIntervalMillis(8_000L)
        .build();
```
WiFi/cell triangulation every 10 seconds. Lower accuracy but works underground when GPS has no signal. This is NOT the SSID matching — this is Google's location database giving a coordinate fix from nearby WiFi signals.

```java
fusedClient.requestLocationUpdates(gpsRequest,     locationCallback,        Looper.getMainLooper());
fusedClient.requestLocationUpdates(networkRequest, networkLocationCallback, Looper.getMainLooper());
```
Both callbacks call `checkLocationAndTrigger()`. Registering two separate requests means the network provider fires independently when GPS is unavailable.

---

### `checkLocationAndTrigger()`

```java
float[] dist = new float[1];
Location.distanceBetween(loc.getLatitude(), loc.getLongitude(), t.lat, t.lon, dist);
if (dist[0] <= t.radius) {
    triggerAlarm(t.stopId, t.stopName, dist[0]);
}
```
`Location.distanceBetween()` computes the great-circle distance using the Haversine formula. Returns metres in `dist[0]`. If within `t.radius` metres, the alarm fires.

---

### `startSubterraneanTracking()`

```java
wifiScanReceiver = new BroadcastReceiver() {
    public void onReceive(Context context, Intent intent) {
        boolean ok = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false);
        if (ok) evaluateWifiResults();
    }
};
IntentFilter filter = new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
ContextCompat.registerReceiver(this, wifiScanReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);
```
Registers a receiver for the system broadcast `SCAN_RESULTS_AVAILABLE_ACTION`, which fires after every WiFi scan completes. `EXTRA_RESULTS_UPDATED` is `true` if the scan actually returned fresh results (vs. throttled cached results).

```java
wifiScanRunnable = new Runnable() {
    public void run() {
        boolean accepted = wifiManager.startScan();
        long next = accepted ? WIFI_SCAN_INTERVAL_MS : WIFI_SCAN_THROTTLED_INTERVAL_MS;
        wifiScanHandler.postDelayed(this, next);
    }
};
wifiScanHandler.post(wifiScanRunnable);
```
Triggers a scan immediately, then schedules the next one. If the scan was rejected (throttled by Android), waits `32_000ms` instead of `8_000ms` to avoid hammering the radio.

---

### `evaluateWifiResults()`

```java
for (ScanResult r : results) {
    if (targetSsid.equalsIgnoreCase(r.SSID) || targetSsid.equalsIgnoreCase(r.BSSID)) {
        triggerAlarm(targetStopId, targetStopName, 0f);
        return;
    }
}
```
`r.SSID` is the human-readable network name. `r.BSSID` is the MAC address (for cases where the SSID may be hidden but the BSSID is known). `distanceMetres = 0f` for WiFi alarms because there is no physical distance measurement — the station is detected by its network presence.

---

### `triggerAlarm()`

```java
prefs.edit()
    .putString("pending_alarm_stop_id",   targetStopId)
    .putString("pending_alarm_stop_name", targetStopName)
    .putFloat("pending_alarm_distance",   distanceMetres)
    .putLong("pending_alarm_fired_at",    firedAt)
    .apply();
```
Persists alarm data before doing anything else. If the app is killed between this point and the broadcast, `checkPendingAlarm` in `MainActivity` will still find the data on the next app open.

```java
Intent bc = new Intent(ACTION_ALARM_TRIGGER);
bc.putExtra("stopId",         targetStopId);
...
sendBroadcast(bc);
```
Sends a local broadcast that `MainActivity`'s `EventChannel` receiver picks up and forwards to Dart as a stream event.

```java
pendingSoundRunnable = () -> playAlarmSound(getSharedPreferences(PREFS_NAME, MODE_PRIVATE));
soundHandler.postDelayed(pendingSoundRunnable, 500L);
```
Delays the sound by 500ms. This gives the Flutter alarm screen time to animate in before the ringtone starts. The `pendingSoundRunnable` reference is saved so it can be cancelled if the user dismisses within the 500ms window.

---

### `playAlarmSound()`

```java
boolean isSubtle = "subtlePulse".equals(prefs.getString(PREF_ALARM_STYLE_ACTIVE, "defconDrill"));
```
Two alarm styles:
- `"defconDrill"` — looping alarm ringtone, `USAGE_ALARM`.
- `"subtlePulse"` — single notification sound, `USAGE_NOTIFICATION`.

```java
alarmRingtone.setLooping(!isSubtle);
```
`defconDrill` loops until dismissed. `subtlePulse` plays once.

---

### `showAlarmNotification()`

```java
NotificationCompat.Builder b = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
    ...
    .setPriority(NotificationCompat.PRIORITY_MAX)
    .setCategory(NotificationCompat.CATEGORY_ALARM)
    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
    .setOngoing(true)
    .setAutoCancel(false)
    .addAction(..., "Snooze 2 min", snoozePi)
    .addAction(..., "Stop Alarm", stopPi);
```
- `PRIORITY_MAX` — heads-up notification (pops up over other apps).
- `CATEGORY_ALARM` — Android treats it like a clock alarm: bypasses Do Not Disturb.
- `VISIBILITY_PUBLIC` — shown in full on the lock screen.
- `setOngoing(true)` — the user cannot swipe it away.
- Both action buttons send intents back to the service.

```java
launchIntent.putExtra("alarmFromService", true);
```
This extra is checked in `MainActivity.onCreate()` and `onNewIntent()` to apply the show-over-lock-screen flags.

---

### `snoozeAlarm()`

Cancels the pending sound, stops any playing ringtone, replaces the alarm notification with a quiet "snoozed" notification, resets `alarmFired = false`, and posts a delayed `Handler` that re-arms location/WiFi tracking after `snoozeMinutes * 60_000ms`.

---

### `dismissAlarm()`

If multi-target mode has remaining targets, only resets `alarmFired` and updates the notification — tracking continues. If no more targets, stops all sensors, clears SharedPreferences, and calls `stopSelf()`.

---

### `saveTrackingState()` / `clearTrackingState()` / `resumeFromPrefs()`

These three methods together make the service **crash-resilient**:
- `saveTrackingState()` — called right after every `ACTION_*` case, writes current target info to SharedPreferences.
- `clearTrackingState()` — called on dismissal, removes all persisted state.
- `resumeFromPrefs()` — called when `intent == null` (Android restart). Reads state back and re-starts the appropriate tracking mode.

`Double.doubleToRawLongBits(lat)` and `Double.longBitsToDouble(...)` are used because SharedPreferences has no native `double` type, only `float` (32-bit, not enough precision for GPS coordinates) and `long` (64-bit, same bit-width as `double`).

---

### `onTaskRemoved()` — OEM kill defence

```java
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    pi = PendingIntent.getForegroundService(...);
} else {
    pi = PendingIntent.getService(...);
}
am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + 3_000L, pi);
```
When the user swipes the app from Recents, `onTaskRemoved` fires. Because `android:stopWithTask="false"` the service usually survives, but aggressive OEM ROM battery managers (MIUI, Samsung, Huawei) may kill it anyway. This schedules a 3-second AlarmManager ping to restart the service. `getForegroundService()` is required on API 26+ because `startService()` is blocked for background apps; `setExactAndAllowWhileIdle` fires even in Doze.

---

### `TargetStop` inner class

```java
private static final class TargetStop {
    final String stopId;
    final String stopName;
    final double lat;
    final double lon;
    final float  radius;
    final String ssid; // null = GPS-only; non-null = also WiFi
    ...
    JSONObject toJson() { ... }
    static TargetStop fromJson(JSONObject o) { ... }
}
```
An immutable data class representing one tracking target. `toJson()` and `fromJson()` provide serialisation for the `PREF_TARGETS_JSON` SharedPreferences key, which persists the multi-target list across process kills.

---

## File 5 — `BootReceiver.java`

**Path:** `android/app/src/main/java/com/stopsnoozer/app/BootReceiver.java`
**Purpose:** Wakes up after the device restarts. Re-registers all scheduled alarms and restarts tracking if it was active.

```java
if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
        && !"android.intent.action.QUICKBOOT_POWERON".equals(intent.getAction())) {
    return;
}
```
Guard against spurious broadcasts. Only `BOOT_COMPLETED` and `QUICKBOOT_POWERON` (HTC fast-boot) are handled.

```java
AlarmScheduler.rescheduleAllFromPrefs(context);
```
Re-registers every saved commute alarm with `AlarmManager`. Without this, all scheduled alarms are lost after reboot.

```java
SharedPreferences prefs = context.getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE);
if (prefs.getString("tracking_action", null) != null) {
    ContextCompat.startForegroundService(context, new Intent(context, SnoozeTrackingService.class));
}
```
Checks if the service was tracking when the phone was powered off. If so, restarts it. The service's `onStartCommand` receives `intent.getAction() == null` (no action set) and calls `resumeFromPrefs()` to restore the tracking session.

---

## File 6 — `CommuteAlarmReceiver.java`

**Path:** `android/app/src/main/java/com/stopsnoozer/app/CommuteAlarmReceiver.java`
**Purpose:** The `BroadcastReceiver` that wakes up when a scheduled commute alarm fires. Starts tracking and reschedules the next occurrence.

```java
String alarmId      = intent.getStringExtra("alarmId");
String stopId       = intent.getStringExtra("stopId");
...
String tripGroupId  = intent.getStringExtra("tripGroupId");
```
Reads every extra that `AlarmScheduler.buildPendingIntent()` packed into the intent.

```java
Intent svcIntent = new Intent(context, SnoozeTrackingService.class);
svcIntent.setAction(SnoozeTrackingService.ACTION_ADD_TARGET);
```
Uses `ACTION_ADD_TARGET` (not `ACTION_START_GEOFENCE`) so the new alarm stop is **merged** with any stops the user may already be tracking manually. This prevents a commute alarm from wiping out an active real-time tracking session.

```java
ContextCompat.startForegroundService(context, svcIntent);
```
Allowed from a `setAlarmClock()` callback even while the app is in the background.

```java
if (tripGroupId != null && !tripGroupId.isEmpty()) {
    context.getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE)
           .edit()
           .putString("pending_trip_group_id", tripGroupId)
           .apply();
}
```
Persists the trip group ID. Dart reads this via `checkPendingTripGroup` (MethodChannel) on the next app open/foreground to load all legs of the trip.

```java
boolean isRecurring = specificDate == null || specificDate.isEmpty();
if (isRecurring && alarmId != null && weekdays != null) {
    AlarmScheduler.rescheduleNext(context, alarmId);
} else if (alarmId != null) {
    AlarmScheduler.remove(context, alarmId);
}
```
If the alarm was weekly-recurring: reschedule for the next matching weekday. If it was a one-off date: remove it from SharedPreferences so it does not fire again on reboot.

---

## File Group 7 — Launcher Icon Assets

### `res/drawable/ic_launcher_background.xml` (Amber/Default)

```xml
<path android:fillColor="#0F1115" android:pathData="M0,0H108V108H0Z"/>
```
A solid rectangle (`0,0` to `108,108`) in very dark charcoal (`#0F1115`). This fills the entire 108dp adaptive icon canvas as the background layer.

### `res/drawable/ic_launcher_foreground.xml` (Amber/Default)

108×108dp SVG-style vector. Uses paths scaled from a 100×100 design space into the 72×72 adaptive-icon safe zone (the centre region that is always visible regardless of device mask shape).

- **Arch/bus-shelter outline** — stroke-only path in `#FFB000` (amber). Represents a transit shelter or arch, the app's visual metaphor.
- **Base bar** — solid amber rectangle at the bottom of the arch, represents the ground/platform.
- **Crescent moon** — amber filled shape, references "not sleeping through your stop".
- **Dot below base bar** — small amber circle, a subtle design punctuation below the platform.

### `res/mipmap-anydpi-v26/ic_launcher.xml` (Amber adaptive icon)

```xml
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
```
Android 8+ (API 26) adaptive icon format. The OS applies its own mask shape (circle, squircle, teardrop, etc.) to this two-layer image. `anydpi-v26` means this XML is used on API 26+ regardless of screen density; the older PNG files in `mipmap-mdpi/xhdpi/` etc. serve as fallbacks for API 25 and below.

### Theme variants (Navy, Forest, Volcanic, Galactic)

Each theme has:
- `res/drawable/ic_launcher_background_<theme>.xml` — same full-canvas rectangle with a different fill colour (e.g. navy blue, forest green, volcanic red, deep space dark).
- `res/drawable/ic_launcher_foreground_<theme>.xml` — same icon paths but potentially with different stroke/fill colours matching the theme palette.
- `res/mipmap-anydpi-v26/ic_launcher_<theme>.xml` — adaptive icon XML combining the theme's background + foreground.
- `res/mipmap-anydpi-v26/ic_launcher_round_<theme>.xml` — identical structure, used as the `roundIcon` attribute on devices with circular icon masks.

The naming convention `ic_launcher_<theme>` matches the `android:icon` attributes on the `<activity-alias>` entries in `AndroidManifest.xml`.

---

## End-to-end Flow Summary

### User saves a commute alarm in the Flutter UI

```
Flutter UI → AlarmViewModel.scheduleAlarm()
  → PlatformChannelService.scheduleCommuteAlarm(...)
    → MethodChannel "com.stopsnoozer.app/location" → "scheduleCommuteAlarm"
      → MainActivity.kt → AlarmScheduler.scheduleAndSave()
        → SharedPreferences persisted
        → AlarmManager.setAlarmClock(fireAt, trigger → CommuteAlarmReceiver)
```

### Alarm fires at scheduled time

```
AlarmManager fires → CommuteAlarmReceiver.onReceive()
  → ContextCompat.startForegroundService(ACTION_ADD_TARGET)
    → SnoozeTrackingService.onStartCommand()
      → startAboveGroundTracking() + startSubterraneanTracking()
      → AlarmScheduler.rescheduleNext() for next weekly occurrence
```

### User arrives at stop

```
GPS fix / WiFi scan → checkLocationAndTrigger() or evaluateWifiResults()
  → triggerAlarm()
    → SharedPreferences: persist pending alarm data
    → showAlarmNotification() → heads-up notification with action buttons
    → sendBroadcast(ACTION_ALARM_TRIGGER)
      → MainActivity EventChannel BroadcastReceiver
        → events.success(payload)
          → Dart alarmStream → DashboardViewModel / AlarmViewModel
            → alarm screen shown in Flutter UI
    → soundHandler.postDelayed(playAlarmSound, 500ms)
```

### User taps "Stop Alarm" on notification

```
PendingIntent → SnoozeTrackingService.onStartCommand(ACTION_STOP_ALARM)
  → dismissAlarm()
    → alarmRingtone.stop()
    → NotificationManager.cancel()
    → if no remaining targets: stopSelf()
```

### User changes theme in Flutter UI

```
ThemeService.setTheme(index)
  → PlatformChannelService.switchLauncherIcon(index)
    → MethodChannel → "switchLauncherIcon"
      → MainActivity.switchLauncherIcon(index)
        → PackageManager.setComponentEnabledSetting(alias[index], ENABLED)
        → PackageManager.setComponentEnabledSetting(alias[others], DISABLED)
          → Launcher home screen icon updates
```
