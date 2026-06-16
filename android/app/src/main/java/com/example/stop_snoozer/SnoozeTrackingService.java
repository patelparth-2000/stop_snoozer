package com.example.stop_snoozer;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.graphics.Color;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.location.Location;
import android.location.LocationManager;
import android.media.AudioAttributes;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import java.util.ArrayList;
import java.util.List;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Foreground service — GPS geofencing (above ground) + Wi-Fi SSID scanning (underground).
 * Stays alive after alarm fires to keep sound playing until the user explicitly stops it.
 */
public class SnoozeTrackingService extends Service {

    // ── Action constants ───────────────────────────────────────────────────
    static final String ACTION_START_GEOFENCE  = "com.stopsnoozer.app.START_GEOFENCE";
    static final String ACTION_START_WIFI      = "com.stopsnoozer.app.START_WIFI";
    static final String ACTION_START_HYBRID    = "com.stopsnoozer.app.START_HYBRID";
    static final String ACTION_UPDATE_TARGETS  = "com.stopsnoozer.app.UPDATE_TARGETS";
    static final String ACTION_ADD_TARGET      = "com.stopsnoozer.app.ADD_TARGET";
    static final String ACTION_STOP            = "com.stopsnoozer.app.STOP_TRACKING";
    static final String ACTION_ALARM_TRIGGER  = "com.stopsnoozer.app.ALARM_TRIGGER";
    static final String ACTION_STOP_ALARM     = "com.stopsnoozer.app.STOP_ALARM";
    static final String ACTION_SNOOZE         = "com.stopsnoozer.app.SNOOZE_ALARM";
    static final String EXTRA_SNOOZE_MINUTES  = "snoozeMinutes";

    // ── Preferences ────────────────────────────────────────────────────────
    static final String PREFS_NAME          = "snoozer_prefs";
    static final String PREF_ALARM_TYPE     = "alarm_type";
    static final String PREF_RINGTONE_URI   = "alarm_ringtone_uri";
    static final String PREF_RINGTONE_NAME  = "alarm_ringtone_name";
    // Persisted tracking state — restored when Android restarts the service
    private static final String PREF_TRACKING_ACTION    = "tracking_action";
    private static final String PREF_TARGETS_JSON       = "tracking_targets_json";
    private static final String PREF_TRACKING_STOP_ID   = "tracking_stop_id";
    private static final String PREF_TRACKING_STOP_NAME = "tracking_stop_name";
    private static final String PREF_TRACKING_LAT       = "tracking_lat";
    private static final String PREF_TRACKING_LON       = "tracking_lon";
    private static final String PREF_TRACKING_RADIUS    = "tracking_radius";
    private static final String PREF_TRACKING_SSID      = "tracking_ssid";

    // ── Notification channels ──────────────────────────────────────────────
    private static final String TRACKING_CHANNEL_ID  = "snooze_tracking";
    private static final String ALARM_CHANNEL_ID     = "snooze_alarm";
    private static final int    TRACKING_NOTIF_ID    = 1001;
    private static final int    ALARM_NOTIF_ID       = 1002;
    private static final int    LOCATION_OFF_NOTIF_ID = 1003;

    private static final int WIFI_SCAN_INTERVAL_MS           = 8_000;
    private static final int WIFI_SCAN_THROTTLED_INTERVAL_MS = 32_000;
    // Seconds the user has to dismiss the alarm screen before the ringtone starts
    static final int ALARM_COUNTDOWN_SECS = 3;

    // ── State ──────────────────────────────────────────────────────────────
    private FusedLocationProviderClient fusedClient;
    private LocationCallback            locationCallback;
    private LocationCallback            networkLocationCallback; // WiFi/cell fallback for underground
    private WifiManager                 wifiManager;
    private BroadcastReceiver           wifiScanReceiver;
    private Handler                     wifiScanHandler;
    private Runnable                    wifiScanRunnable;
    private Ringtone                    alarmRingtone;
    // Delayed ringtone: cancelled if user dismisses within ALARM_COUNTDOWN_SECS
    private Handler                     soundHandler;
    private Runnable                    pendingSoundRunnable;

    private volatile boolean alarmFired = false;
    private String currentAlarmStyle = "defconDrill";

    static final String PREF_ALARM_STYLE_ACTIVE = "alarm_style_active";

    // Single-target fields — used by GEOFENCE/WIFI/HYBRID scheduled alarms
    private String targetStopId;
    private String targetStopName;
    private double targetLat;
    private double targetLon;
    private float  targetRadius;
    private String targetSsid;

    // Multi-target list — used by UPDATE_TARGETS (manual saved locations)
    private final ArrayList<TargetStop> targets = new ArrayList<>();

