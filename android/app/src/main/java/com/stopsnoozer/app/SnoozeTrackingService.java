package com.stopsnoozer.app;

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
import android.os.SystemClock;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
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
    static final String ACTION_SELF_TEST_FIRE = "com.stopsnoozer.app.SELF_TEST_FIRE";
    /** Field-test only: records "I am arriving right now" against the log. */
    static final String ACTION_GROUND_TRUTH   = "com.stopsnoozer.app.GROUND_TRUTH";
    static final String EXTRA_GROUND_TRUTH_LABEL = "groundTruthLabel";
    static final String EXTRA_SNOOZE_MINUTES  = "snoozeMinutes";

    /** Broadcast when the early "get ready" nudge fires (two-stage alerts). */
    static final String ACTION_EARLY_NUDGE    = "com.stopsnoozer.app.EARLY_NUDGE";

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

    // ── Route: several stops alarmed one after another ─────────────────────
    //
    // The route lives here, not in Dart, for the same reason the underground
    // engine does: Dart is not guaranteed alive. When it lived in
    // DashboardCubit, stopping stop 1's alarm from the notification (or with
    // the app closed) ended the whole trip, because the service never knew
    // there was a stop 2.
    static final String ACTION_START_ROUTE = "com.stopsnoozer.app.START_ROUTE";
    static final String ACTION_STOP_ROUTE  = "com.stopsnoozer.app.STOP_ROUTE";
    static final String EXTRA_ROUTE_JSON   = "routeJson";
    static final String PREF_ROUTE_JSON    = "tracking_route_json";
    static final String PREF_ROUTE_INDEX   = "tracking_route_index";
    /** The stop whose alarm is ringing or snoozed, until the user dismisses it. */
    private static final String PREF_FIRED_TARGET = "tracking_fired_target_json";

    // ── Notification channels ──────────────────────────────────────────────
    private static final String TRACKING_CHANNEL_ID  = "snooze_tracking";
    private static final String ALARM_CHANNEL_ID     = "snooze_alarm";
    private static final int    TRACKING_NOTIF_ID    = 1001;
    private static final int    ALARM_NOTIF_ID       = 1002;
    private static final int    LOCATION_OFF_NOTIF_ID = 1003;
    private static final int    EARLY_NUDGE_NOTIF_ID  = 1004;

    private static final int WIFI_SCAN_INTERVAL_MS           = 8_000;
    private static final int WIFI_SCAN_THROTTLED_INTERVAL_MS = 32_000;

    /**
     * Two-stage alerts. The early nudge fires at this multiple of the wake radius
     * so the user has time to gather bags and stand up before the firm alarm.
     * 2.5× a 500 m radius ≈ 1.25 km out, roughly 60–90 s at suburban rail speed.
     */
    private static final float EARLY_NUDGE_RADIUS_MULTIPLIER = 2.5f;
    /** Never nudge further out than this, or long-distance rail nudges far too early. */
    private static final float EARLY_NUDGE_MAX_METRES        = 2_000f;
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

    /** Ordered stops of the active route; empty when no route is running. */
    private final ArrayList<TargetStop> route = new ArrayList<>();
    /** Index into {@link #route} of the stop currently armed. */
    private int routeIndex = 0;
    /**
     * The multi-target stop whose alarm fired and has not been dismissed yet.
     * Dismissing it is what advances a route; snoozing re-arms it. Persisted,
     * because a process kill while ringing must not lose the alarm.
     */
    private TargetStop firedTarget;
    /** True while the "Test your alarm" alarm (not a real stop) is ringing. */
    private boolean selfTestRinging;

    // ── Underground stack (v2) ─────────────────────────────────────────────
    private UndergroundEngine     undergroundEngine;
    private WifiPresenceDetector  wifiPresence;
    private CellObserver          cellObserver;
    private SensorLogger          sensorLogger;

    static final String ACTION_START_UNDERGROUND = "com.stopsnoozer.app.START_UNDERGROUND";
    static final String EXTRA_JOURNEY_PLAN       = "journeyPlan";
    static final String EXTRA_ENABLE_LOGGING     = "enableSensorLogging";
    static final String PREF_JOURNEY_PLAN        = "tracking_journey_plan";

    // ── Lifecycle ──────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannels();
        fusedClient     = LocationServices.getFusedLocationProviderClient(this);
        wifiManager     = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        wifiScanHandler = new Handler(Looper.getMainLooper());
        soundHandler    = new Handler(Looper.getMainLooper());
        restoreRouteState();
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
                // A single stop is a one-stop route. Running it through the
                // shared target list is what lets it coexist with saved stops:
                // as a separate single-target mode it was silently ignored
                // whenever any saved stop was active.
                if (!isLocationEnabled()) {
                    targetStopName = intent.getStringExtra("stopName");
                    showLocationOffNotification();
                    stopEverything();
                    return START_NOT_STICKY;
                }
                startRoute(java.util.Collections.singletonList(new TargetStop(
                        intent.getStringExtra("stopId"),
                        intent.getStringExtra("stopName"),
                        intent.getDoubleExtra("lat", 0),
                        intent.getDoubleExtra("lon", 0),
                        intent.getFloatExtra("radiusMetres", 500f),
                        null, false, intent.getStringExtra("alarmStyle"))));
                break;

            case ACTION_START_ROUTE: {
                ArrayList<TargetStop> legs = new ArrayList<>();
                try {
                    JSONArray arr = new JSONArray(intent.getStringExtra(EXTRA_ROUTE_JSON));
                    for (int i = 0; i < arr.length(); i++) {
                        legs.add(TargetStop.fromJson(arr.getJSONObject(i)));
                    }
                } catch (Exception ignored) {}
                if (legs.isEmpty()) break;
                startRoute(legs);
                break;
            }

            case ACTION_STOP_ROUTE:
                stopRoute();
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

            case ACTION_START_HYBRID: {
                // One-stop route with Wi-Fi corroboration; see ACTION_START_GEOFENCE.
                String ssid = intent.getStringExtra("targetSsid");
                startRoute(java.util.Collections.singletonList(new TargetStop(
                        intent.getStringExtra("stopId"),
                        intent.getStringExtra("stopName"),
                        intent.getDoubleExtra("lat", 0),
                        intent.getDoubleExtra("lon", 0),
                        intent.getFloatExtra("radiusMetres", 300f),
                        ssid != null && !ssid.isEmpty() ? ssid : null,
                        false, intent.getStringExtra("alarmStyle"))));
                break;
            }

            case ACTION_UPDATE_TARGETS: {
                // Replaces the SAVED stops only. The active route's stop is not
                // the caller's to replace: Dart re-sends saved stops on every
                // cold start, and that used to wipe a trip in progress.
                String json = intent.getStringExtra("targetsJson");
                ArrayList<TargetStop> saved = new ArrayList<>();
                if (json != null && !json.isEmpty()) {
                    try {
                        JSONArray arr = new JSONArray(json);
                        for (int i = 0; i < arr.length(); i++) {
                            saved.add(TargetStop.fromJson(arr.getJSONObject(i)));
                        }
                    } catch (Exception ignored) {}
                }
                restoreTargetsIfEmpty();
                for (int i = targets.size() - 1; i >= 0; i--) {
                    if (!targets.get(i).routeLeg) targets.remove(i);
                }
                for (TargetStop s : saved) addTargetDedup(s);
                // A saved stop that is ringing/snoozed and was just switched off
                // must not come back when the snooze ends.
                if (firedTarget != null && !firedTarget.routeLeg
                        && !containsStop(saved, firedTarget.stopId)) {
                    setFiredTarget(null);
                }
                alarmFired = false;
                if (targets.isEmpty() && firedTarget == null) {
                    stopEverything();
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
                // Replace a saved stop with the same id, but never a route stop:
                // the route needs its own entry to advance when it is dismissed.
                for (int i = targets.size() - 1; i >= 0; i--) {
                    if (targets.get(i).stopId.equals(newId) && !targets.get(i).routeLeg) {
                        targets.remove(i);
                    }
                }
                addTargetDedup(new TargetStop(newId, newName, newLat, newLon, newRad, newSsid));
                alarmFired = false;
                saveTargetsJson();
                saveTrackingState(ACTION_UPDATE_TARGETS);
                startMultiTargetTracking();
                break;
            }

            case ACTION_STOP:
                // "Stop Tracking" means stop. It used to share dismissAlarm(),
                // which in multi-stop mode only reset the alarm and carried on.
                stopEverything();
                break;

            case ACTION_STOP_ALARM:
                dismissAlarm();
                break;

            case ACTION_SNOOZE:
                int minutes = intent.getIntExtra(EXTRA_SNOOZE_MINUTES, 5);
                snoozeAlarm(minutes);
                break;

            case ACTION_START_UNDERGROUND: {
                alarmFired = false;
                String planJson = intent.getStringExtra(EXTRA_JOURNEY_PLAN);
                boolean logging = intent.getBooleanExtra(EXTRA_ENABLE_LOGGING, false);
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                        .putString(PREF_JOURNEY_PLAN, planJson)
                        .apply();
                saveTrackingState(ACTION_START_UNDERGROUND);
                startUndergroundTracking(planJson, logging);
                break;
            }

            case ACTION_GROUND_TRUTH: {
                // Field-test marker. Without this the sensor logs are just
                // traces with nothing to score them against, and no threshold
                // can be calibrated from them.
                if (sensorLogger != null) {
                    String label = intent.getStringExtra(EXTRA_GROUND_TRUTH_LABEL);
                    sensorLogger.logGroundTruth(
                            label != null && !label.isEmpty() ? label : "arrival");
                    if (undergroundEngine != null) {
                        sensorLogger.logNote("engine believed index="
                                + undergroundEngine.currentIndex()
                                + " confidence=" + String.format(java.util.Locale.US,
                                        "%.2f", undergroundEngine.confidence()));
                    }
                }
                break;
            }

            case ACTION_SELF_TEST_FIRE:
                // Reached only via CommuteAlarmReceiver, i.e. the OS really did
                // wake us. Fire the alarm UI with no tracking targets attached.
                // The tracked stops are left alone: clearing them (as this
                // did) meant a self-test run during a trip ended the trip.
                if (alarmFired) break;   // a real alarm is ringing; don't mask it
                restoreTargetsIfEmpty();
                selfTestRinging = true;
                targetStopId    = "__selftest__";
                targetStopName  = "Alarm Test — it works";
                currentAlarmStyle = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                        .getString(PREF_ALARM_STYLE_ACTIVE, "defconDrill");
                triggerAlarm(targetStopId, targetStopName, 0f);
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
    @VisibleForTesting
    void checkLocationAndTrigger(Location loc) {
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
                maybeEarlyNudge(t.stopId, t.stopName, t.radius, dist[0]);
            }
        } else {
            Location.distanceBetween(loc.getLatitude(), loc.getLongitude(),
                    targetLat, targetLon, dist);
            if (dist[0] <= targetRadius) {
                triggerAlarm(targetStopId, targetStopName, dist[0]);
            } else {
                maybeEarlyNudge(targetStopId, targetStopName, targetRadius, dist[0]);
            }
        }
    }

    // ── Two-stage alerts (early nudge → firm alarm) ────────────────────────

    /** Stop IDs already nudged, so the gentle alert fires at most once each. */
    private final java.util.HashSet<String> nudgedStopIds = new java.util.HashSet<>();

    /**
     * Posts the gentle "start getting ready" alert when the user first crosses
     * the outer ring, well before the firm alarm at the wake radius.
     *
     * <p>Fires once per stop per journey. Silent and low-priority by design: its
     * job is to be noticed if the user is awake, not to wake them — that is the
     * firm alarm's job, and duplicating it would train users to ignore both.
     */
    private void maybeEarlyNudge(String stopId, String stopName,
                                 float radius, float distance) {
        if (stopId == null || stopId.isEmpty()) return;
        if (nudgedStopIds.contains(stopId)) return;

        float nudgeAt = Math.min(radius * EARLY_NUDGE_RADIUS_MULTIPLIER,
                                 Math.max(radius, EARLY_NUDGE_MAX_METRES));
        // Only nudge if the outer ring is meaningfully outside the alarm radius,
        // otherwise both alerts land within seconds of each other.
        if (nudgeAt <= radius * 1.2f) return;
        if (distance > nudgeAt) return;

        nudgedStopIds.add(stopId);

        String label = stopName != null && !stopName.isEmpty() ? stopName : "your stop";
        PendingIntent launchPi = buildAppLaunchPi(14);
        NotificationCompat.Builder b = new NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setColor(APP_COLOR)
                .setContentTitle("Get ready — " + label + " is next")
                .setContentText(Math.round(distance) + "m to go")
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "You're about " + Math.round(distance) + "m from " + label
                        + ". The full alarm will sound when you arrive."))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setAutoCancel(true);
        if (launchPi != null) b.setContentIntent(launchPi);

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(EARLY_NUDGE_NOTIF_ID, b.build());

        Intent bc = new Intent(ACTION_EARLY_NUDGE);
        bc.putExtra("stopId",         stopId);
        bc.putExtra("stopName",       stopName);
        bc.putExtra("distanceMetres", distance);
        sendBroadcast(bc);
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
                // Cell polling shares this cadence: both are opportunistic
                // corroboration and neither should run as a busy loop.
                evaluateCellResults();
                long next = accepted ? WIFI_SCAN_INTERVAL_MS : WIFI_SCAN_THROTTLED_INTERVAL_MS;
                wifiScanHandler.postDelayed(this, next);
            }
        };
        wifiScanHandler.post(wifiScanRunnable);
        updateTrackingNotification("Underground sensing: " + targetStopName);
    }

    /**
     * Wi-Fi presence evaluation (U3).
     *
     * <p>Previously this matched a per-stop SSID string to identify the station.
     * That model was unsound: Underground SSIDs are provider-branded and
     * identical across the whole network, so a match said nothing about *which*
     * station. Identity now comes from the route model; Wi-Fi only corroborates
     * that we are at a station at all.
     *
     * <p>When an underground journey plan is active, a station-grade hit is
     * forwarded to {@link UndergroundEngine} as corroboration. Without a plan we
     * have no sequence to reason about, so a bare hit is not sufficient grounds
     * to fire an alarm — doing so is what produced false triggers at every
     * station on the line.
     */
    private void evaluateWifiResults() {
        if (wifiPresence == null || undergroundEngine == null) return;
        WifiPresenceDetector.Presence p = wifiPresence.evaluate();
        if (!p.atStation) return;

        // Corroboration, NOT an absolute fix. Wi-Fi presence cannot say which
        // station this is, so the engine advances only if its own timing gate
        // already agrees, and only once per station.
        undergroundEngine.corroborateArrival("wifi_presence");
    }

    /**
     * Polls for a fresh cell observation and uses it as corroboration.
     *
     * <p>Runs on the same throttled cadence as Wi-Fi rather than continuously:
     * underground this usually returns nothing, and when it does return
     * something the reading is only trustworthy if it is under 5 s old — which
     * {@link CellObserver} enforces. A stale cached cell from the previous
     * station is worse than no reading, so an empty result is treated as "no
     * information", never as "position unchanged".
     */
    private void evaluateCellResults() {
        if (cellObserver == null || undergroundEngine == null) return;
        java.util.List<CellObserver.Observation> fresh = cellObserver.observeFresh();
        if (fresh.isEmpty()) return;

        // A registered cell means the handset actually attached to a base
        // station, which in tunnel conditions effectively only happens at a
        // platform with coverage.
        for (CellObserver.Observation o : fresh) {
            if (o.registered) {
                undergroundEngine.corroborateArrival("cell_registered");
                return;
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
        if (needGps) {
            // Request updates even with location switched off: the fused
            // provider starts delivering as soon as it is switched back on.
            // Skipping the request (as this did) meant a trip armed with
            // location off never tracked again, and nobody was told.
            if (!isLocationEnabled()) {
                targetStopName = names.toString();
                showLocationOffNotification();
            }
            startAboveGroundTracking();
        }
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

        // The firm alarm supersedes the gentle nudge — drop the stale banner.
        nudgedStopIds.remove(stopId);
        NotificationManager nudgeMgr = getSystemService(NotificationManager.class);
        if (nudgeMgr != null) nudgeMgr.cancel(EARLY_NUDGE_NOTIF_ID);

        // Multi-target: remove fired stop; keep sensors running for remaining targets
        boolean hasRemaining = false;
        if (!targets.isEmpty()) {
            for (int i = targets.size() - 1; i >= 0; i--) {
                if (targets.get(i).stopId.equals(stopId)) {
                    TargetStop fired = targets.remove(i);
                    setFiredTarget(fired);
                    selfTestRinging = false;   // a real stop now owns the alarm
                    // Each stop rings in its own style (I-09). playAlarmSound()
                    // reads the pref, so persist it, not just the field.
                    currentAlarmStyle = fired.alarmStyle != null ? fired.alarmStyle : "defconDrill";
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                            .putString(PREF_ALARM_STYLE_ACTIVE, currentAlarmStyle).apply();
                    break;
                }
            }
            hasRemaining = !targets.isEmpty();
            // Saved even when empty: a stale list would resurrect the fired stop
            // after a process restart, ringing it twice.
            saveTargetsJson();
        }
        // Stop sensors only when this was the last target. The service itself
        // stays up: the alarm is still ringing, and dismissing it may arm the
        // route's next stop.
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
        cancelPendingSnooze();
        final TargetStop snoozed = firedTarget;
        snoozeRunnable = () -> {
            snoozeRunnable = null;
            String action = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .getString(PREF_TRACKING_ACTION, null);
            if (action == null) return;   // tracking was stopped during the snooze
            if (ACTION_START_GEOFENCE.equals(action)) {
                startAboveGroundTracking();
            } else if (ACTION_START_HYBRID.equals(action)) {
                startHybridTracking();
            } else if (ACTION_UPDATE_TARGETS.equals(action)) {
                // triggerAlarm() removed the fired stop from the list; without
                // putting it back, a snoozed alarm never rang again.
                if (snoozed != null && firedTarget == snoozed) addTargetDedup(snoozed);
                saveTargetsJson();
                startMultiTargetTracking();
            } else {
                startSubterraneanTracking();
            }
        };
        soundHandler.postDelayed(snoozeRunnable, snoozeMinutes * 60_000L);
    }

    private Runnable snoozeRunnable;

    private void cancelPendingSnooze() {
        if (snoozeRunnable != null) {
            soundHandler.removeCallbacks(snoozeRunnable);
            snoozeRunnable = null;
        }
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

        cancelPendingSnooze();

        // Multi-target: the fired stop was already removed in triggerAlarm.
        // Dismissing it is the user saying "done with this stop" — for a route
        // that means arming the next one. Only the first dismiss of a given
        // alarm advances: the notification and the in-app screen can both send
        // one, and advancing twice would skip a stop.
        // Dismissing the self-test alarm is not "done with this stop".
        TargetStop dismissed = selfTestRinging ? null : firedTarget;
        selfTestRinging = false;
        if (dismissed != null) {
            setFiredTarget(null);
            // Re-armed after a restart or snooze but dismissed before it rang
            // again: it is done either way.
            for (int i = targets.size() - 1; i >= 0; i--) {
                if (targets.get(i).stopId.equals(dismissed.stopId)) targets.remove(i);
            }
            if (dismissed.routeLeg) {
                routeIndex++;
                armCurrentRouteLeg();
                saveRouteState();
            }
        }

        if (!targets.isEmpty()) {
            alarmFired = false;
            saveTargetsJson();
            saveTrackingState(ACTION_UPDATE_TARGETS);
            // Sensors were stopped if the fired stop was the last one armed.
            if (!isActivelyTracking()) startMultiTargetTracking();
            else updateTrackingNotification("Tracking: " + getTargetNames());
            return;
        }

        stopEverything();
    }

    /** Ends all tracking: route, saved stops, sensors, notifications, service. */
    private void stopEverything() {
        cancelPendingSnooze();
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
        stopSensors();
        clearTrackingState();
        stopForeground(true);
        stopSelf();
    }

    // ── Route ──────────────────────────────────────────────────────────────

    /** Starts a new route, replacing any previous one. Saved stops are kept. */
    private void startRoute(java.util.List<TargetStop> legs) {
        restoreTargetsIfEmpty();
        // A new route replaces the old route, and any alarm still pending from
        // it (ringing or snoozed) is abandoned along with it.
        for (int i = targets.size() - 1; i >= 0; i--) {
            if (targets.get(i).routeLeg) targets.remove(i);
        }
        if (firedTarget != null && firedTarget.routeLeg) setFiredTarget(null);
        route.clear();
        for (TargetStop l : legs) route.add(l.asRouteLeg());
        routeIndex = 0;
        armCurrentRouteLeg();
        saveRouteState();
        alarmFired = false;
        saveTargetsJson();
        saveTrackingState(ACTION_UPDATE_TARGETS);
        startMultiTargetTracking();
    }

    /** Ends the route only; saved stops keep being tracked. */
    private void stopRoute() {
        restoreTargetsIfEmpty();
        for (int i = targets.size() - 1; i >= 0; i--) {
            if (targets.get(i).routeLeg) targets.remove(i);
        }
        if (firedTarget != null && firedTarget.routeLeg) setFiredTarget(null);
        route.clear();
        routeIndex = 0;
        saveRouteState();
        if (targets.isEmpty() && firedTarget == null) {
            stopEverything();
            return;
        }
        saveTargetsJson();
        saveTrackingState(ACTION_UPDATE_TARGETS);
        startMultiTargetTracking();
    }

    /** Puts the route's current stop into the tracked list, if there is one. */
    private void armCurrentRouteLeg() {
        for (int i = targets.size() - 1; i >= 0; i--) {
            if (targets.get(i).routeLeg) targets.remove(i);
        }
        if (routeIndex < 0 || routeIndex >= route.size()) {
            route.clear();
            routeIndex = 0;
            return;
        }
        TargetStop leg = route.get(routeIndex);
        // A saved stop or scheduled alarm for the same place would ring a
        // second time a few seconds later; the route's own entry wins.
        for (int i = targets.size() - 1; i >= 0; i--) {
            if (targets.get(i).stopId.equals(leg.stopId)) targets.remove(i);
        }
        targets.add(leg);
    }

    private void addTargetDedup(TargetStop t) {
        if (!containsStop(targets, t.stopId)) targets.add(t);
    }

    private static boolean containsStop(java.util.List<TargetStop> list, String stopId) {
        for (TargetStop t : list) if (t.stopId.equals(stopId)) return true;
        return false;
    }

    /** After a process restart the in-memory list is empty; reload it. */
    private void restoreTargetsIfEmpty() {
        if (!targets.isEmpty()) return;
        String tj = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(PREF_TARGETS_JSON, null);
        if (tj == null) return;
        try {
            JSONArray arr = new JSONArray(tj);
            for (int i = 0; i < arr.length(); i++) {
                targets.add(TargetStop.fromJson(arr.getJSONObject(i)));
            }
        } catch (Exception ignored) {}
    }

    private void setFiredTarget(TargetStop t) {
        firedTarget = t;
        SharedPreferences.Editor ed = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        if (t == null) ed.remove(PREF_FIRED_TARGET);
        else ed.putString(PREF_FIRED_TARGET, t.toJson().toString());
        ed.apply();
    }

    private void saveRouteState() {
        SharedPreferences.Editor ed = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        if (route.isEmpty()) {
            ed.remove(PREF_ROUTE_JSON).remove(PREF_ROUTE_INDEX);
        } else {
            JSONArray arr = new JSONArray();
            for (TargetStop t : route) arr.put(t.toJson());
            ed.putString(PREF_ROUTE_JSON, arr.toString());
            ed.putInt(PREF_ROUTE_INDEX, routeIndex);
        }
        ed.apply();
    }

    private void restoreRouteState() {
        SharedPreferences p = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        route.clear();
        String rj = p.getString(PREF_ROUTE_JSON, null);
        if (rj != null) {
            try {
                JSONArray arr = new JSONArray(rj);
                for (int i = 0; i < arr.length(); i++) {
                    route.add(TargetStop.fromJson(arr.getJSONObject(i)).asRouteLeg());
                }
            } catch (Exception ignored) { route.clear(); }
        }
        routeIndex = p.getInt(PREF_ROUTE_INDEX, 0);
        String fj = p.getString(PREF_FIRED_TARGET, null);
        firedTarget = null;
        if (fj != null) {
            try { firedTarget = TargetStop.fromJson(new JSONObject(fj)); }
            catch (Exception ignored) {}
        }
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
        route.clear();
        routeIndex = 0;
        firedTarget = null;
        nudgedStopIds.clear();
        clearBeliefState();
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .remove(PREF_ROUTE_JSON)
                .remove(PREF_ROUTE_INDEX)
                .remove(PREF_FIRED_TARGET)
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
        } else if (ACTION_START_UNDERGROUND.equals(action)) {
            alarmFired = false;
            String planJson = prefs.getString(PREF_JOURNEY_PLAN, null);
            if (planJson == null) { stopSelf(); return; }
            // Position is not restored: the engine's belief was in memory and is
            // gone. Restarting from the plan's boarding station is wrong, so the
            // engine will run at reduced confidence and the fail-safe will wake
            // the user early rather than assert a position it cannot justify.
            startUndergroundTracking(planJson, false);
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
            // An alarm that was ringing or snoozed when the process died has
            // lost its sound and its snooze timer. Re-arm the stop so it rings
            // again rather than being silently dropped.
            if (firedTarget != null) addTargetDedup(firedTarget);
            if (targets.isEmpty()) { stopEverything(); return; }
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
        stopUndergroundTracking();
    }

    // ── Underground sensor-fusion tracking (v2) ─────────────────────────────

    /**
     * Starts the barometer/accelerometer/timing engine for a pre-selected route.
     *
     * <p>Runs alongside GPS rather than replacing it: above ground GPS is far
     * more reliable (~98%), so the engine is the fallback that takes over when
     * the signal disappears — not a substitute for it.
     */
    private void startUndergroundTracking(String planJson, boolean enableLogging) {
        JourneyPlan plan = JourneyPlan.fromJson(planJson);
        if (plan == null) {
            // Malformed or empty plan: fall back to plain GPS rather than
            // silently tracking nothing.
            if (isLocationEnabled()) startAboveGroundTracking();
            return;
        }

        sensorLogger = SensorLogger.createIfEnabled(
                this, enableLogging, plan.lineId);
        wifiPresence = new WifiPresenceDetector(this, sensorLogger);
        cellObserver = new CellObserver(this, sensorLogger);
        startServiceStateWatch();

        undergroundEngine = new UndergroundEngine(this, plan,
                new UndergroundEngine.Listener() {
                    @Override
                    public void onTargetReached(String stopId, String stopName) {
                        triggerAlarm(stopId, stopName, 0f);
                    }

                    @Override
                    public void onLowConfidenceApproach(String stopId, String stopName,
                                                        String reason) {
                        // Honest early alarm — never a silent guess.
                        triggerLowConfidenceAlarm(stopId, stopName, reason);
                    }

                    @Override
                    public void onPositionChanged(int index, String stopName,
                                                  double confidence) {
                        updateTrackingNotification(String.format(
                                java.util.Locale.UK,
                                "Underground: %s (%.0f%% confident)",
                                stopName, confidence * 100));
                    }

                    @Override
                    public void onSurfaced() {
                        // Back above ground — GPS is authoritative again.
                        if (isLocationEnabled() && locationCallback == null) {
                            startAboveGroundTracking();
                        }
                    }

                    @Override
                    public void onSubmerged() {
                        // GPS cannot fix at platform depth; keeping the receiver
                        // alive down here is the largest avoidable battery cost
                        // in the whole underground path.
                        stopAboveGroundTracking();
                        if (sensorLogger != null) {
                            sensorLogger.logNote("submerged: GPS stopped");
                        }
                    }

                    @Override
                    public void onPersistState(int index, double conf, long msSinceArrival) {
                        saveBeliefState(index, conf, msSinceArrival);
                    }
                }, sensorLogger);

        boolean ok = undergroundEngine.start();
        if (!ok) {
            undergroundEngine = null;
            if (isLocationEnabled()) startAboveGroundTracking();
            return;
        }

        restoreBeliefStateIfAny();

        // GPS in parallel: it works at shallow/open-air stations and is the
        // strongest available fix whenever it is present.
        if (isLocationEnabled()) startAboveGroundTracking();
        // Opportunistic Wi-Fi corroboration on the throttle-aware cadence.
        if (wifiPresence.isWifiEnabled()) startSubterraneanTracking();

        updateTrackingNotification("Underground tracking active");
    }

    // ── Telephony service state (network entry/exit, U10) ──────────────────

    private android.telephony.PhoneStateListener phoneStateListener;
    private boolean lastHadService = true;

    /**
     * Watches for cellular service loss and reacquisition.
     *
     * <p>Losing all service is a strong, cheap indicator of entering a tunnel,
     * and regaining it marks a station with coverage or the surface. Unlike
     * reading cell identities this needs no fresh-data guarantees — the
     * transition itself is the signal, so stale-cache concerns do not apply.
     *
     * <p>Purely advisory: it feeds logging and corroboration, never an alarm on
     * its own. Coverage is patchy and improving as the Boldyn rollout proceeds,
     * so its meaning changes over time and must not be load-bearing.
     */
    private void startServiceStateWatch() {
        if (ContextCompat.checkSelfPermission(this,
                android.Manifest.permission.READ_PHONE_STATE)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            return;
        }
        android.telephony.TelephonyManager tm =
                (android.telephony.TelephonyManager) getSystemService(TELEPHONY_SERVICE);
        if (tm == null) return;

        phoneStateListener = new android.telephony.PhoneStateListener() {
            @Override
            @SuppressWarnings("deprecation")
            public void onServiceStateChanged(android.telephony.ServiceState serviceState) {
                boolean hasService = serviceState.getState()
                        == android.telephony.ServiceState.STATE_IN_SERVICE;
                if (hasService == lastHadService) return;
                lastHadService = hasService;
                if (sensorLogger != null) {
                    sensorLogger.logServiceState(hasService ? "IN_SERVICE" : "OUT_OF_SERVICE");
                }
                // Regaining service underground usually means a covered
                // platform. Corroboration only — the engine still applies its
                // own timing gate before advancing.
                if (hasService && undergroundEngine != null) {
                    undergroundEngine.corroborateArrival("service_regained");
                }
            }
        };
        try {
            tm.listen(phoneStateListener,
                    android.telephony.PhoneStateListener.LISTEN_SERVICE_STATE);
        } catch (Exception ignored) {
            phoneStateListener = null;
        }
    }

    private void stopServiceStateWatch() {
        if (phoneStateListener == null) return;
        try {
            android.telephony.TelephonyManager tm =
                    (android.telephony.TelephonyManager) getSystemService(TELEPHONY_SERVICE);
            if (tm != null) {
                tm.listen(phoneStateListener,
                        android.telephony.PhoneStateListener.LISTEN_NONE);
            }
        } catch (Exception ignored) {
        } finally {
            phoneStateListener = null;
        }
    }

    // ── Belief-state checkpointing (survives OEM process kills) ────────────

    private static final String PREF_BELIEF_INDEX      = "belief_index";
    private static final String PREF_BELIEF_CONFIDENCE = "belief_confidence";
    private static final String PREF_BELIEF_SINCE_MS   = "belief_since_ms";
    private static final String PREF_BELIEF_WALL_MS    = "belief_wall_ms";
    private static final String PREF_BELIEF_BOOT_MS    = "belief_boot_ms";

    /**
     * Checkpoints the engine's belief.
     *
     * <p>Stores a wall-clock/monotonic pair, not just one clock. On restore,
     * {@code elapsedRealtime()} gives a gap immune to time-zone and clock
     * changes — but it resets to zero on reboot, so a saved value larger than
     * the current one is how a reboot is detected. Wall clock alone would be
     * fooled by the user changing the time; monotonic alone cannot see a reboot.
     */
    private void saveBeliefState(int index, double confidence, long msSinceArrival) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putInt(PREF_BELIEF_INDEX, index)
                .putFloat(PREF_BELIEF_CONFIDENCE, (float) confidence)
                .putLong(PREF_BELIEF_SINCE_MS, msSinceArrival)
                .putLong(PREF_BELIEF_WALL_MS, System.currentTimeMillis())
                .putLong(PREF_BELIEF_BOOT_MS, SystemClock.elapsedRealtime())
                .apply();
    }

    /**
     * Restores a checkpoint, if one exists and is still meaningful.
     *
     * <p>A detected reboot invalidates the belief outright: the device was off
     * for an unknown period and the journey is almost certainly over. Guessing
     * would be worse than starting clean.
     */
    private void restoreBeliefStateIfAny() {
        if (undergroundEngine == null) return;
        SharedPreferences p = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        if (!p.contains(PREF_BELIEF_INDEX)) return;

        int index        = p.getInt(PREF_BELIEF_INDEX, 0);
        double conf      = p.getFloat(PREF_BELIEF_CONFIDENCE, 1.0f);
        long sinceMs     = p.getLong(PREF_BELIEF_SINCE_MS, 0L);
        long savedWall   = p.getLong(PREF_BELIEF_WALL_MS, 0L);
        long savedBoot   = p.getLong(PREF_BELIEF_BOOT_MS, 0L);

        long nowBoot = SystemClock.elapsedRealtime();
        boolean rebooted = savedBoot > nowBoot;

        if (rebooted) {
            clearBeliefState();
            if (sensorLogger != null) {
                sensorLogger.logNote("belief discarded: reboot detected");
            }
            return;
        }

        long gapMs = nowBoot - savedBoot;
        // Cross-check against the wall clock: if they disagree wildly the clock
        // was changed, so trust the monotonic one.
        long wallGap = System.currentTimeMillis() - savedWall;
        if (wallGap > 0 && Math.abs(wallGap - gapMs) > 60_000L) {
            if (sensorLogger != null) {
                sensorLogger.logNote("clock skew: wallGap=" + wallGap
                        + " monotonicGap=" + gapMs);
            }
        }

        undergroundEngine.restoreState(index, conf, sinceMs + gapMs, gapMs);
    }

    private void clearBeliefState() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .remove(PREF_BELIEF_INDEX)
                .remove(PREF_BELIEF_CONFIDENCE)
                .remove(PREF_BELIEF_SINCE_MS)
                .remove(PREF_BELIEF_WALL_MS)
                .remove(PREF_BELIEF_BOOT_MS)
                .apply();
    }

    private void stopUndergroundTracking() {
        stopServiceStateWatch();
        if (undergroundEngine != null) {
            undergroundEngine.stop();
            undergroundEngine = null;
        }
        if (sensorLogger != null) {
            sensorLogger.close();
            sensorLogger = null;
        }
        wifiPresence = null;
        cellObserver = null;
    }

    /**
     * Fires the alarm early, stating plainly that position could not be
     * confirmed. Users tolerate an early alarm; they do not tolerate a confident
     * alarm at the wrong station.
     */
    private void triggerLowConfidenceAlarm(String stopId, String stopName, String reason) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putString("pending_alarm_reason", reason)
                .apply();
        triggerAlarm(stopId, "Approaching " + stopName, 0f);
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
        /** True for the route's current stop; dismissing it arms the next. */
        final boolean routeLeg;
        /** "subtlePulse" / "defconDrill", or null to use the global setting. */
        final String alarmStyle;
        /** Transit mode name, carried only so the app can redraw the trip. */
        String mode;

        TargetStop(String stopId, String stopName, double lat, double lon, float radius, String ssid) {
            this(stopId, stopName, lat, lon, radius, ssid, false, null);
        }

        TargetStop(String stopId, String stopName, double lat, double lon, float radius,
                   String ssid, boolean routeLeg, String alarmStyle) {
            this.stopId   = stopId   != null ? stopId   : "";
            this.stopName = stopName != null ? stopName : "";
            this.lat      = lat;
            this.lon      = lon;
            this.radius   = radius;
            this.ssid     = ssid;
            this.routeLeg = routeLeg;
            this.alarmStyle = alarmStyle != null && !alarmStyle.isEmpty() ? alarmStyle : null;
        }

        TargetStop asRouteLeg() {
            TargetStop t = new TargetStop(stopId, stopName, lat, lon, radius, ssid, true, alarmStyle);
            t.mode = mode;
            return t;
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
                if (routeLeg) o.put("routeLeg", true);
                if (alarmStyle != null) o.put("alarmStyle", alarmStyle);
                if (mode != null) o.put("mode", mode);
                return o;
            } catch (Exception e) { return new JSONObject(); }
        }

        static TargetStop fromJson(JSONObject o) {
            // Dart sends "radiusMetres"; this class persists "radius". Reading
            // only "radius" made every saved stop use 300 m whatever the user set.
            double radius = o.has("radius")
                    ? o.optDouble("radius", 300)
                    : o.optDouble("radiusMetres", 300);
            String ssid = o.has("ssid") && !o.isNull("ssid") ? o.optString("ssid") : null;
            TargetStop t = new TargetStop(
                    o.optString("stopId"),
                    o.optString("stopName"),
                    o.optDouble("lat",    0),
                    o.optDouble("lon",    0),
                    (float) radius,
                    ssid != null && !ssid.isEmpty() ? ssid : null,
                    o.optBoolean("routeLeg", false),
                    o.has("alarmStyle") ? o.optString("alarmStyle") : null
            );
            if (o.has("mode")) t.mode = o.optString("mode");
            return t;
        }
    }
}