    // ── Lifecycle ──────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannels();
        fusedClient     = LocationServices.getFusedLocationProviderClient(this);
        wifiManager     = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        wifiScanHandler = new Handler(Looper.getMainLooper());
        soundHandler    = new Handler(Looper.getMainLooper());
    }

    /** True while location callbacks or Wi-Fi scanning are registered. */
    private boolean isActivelyTracking() {
        return locationCallback != null || networkLocationCallback != null
                || wifiScanRunnable != null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // intent == null  → Android START_STICKY auto-restart after OOM kill.
        // action == null  → BootReceiver or onTaskRemoved AlarmManager ping
        //                   (non-null intent but no action set).
        // Both cases must restore tracking from SharedPreferences.
        if (intent == null || intent.getAction() == null) {
            if (!isActivelyTracking()) resumeFromPrefs();
            return START_STICKY;
        }

        startForeground(TRACKING_NOTIF_ID,
                buildTrackingNotification("StopSnoozer is watching your route…"));

        final String action = intent.getAction();
        switch (action) {
            case ACTION_START_GEOFENCE:
                alarmFired        = false;
                targetStopId      = intent.getStringExtra("stopId");
                targetStopName    = intent.getStringExtra("stopName");
                targetLat         = intent.getDoubleExtra("lat", 0);
                targetLon         = intent.getDoubleExtra("lon", 0);
                targetRadius      = intent.getFloatExtra("radiusMetres", 500f);
                { String s = intent.getStringExtra("alarmStyle"); currentAlarmStyle = s != null && !s.isEmpty() ? s : "defconDrill"; }
                if (!isLocationEnabled()) {
                    showLocationOffNotification();
                    clearTrackingState();
                    stopForeground(true);
                    stopSelf();
                    return START_NOT_STICKY;
                }
                saveTrackingState(ACTION_START_GEOFENCE);
                startAboveGroundTracking();
                break;

            case ACTION_START_WIFI:
                alarmFired     = false;
                targetStopId   = intent.getStringExtra("stopId");
                targetStopName = intent.getStringExtra("stopName");
                targetSsid     = intent.getStringExtra("targetSsid");
                if (!isWifiEnabled()) {
                    showWifiOffNotification();
                    clearTrackingState();
                    stopForeground(true);
                    stopSelf();
                    return START_NOT_STICKY;
                }
                saveTrackingState(ACTION_START_WIFI);
                startSubterraneanTracking();
                break;

            case ACTION_START_HYBRID:
                alarmFired        = false;
                targets.clear();
                targetStopId      = intent.getStringExtra("stopId");
                targetStopName    = intent.getStringExtra("stopName");
                targetLat         = intent.getDoubleExtra("lat", 0);
                targetLon         = intent.getDoubleExtra("lon", 0);
                targetRadius      = intent.getFloatExtra("radiusMetres", 300f);
                targetSsid        = intent.getStringExtra("targetSsid");
                { String s = intent.getStringExtra("alarmStyle"); currentAlarmStyle = s != null && !s.isEmpty() ? s : "defconDrill"; }
                saveTrackingState(ACTION_START_HYBRID);
                startHybridTracking();
                break;

            case ACTION_UPDATE_TARGETS: {
                String json = intent.getStringExtra("targetsJson");
                targets.clear();
                alarmFired = false;
                if (json != null && !json.isEmpty()) {
                    try {
                        JSONArray arr = new JSONArray(json);
                        for (int i = 0; i < arr.length(); i++) {
                            targets.add(TargetStop.fromJson(arr.getJSONObject(i)));
                        }
                    } catch (Exception ignored) {}
                }
                if (targets.isEmpty()) {
                    dismissAlarm();
                    break;
                }
                saveTargetsJson();
                saveTrackingState(ACTION_UPDATE_TARGETS);
                startMultiTargetTracking();
                break;
            }

            case ACTION_ADD_TARGET: {
                // Restore existing multi-targets from prefs (handles post-kill case)
                if (targets.isEmpty()) {
                    SharedPreferences ap = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
                    String tj = ap.getString(PREF_TARGETS_JSON, null);
                    if (tj != null) {
                        try {
                            JSONArray arr = new JSONArray(tj);
                            for (int i = 0; i < arr.length(); i++)
                                targets.add(TargetStop.fromJson(arr.getJSONObject(i)));
                        } catch (Exception ignored) {}
                    }
                    // Also absorb an active single-target (GEOFENCE/HYBRID) into the list
                    if (targets.isEmpty()) {
                        String cur = ap.getString(PREF_TRACKING_ACTION, null);
                        if (ACTION_START_GEOFENCE.equals(cur) || ACTION_START_HYBRID.equals(cur)) {
                            String eId   = ap.getString(PREF_TRACKING_STOP_ID,   null);
                            String eName = ap.getString(PREF_TRACKING_STOP_NAME, null);
                            double eLat  = Double.longBitsToDouble(ap.getLong(PREF_TRACKING_LAT, 0));
                            double eLon  = Double.longBitsToDouble(ap.getLong(PREF_TRACKING_LON, 0));
                            float  eRad  = ap.getFloat(PREF_TRACKING_RADIUS, 300f);
                            String eSsid = ap.getString(PREF_TRACKING_SSID, null);
                            if (eId != null && !eId.isEmpty())
                                targets.add(new TargetStop(eId, eName, eLat, eLon, eRad, eSsid));
                        }
                    }
                }
                // Add/update new target (deduplicate by stopId)
                String newId   = intent.getStringExtra("stopId");
                String newName = intent.getStringExtra("stopName");
                double newLat  = intent.getDoubleExtra("lat", 0);
                double newLon  = intent.getDoubleExtra("lon", 0);
                float  newRad  = intent.getFloatExtra("radiusMetres", 300f);
                String newSsid = intent.getStringExtra("ssid");
                for (int i = targets.size() - 1; i >= 0; i--) {
                    if (targets.get(i).stopId.equals(newId)) targets.remove(i);
                }
                targets.add(new TargetStop(newId, newName, newLat, newLon, newRad, newSsid));
                alarmFired = false;
                saveTargetsJson();
                saveTrackingState(ACTION_UPDATE_TARGETS);
                startMultiTargetTracking();
                break;
            }

            case ACTION_STOP:
                dismissAlarm();
                break;

            case ACTION_STOP_ALARM:
                dismissAlarm();
                break;

            case ACTION_SNOOZE:
                int minutes = intent.getIntExtra(EXTRA_SNOOZE_MINUTES, 5);
                snoozeAlarm(minutes);
                break;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopSensors();
        if (alarmRingtone != null) {
            alarmRingtone.stop();
            alarmRingtone = null;
        }
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Above-ground GPS Geofencing + Network (underground) fallback ─────────

    /** Shared distance check — called by both GPS and network location callbacks. */
    private void checkLocationAndTrigger(Location loc) {
        if (alarmFired) return;
        float[] dist = new float[1];
        if (!targets.isEmpty()) {
            for (TargetStop t : targets) {
                if (t.lat == 0.0 && t.lon == 0.0) continue;
                Location.distanceBetween(loc.getLatitude(), loc.getLongitude(), t.lat, t.lon, dist);
                if (dist[0] <= t.radius) {
                    triggerAlarm(t.stopId, t.stopName, dist[0]);
                    return;
                }
            }
        } else {
            Location.distanceBetween(loc.getLatitude(), loc.getLongitude(),
                    targetLat, targetLon, dist);
            if (dist[0] <= targetRadius)
                triggerAlarm(targetStopId, targetStopName, dist[0]);
        }
    }

    @SuppressWarnings("MissingPermission")
    private void startAboveGroundTracking() {
        // Primary: GPS — precise above ground, 5s interval
        LocationRequest gpsRequest = new LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
                .setMinUpdateIntervalMillis(3_000L)
                .build();

        // Fallback: WiFi/cell triangulation — fires when GPS loses signal underground.
        // Does NOT require a specific SSID — uses Google's WiFi positioning database.
        LocationRequest networkRequest = new LocationRequest.Builder(
                Priority.PRIORITY_BALANCED_POWER_ACCURACY, 10_000L)
                .setMinUpdateIntervalMillis(8_000L)
                .build();

        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult result) {
                Location loc = result.getLastLocation();
                if (loc != null) checkLocationAndTrigger(loc);
            }
        };

        networkLocationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult result) {
                Location loc = result.getLastLocation();
                if (loc != null) checkLocationAndTrigger(loc);
            }
        };

        try {
            fusedClient.requestLocationUpdates(gpsRequest,     locationCallback,        Looper.getMainLooper());
            fusedClient.requestLocationUpdates(networkRequest, networkLocationCallback, Looper.getMainLooper());
            updateTrackingNotification("Tracking: " + targetStopName);
        } catch (SecurityException e) {
            locationCallback        = null;
            networkLocationCallback = null;
            showPermissionMissingNotification();
            clearTrackingState();
            stopForeground(true);
            stopSelf();
        }
    }

    private void showPermissionMissingNotification() {
        Intent settingsIntent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        settingsIntent.setData(Uri.fromParts("package", getPackageName(), null));
        settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent settingsPi = PendingIntent.getActivity(
                this, 5, settingsIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setColor(APP_COLOR)
                .setContentTitle("Background Location Needed")
                .setContentText("Set location to 'Allow all the time' for alarms to work")
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "Your scheduled alarm fired but background location is not granted. "
                        + "Open App Settings → Location → Allow all the time, "
                        + "then re-save your alarm."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ERROR)
                .setAutoCancel(true)
                .setContentIntent(settingsPi)
                .addAction(android.R.drawable.ic_menu_mylocation, "Open App Settings", settingsPi)
                .build();

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(LOCATION_OFF_NOTIF_ID + 2, n);
    }

    private void stopAboveGroundTracking() {
        if (fusedClient != null && locationCallback != null) {
            fusedClient.removeLocationUpdates(locationCallback);
            locationCallback = null;
        }
        if (fusedClient != null && networkLocationCallback != null) {
            fusedClient.removeLocationUpdates(networkLocationCallback);
            networkLocationCallback = null;
        }
    }

    // ── Hybrid GPS + Wi-Fi ────────────────────────────────────────────────

    private void startHybridTracking() {
        boolean gpsOk  = isLocationEnabled();
        boolean wifiOk = isWifiEnabled();
        if (!gpsOk && !wifiOk) {
            // Neither sensor available — show location-off notification as a best-effort
            showLocationOffNotification();
            clearTrackingState();
            stopForeground(true);
            stopSelf();
            return;
        }
        if (gpsOk)  startAboveGroundTracking();
        if (wifiOk) startSubterraneanTracking();
        updateTrackingNotification("GPS + WiFi: " + targetStopName);
    }

    // ── Subterranean Wi-Fi SSID Scanning ──────────────────────────────────

    private void startSubterraneanTracking() {
        wifiScanReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (alarmFired) return;
                boolean ok = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false);
                if (ok) evaluateWifiResults();
            }
        };

        IntentFilter filter = new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
        ContextCompat.registerReceiver(this, wifiScanReceiver, filter,
                ContextCompat.RECEIVER_NOT_EXPORTED);

        wifiScanRunnable = new Runnable() {
            @Override
            @SuppressWarnings("deprecation")
            public void run() {
                if (alarmFired || wifiManager == null) return;
                boolean accepted = wifiManager.startScan();
                long next = accepted ? WIFI_SCAN_INTERVAL_MS : WIFI_SCAN_THROTTLED_INTERVAL_MS;
                wifiScanHandler.postDelayed(this, next);
            }
        };
        wifiScanHandler.post(wifiScanRunnable);
        updateTrackingNotification("Underground sensing: " + targetStopName);
    }

    @SuppressWarnings("deprecation")
    private void evaluateWifiResults() {
        if (wifiManager == null) return;
        List<ScanResult> results = wifiManager.getScanResults();

        if (!targets.isEmpty()) {
            // Multi-target mode: match any target's SSID
            for (TargetStop t : targets) {
                if (t.ssid == null) continue;
                for (ScanResult r : results) {
                    if (t.ssid.equalsIgnoreCase(r.SSID) || t.ssid.equalsIgnoreCase(r.BSSID)) {
                        triggerAlarm(t.stopId, t.stopName, 0f);
                        return;
                    }
                }
            }
        } else {
            // Single-target mode
            if (targetSsid == null) return;
            for (ScanResult r : results) {
                if (targetSsid.equalsIgnoreCase(r.SSID) || targetSsid.equalsIgnoreCase(r.BSSID)) {
                    triggerAlarm(targetStopId, targetStopName, 0f);
                    return;
                }
            }
        }
    }

    private void stopSubterraneanTracking() {
        if (wifiScanReceiver != null) {
            try { unregisterReceiver(wifiScanReceiver); } catch (Exception ignored) {}
            wifiScanReceiver = null;
        }
        if (wifiScanRunnable != null) {
            wifiScanHandler.removeCallbacks(wifiScanRunnable);
            wifiScanRunnable = null;
        }
    }

    // ── Alarm Dispatch ─────────────────────────────────────────────────────

    private void startMultiTargetTracking() {
        stopSensors();
        boolean needGps = false, needWifi = false;
        StringBuilder names = new StringBuilder();
        for (TargetStop t : targets) {
            if (t.lat != 0.0 || t.lon != 0.0) needGps  = true;
            if (t.ssid != null)                needWifi = true;
            if (names.length() > 0) names.append(", ");
            names.append(t.stopName);
        }
        if (needGps  && isLocationEnabled()) startAboveGroundTracking();
        if (needWifi && isWifiEnabled())     startSubterraneanTracking();
        updateTrackingNotification("Tracking: " + names);
    }

    private void saveTargetsJson() {
        JSONArray arr = new JSONArray();
        for (TargetStop t : targets) arr.put(t.toJson());
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putString(PREF_TARGETS_JSON, arr.toString())
                .apply();
    }

    private void triggerAlarm(String stopId, String stopName, float distanceMetres) {
        if (alarmFired) return;
        alarmFired     = true;
        targetStopId   = stopId;
        targetStopName = stopName;

        // Multi-target: remove fired stop; keep sensors running for remaining targets
        boolean hasRemaining = false;
        if (!targets.isEmpty()) {
            for (int i = targets.size() - 1; i >= 0; i--) {
                if (targets.get(i).stopId.equals(stopId)) { targets.remove(i); break; }
            }
            hasRemaining = !targets.isEmpty();
            if (hasRemaining) saveTargetsJson();
        }
        // Stop sensors only when this was the last target
        if (!hasRemaining) stopSensors();

        final long firedAt = System.currentTimeMillis();
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);

        prefs.edit()
                .putString("pending_alarm_stop_id",   targetStopId   != null ? targetStopId   : "")
                .putString("pending_alarm_stop_name", targetStopName != null ? targetStopName : "")
                .putFloat("pending_alarm_distance",   distanceMetres)
                .putLong("pending_alarm_fired_at",    firedAt)
                .apply();

        showAlarmNotification(distanceMetres);

        Intent bc = new Intent(ACTION_ALARM_TRIGGER);
        bc.putExtra("stopId",         targetStopId);
        bc.putExtra("stopName",       targetStopName);
        bc.putExtra("distanceMetres", distanceMetres);
        bc.putExtra("firedAt",        firedAt);
        bc.putExtra("countdownSecs",  ALARM_COUNTDOWN_SECS);
        sendBroadcast(bc);

        pendingSoundRunnable = () -> playAlarmSound(getSharedPreferences(PREFS_NAME, MODE_PRIVATE));
        soundHandler.postDelayed(pendingSoundRunnable, 500L);

        // Allow remaining targets to fire after a 5-second cooldown
        if (hasRemaining) {
            new Handler(Looper.getMainLooper()).postDelayed(() -> alarmFired = false, 5_000L);
        }
    }

    private String getTargetNames() {
        StringBuilder sb = new StringBuilder();
        for (TargetStop t : targets) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(t.stopName);
        }
        return sb.toString();
    }

    private void playAlarmSound(SharedPreferences prefs) {
        boolean isSubtle = "subtlePulse".equals(
                prefs.getString(PREF_ALARM_STYLE_ACTIVE, "defconDrill"));

        Uri uri;
        if (isSubtle) {
            uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        } else {
            String uriStr = prefs.getString(PREF_RINGTONE_URI, null);
            uri = uriStr != null
                    ? Uri.parse(uriStr)
                    : RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        }
        if (uri == null) uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (uri == null) return;

        alarmRingtone = RingtoneManager.getRingtone(this, uri);
        if (alarmRingtone == null) return;

        alarmRingtone.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(isSubtle ? AudioAttributes.USAGE_NOTIFICATION : AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build());
        alarmRingtone.setLooping(!isSubtle); // subtle = one-shot; defconDrill = looped
        alarmRingtone.play();
    }

    /**
     * Posts the alarm notification.
     * On Android 14+ checks USE_FULL_SCREEN_INTENT; falls back to heads-up if not granted.
     * Always shows on the lock screen (VISIBILITY_PUBLIC) and wakes the device.
     */
    private void showAlarmNotification(float distanceMetres) {
        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP_ALARM);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Intent snoozeIntent = new Intent(this, SnoozeTrackingService.class);
        snoozeIntent.setAction(ACTION_SNOOZE);
        snoozeIntent.putExtra(EXTRA_SNOOZE_MINUTES, 2);
        PendingIntent snoozePi = PendingIntent.getService(this, 3, snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent launchPi = null;
        if (launchIntent != null) {
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            launchIntent.putExtra("alarmFromService", true);
            launchIntent.putExtra("stopId",           targetStopId);
            launchIntent.putExtra("stopName",         targetStopName);
            launchIntent.putExtra("distanceMetres",   distanceMetres);
            launchPi = PendingIntent.getActivity(this, 2, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }

        String stop         = targetStopName != null ? targetStopName : "your stop";
        boolean isAtPlatform = (distanceMetres == 0f);
        String title   = isAtPlatform
                ? "You've arrived at " + stop + "!"
                : "Approaching " + stop + "!";
        String summary = isAtPlatform
                ? "You're at the platform — get off now"
                : "You're " + Math.round(distanceMetres) + "m away — get off soon";

        NotificationCompat.Builder b = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setColor(APP_COLOR)
                .setContentTitle(title)
                .setContentText(summary)
                .setStyle(new NotificationCompat.BigTextStyle()
                        .setBigContentTitle(title)
                        .bigText(summary + ". Tap to open StopSnoozer."))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .addAction(android.R.drawable.ic_menu_recent_history, "Snooze 2 min", snoozePi)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Alarm", stopPi);

        if (launchPi != null) {
            b.setContentIntent(launchPi);
        }

        NotificationManager mgr = getSystemService(NotificationManager.class);
        Notification alarm = b.build();
        if (mgr != null) {
            mgr.cancel(TRACKING_NOTIF_ID);
            mgr.notify(ALARM_NOTIF_ID, alarm);
        }
        startForeground(ALARM_NOTIF_ID, alarm);
    }

    /**
     * Silences the alarm and re-arms location tracking after {@code snoozeMinutes}.
     * The alarm notification is replaced with a "snoozed" banner so the user can
     * see how long is left.
     */
    private void snoozeAlarm(int snoozeMinutes) {
        // Cancel any pending countdown ringtone
        if (pendingSoundRunnable != null) {
            soundHandler.removeCallbacks(pendingSoundRunnable);
            pendingSoundRunnable = null;
        }
        // Stop ringtone immediately
        if (alarmRingtone != null) {
            alarmRingtone.stop();
            alarmRingtone = null;
        }

        // Cancel alarm notification, replace with a snooze status notification
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.cancel(ALARM_NOTIF_ID);

        String stopLabel = targetStopName != null ? targetStopName : "your stop";
        PendingIntent snoozeLaunchPi = buildAppLaunchPi(11);
        NotificationCompat.Builder snoozeBuilder = new NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_recent_history)
                .setColor(APP_COLOR)
                .setContentTitle("Alarm Snoozed — " + stopLabel)
                .setContentText("Re-checking in " + snoozeMinutes + " min. Tap to open app.")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true);
        if (snoozeLaunchPi != null) snoozeBuilder.setContentIntent(snoozeLaunchPi);
        startForeground(TRACKING_NOTIF_ID, snoozeBuilder.build());

        // Re-arm tracking after the snooze delay
        alarmFired = false;
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            String action = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .getString(PREF_TRACKING_ACTION, null);
            if (ACTION_START_GEOFENCE.equals(action)) {
                startAboveGroundTracking();
            } else if (ACTION_START_HYBRID.equals(action)) {
                startHybridTracking();
            } else if (ACTION_UPDATE_TARGETS.equals(action)) {
                startMultiTargetTracking();
            } else {
                startSubterraneanTracking();
            }
        }, snoozeMinutes * 60_000L);
    }

    /** Stops sound, cancels notification. In multi-target mode continues tracking remaining stops. */
    private void dismissAlarm() {
        if (pendingSoundRunnable != null) {
            soundHandler.removeCallbacks(pendingSoundRunnable);
            pendingSoundRunnable = null;
        }
        if (alarmRingtone != null) {
            alarmRingtone.stop();
            alarmRingtone = null;
        }
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) {
            mgr.cancel(TRACKING_NOTIF_ID);
            mgr.cancel(ALARM_NOTIF_ID);
        }

        // Multi-target: fired stop was already removed in triggerAlarm;
        // sensors are still running for remaining targets — just reset alarm state.
        if (!targets.isEmpty()) {
            alarmFired = false;
            updateTrackingNotification("Tracking: " + getTargetNames());
            return;
        }

        stopSensors();
        clearTrackingState();
        stopForeground(true);
        stopSelf();
    }

    // ── Tracking state persistence (survive process kill) ──────────────────

    private void saveTrackingState(String action) {
        SharedPreferences.Editor ed = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        ed.putString(PREF_TRACKING_ACTION,    action);
        ed.putString(PREF_TRACKING_STOP_ID,   targetStopId   != null ? targetStopId   : "");
        ed.putString(PREF_TRACKING_STOP_NAME, targetStopName != null ? targetStopName : "");
        if (ACTION_START_GEOFENCE.equals(action) || ACTION_START_HYBRID.equals(action)) {
            ed.putLong(PREF_TRACKING_LAT,     Double.doubleToRawLongBits(targetLat));
            ed.putLong(PREF_TRACKING_LON,     Double.doubleToRawLongBits(targetLon));
            ed.putFloat(PREF_TRACKING_RADIUS, targetRadius);
        }
        if (ACTION_START_WIFI.equals(action) || ACTION_START_HYBRID.equals(action)) {
            ed.putString(PREF_TRACKING_SSID, targetSsid != null ? targetSsid : "");
        }
        ed.putString(PREF_ALARM_STYLE_ACTIVE, currentAlarmStyle != null ? currentAlarmStyle : "defconDrill");
        // For UPDATE_TARGETS the targets JSON is saved separately via saveTargetsJson()
        ed.apply();
    }

    private void clearTrackingState() {
        targets.clear();
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .remove(PREF_TRACKING_ACTION)
                .remove(PREF_TRACKING_STOP_ID)
                .remove(PREF_TRACKING_STOP_NAME)
                .remove(PREF_TRACKING_LAT)
                .remove(PREF_TRACKING_LON)
                .remove(PREF_TRACKING_RADIUS)
                .remove(PREF_TRACKING_SSID)
                .remove(PREF_TARGETS_JSON)
                .remove("pending_alarm_stop_id")
                .remove("pending_alarm_stop_name")
                .remove("pending_alarm_distance")
                .remove("pending_alarm_fired_at")
                .apply();
    }

    private void resumeFromPrefs() {
        SharedPreferences prefs  = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String action            = prefs.getString(PREF_TRACKING_ACTION, null);
        if (action == null) { stopSelf(); return; }

        startForeground(TRACKING_NOTIF_ID,
                buildTrackingNotification("StopSnoozer is watching your route…"));

        currentAlarmStyle = prefs.getString(PREF_ALARM_STYLE_ACTIVE, "defconDrill");

        if (ACTION_START_GEOFENCE.equals(action)) {
            alarmFired     = false;
            targetStopId   = prefs.getString(PREF_TRACKING_STOP_ID,   "");
            targetStopName = prefs.getString(PREF_TRACKING_STOP_NAME, "");
            targetLat      = Double.longBitsToDouble(prefs.getLong(PREF_TRACKING_LAT, 0));
            targetLon      = Double.longBitsToDouble(prefs.getLong(PREF_TRACKING_LON, 0));
            targetRadius   = prefs.getFloat(PREF_TRACKING_RADIUS, 500f);
            if (!isLocationEnabled()) {
                showLocationOffNotification();
                clearTrackingState();
                stopForeground(true);
                stopSelf();
                return;
            }
            startAboveGroundTracking();
        } else if (ACTION_START_WIFI.equals(action)) {
            alarmFired     = false;
            targetStopId   = prefs.getString(PREF_TRACKING_STOP_ID,   "");
            targetStopName = prefs.getString(PREF_TRACKING_STOP_NAME, "");
            targetSsid     = prefs.getString(PREF_TRACKING_SSID, null);
            if (!isWifiEnabled()) {
                showWifiOffNotification();
                clearTrackingState();
                stopForeground(true);
                stopSelf();
                return;
            }
            startSubterraneanTracking();
        } else if (ACTION_START_HYBRID.equals(action)) {
            alarmFired     = false;
            targetStopId   = prefs.getString(PREF_TRACKING_STOP_ID,   "");
            targetStopName = prefs.getString(PREF_TRACKING_STOP_NAME, "");
            targetLat      = Double.longBitsToDouble(prefs.getLong(PREF_TRACKING_LAT, 0));
            targetLon      = Double.longBitsToDouble(prefs.getLong(PREF_TRACKING_LON, 0));
            targetRadius   = prefs.getFloat(PREF_TRACKING_RADIUS, 300f);
            targetSsid     = prefs.getString(PREF_TRACKING_SSID, null);
            startHybridTracking();
        } else if (ACTION_UPDATE_TARGETS.equals(action)) {
            String json = prefs.getString(PREF_TARGETS_JSON, null);
            if (json == null) { stopSelf(); return; }
            targets.clear();
            alarmFired = false;
            try {
                JSONArray arr = new JSONArray(json);
                for (int i = 0; i < arr.length(); i++) {
                    targets.add(TargetStop.fromJson(arr.getJSONObject(i)));
                }
            } catch (Exception ignored) {}
            if (targets.isEmpty()) { stopSelf(); return; }
            startMultiTargetTracking();
        } else {
            stopSelf();
        }
    }

    /** Returns true if the device's location services are switched on. */
    private boolean isLocationEnabled() {
        LocationManager lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        if (lm == null) return false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return lm.isLocationEnabled();
        }
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
                || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
    }

    /**
     * Posts a persistent notification telling the user that location is off and
     * their alarm for the target stop will not fire until it is switched back on.
     * Tapping the notification (or its action button) opens Location Settings.
     */
    private void showLocationOffNotification() {
        Intent settingsIntent = new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
        settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent settingsPi = PendingIntent.getActivity(
                this, 3, settingsIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        String stopLabel = targetStopName != null && !targetStopName.isEmpty()
                ? targetStopName : "your stop";

        PendingIntent locAppPi = buildAppLaunchPi(12);
        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setColor(APP_COLOR)
                .setContentTitle("Location Off — " + stopLabel)
                .setContentText("Turn on location so StopSnoozer can track your stop")
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "Your alarm for \"" + stopLabel + "\" is active but location "
                        + "services are off. Turn them on to be alerted when you arrive."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(locAppPi != null ? locAppPi : settingsPi)
                .addAction(android.R.drawable.ic_menu_mylocation, "Location Settings", settingsPi)
                .build();

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(LOCATION_OFF_NOTIF_ID, n);
    }

    /** Returns true if the device's Wi-Fi radio is switched on. */
    private boolean isWifiEnabled() {
        return wifiManager != null && wifiManager.isWifiEnabled();
    }

    /** Posts a notification telling the user that Wi-Fi is off when an underground alarm activates. */
    private void showWifiOffNotification() {
        Intent settingsIntent = new Intent(Settings.ACTION_WIFI_SETTINGS);
        settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent settingsPi = PendingIntent.getActivity(
                this, 4, settingsIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        String stopLabel = targetStopName != null && !targetStopName.isEmpty()
                ? targetStopName : "your stop";

        PendingIntent wifiAppPi = buildAppLaunchPi(13);
        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setColor(APP_COLOR)
                .setContentTitle("Wi-Fi Off — " + stopLabel)
                .setContentText("Turn on Wi-Fi so StopSnoozer can detect the underground station")
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "Your alarm for \"" + stopLabel + "\" needs Wi-Fi to detect the "
                        + "underground platform. Turn it on to be alerted when you arrive."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(wifiAppPi != null ? wifiAppPi : settingsPi)
                .addAction(android.R.drawable.ic_menu_share, "Wi-Fi Settings", settingsPi)
                .build();

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(LOCATION_OFF_NOTIF_ID + 1, n);
    }

    private void stopSensors() {
        stopAboveGroundTracking();
        stopSubterraneanTracking();
    }

    // ── Notification helpers ───────────────────────────────────────────────

    // App brand amber (#FFB000) — used as notification accent throughout
    private static final int APP_COLOR = Color.parseColor("#FFB000");

    /** Returns a PendingIntent that opens the main app activity. */
    private PendingIntent buildAppLaunchPi(int requestCode) {
        Intent i = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (i == null) return null;
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, requestCode, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private void createNotificationChannels() {
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr == null) return;

        NotificationChannel tracking = new NotificationChannel(
                TRACKING_CHANNEL_ID, "StopSnoozer Tracking",
                NotificationManager.IMPORTANCE_LOW);
        tracking.setDescription("Active journey tracking — do not dismiss");
        tracking.setSound(null, null);
        tracking.setLightColor(APP_COLOR);
        tracking.enableLights(true);
        mgr.createNotificationChannel(tracking);

        // Alarm channel: no sound (we play it via Ringtone to support user-selected tunes)
        NotificationChannel alarm = new NotificationChannel(
                ALARM_CHANNEL_ID, "StopSnoozer Alarm",
                NotificationManager.IMPORTANCE_HIGH);
        alarm.setDescription("Wake-up alert when you arrive at your stop");
        alarm.enableVibration(true);
        alarm.setVibrationPattern(new long[]{0, 400, 200, 400});
        alarm.setLightColor(APP_COLOR);
        alarm.enableLights(true);
        alarm.setSound(null, null); // sound played manually via Ringtone
        mgr.createNotificationChannel(alarm);
    }

    private Notification buildTrackingNotification(String text) {
        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(
                this, 0, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        PendingIntent launchPi = buildAppLaunchPi(10);

        NotificationCompat.Builder b = new NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
                .setContentTitle("StopSnoozer — Tracking Active")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setColor(APP_COLOR)
                .setOngoing(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Tracking", stopPi);

        if (launchPi != null) b.setContentIntent(launchPi);
        return b.build();
    }

    private void updateTrackingNotification(String text) {
        Notification notif = buildTrackingNotification(text);
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(TRACKING_NOTIF_ID, notif);
    }

    /**
     * Re-arms the service when the user swipes the app from Recents.
     * Because android:stopWithTask="false" the service usually survives, so this
     * AlarmManager ping is a belt-and-suspenders fallback for aggressive OEM killers
     * (MIUI, One UI aggressive battery optimisation etc.).
     * API 26+: must use getForegroundService() — startService() is blocked in background.
     * API 23+: setAndAllowWhileIdle() fires even in Doze without needing exact-alarm permission.
     */
    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);
        String savedAction = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(PREF_TRACKING_ACTION, null);
        if (savedAction == null) return;
        Intent restartIntent = new Intent(this, SnoozeTrackingService.class);
        PendingIntent pi;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pi = PendingIntent.getForegroundService(this, 99, restartIntent,
                    PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE);
        } else {
            pi = PendingIntent.getService(this, 99, restartIntent,
                    PendingIntent.FLAG_ONE_SHOT | PendingIntent.FLAG_IMMUTABLE);
        }
        android.app.AlarmManager am = (android.app.AlarmManager) getSystemService(ALARM_SERVICE);
        if (am == null) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP,
                        System.currentTimeMillis() + 3_000L, pi);
            } else {
                am.set(android.app.AlarmManager.RTC_WAKEUP,
                        System.currentTimeMillis() + 3_000L, pi);
            }
        } catch (SecurityException e) {
            // Fallback if exact alarm permission not granted
            am.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 3_000L, pi);
        }
    }

    // ── Multi-target stop descriptor ──────────────────────────────────────

    private static final class TargetStop {
        final String stopId;
        final String stopName;
        final double lat;
        final double lon;
        final float  radius;
        final String ssid; // null = GPS-only; non-null = also WiFi

        TargetStop(String stopId, String stopName, double lat, double lon, float radius, String ssid) {
            this.stopId   = stopId   != null ? stopId   : "";
            this.stopName = stopName != null ? stopName : "";
            this.lat      = lat;
            this.lon      = lon;
            this.radius   = radius;
            this.ssid     = ssid;
        }

        JSONObject toJson() {
            try {
                JSONObject o = new JSONObject();
                o.put("stopId",   stopId);
                o.put("stopName", stopName);
                o.put("lat",      lat);
                o.put("lon",      lon);
                o.put("radius",   (double) radius);
                if (ssid != null) o.put("ssid", ssid);
                return o;
            } catch (Exception e) { return new JSONObject(); }
        }

        static TargetStop fromJson(JSONObject o) {
            return new TargetStop(
                    o.optString("stopId"),
                    o.optString("stopName"),
                    o.optDouble("lat",    0),
                    o.optDouble("lon",    0),
                    (float) o.optDouble("radius", 300),
                    o.has("ssid") ? o.optString("ssid") : null
            );
        }
    }
}
