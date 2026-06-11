package com.example.stop_snoozer;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.location.Location;
import android.location.LocationManager;
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

import java.util.List;

/**
 * Foreground service — GPS geofencing (above ground) + Wi-Fi SSID scanning (underground).
 * Stays alive after alarm fires to keep sound playing until the user explicitly stops it.
 */
public class SnoozeTrackingService extends Service {

    // ── Action constants ───────────────────────────────────────────────────
    static final String ACTION_START_GEOFENCE = "com.stopsnoozer.app.START_GEOFENCE";
    static final String ACTION_START_WIFI     = "com.stopsnoozer.app.START_WIFI";
    static final String ACTION_STOP           = "com.stopsnoozer.app.STOP_TRACKING";
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

    private static final int WIFI_SCAN_INTERVAL_MS          = 8_000;
    private static final int WIFI_SCAN_THROTTLED_INTERVAL_MS = 32_000;

    // ── State ──────────────────────────────────────────────────────────────
    private FusedLocationProviderClient fusedClient;
    private LocationCallback            locationCallback;
    private WifiManager                 wifiManager;
    private BroadcastReceiver           wifiScanReceiver;
    private Handler                     wifiScanHandler;
    private Runnable                    wifiScanRunnable;
    private Ringtone                    alarmRingtone;

    private volatile boolean alarmFired = false;

    private String targetStopId;
    private String targetStopName;
    private double targetLat;
    private double targetLon;
    private float  targetRadius;
    private String targetSsid;

    // ── Lifecycle ──────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannels();
        fusedClient     = LocationServices.getFusedLocationProviderClient(this);
        wifiManager     = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        wifiScanHandler = new Handler(Looper.getMainLooper());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            // Android restarted the service after it was killed — restore state
            resumeFromPrefs();
            return START_STICKY;
        }

        startForeground(TRACKING_NOTIF_ID,
                buildTrackingNotification("StopSnoozer is watching your route…"));

        final String action = intent.getAction();
        if (action == null) return START_STICKY;

        switch (action) {
            case ACTION_START_GEOFENCE:
                alarmFired     = false;
                targetStopId   = intent.getStringExtra("stopId");
                targetStopName = intent.getStringExtra("stopName");
                targetLat      = intent.getDoubleExtra("lat", 0);
                targetLon      = intent.getDoubleExtra("lon", 0);
                targetRadius   = intent.getFloatExtra("radiusMetres", 500f);
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

    // ── Above-ground GPS Geofencing ───────────────────────────────────────

    @SuppressWarnings("MissingPermission")
    private void startAboveGroundTracking() {
        LocationRequest request = new LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
                .setMinUpdateIntervalMillis(3_000L)
                .build();

        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult result) {
                if (alarmFired) return;
                Location loc = result.getLastLocation();
                if (loc == null) return;

                float[] dist = new float[1];
                Location.distanceBetween(
                        loc.getLatitude(), loc.getLongitude(),
                        targetLat, targetLon, dist);

                if (dist[0] <= targetRadius) triggerAlarm(dist[0]);
            }
        };

        fusedClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper());
        updateTrackingNotification("Tracking: " + targetStopName);
    }

    private void stopAboveGroundTracking() {
        if (fusedClient != null && locationCallback != null) {
            fusedClient.removeLocationUpdates(locationCallback);
            locationCallback = null;
        }
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
        if (wifiManager == null || targetSsid == null) return;
        List<ScanResult> results = wifiManager.getScanResults();
        for (ScanResult r : results) {
            if (targetSsid.equalsIgnoreCase(r.SSID) || targetSsid.equalsIgnoreCase(r.BSSID)) {
                triggerAlarm(0f);
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

    private void triggerAlarm(float distanceMetres) {
        if (alarmFired) return;
        alarmFired = true;
        stopSensors();

        SharedPreferences prefs   = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String            type    = prefs.getString(PREF_ALARM_TYPE, "both");
        boolean           screen  = !type.equals("notification");
        boolean           notif   = !type.equals("screen");

        // Persist alarm data so Flutter can recover it on cold start
        prefs.edit()
                .putString("pending_alarm_stop_id",   targetStopId   != null ? targetStopId   : "")
                .putString("pending_alarm_stop_name", targetStopName != null ? targetStopName : "")
                .putFloat("pending_alarm_distance",   distanceMetres)
                .apply();

        playAlarmSound(prefs);

        if (screen) {
            // Full-screen intent: wakes the screen and shows alarm UI over any app/lock screen
            showAlarmScreenOverlay(distanceMetres);
            // Also broadcast for a Flutter instance already running in memory
            Intent bc = new Intent(ACTION_ALARM_TRIGGER);
            bc.putExtra("stopId",         targetStopId);
            bc.putExtra("stopName",       targetStopName);
            bc.putExtra("distanceMetres", distanceMetres);
            sendBroadcast(bc);
        }

        if (notif) {
            // Banner notification (with full-screen intent when "both" mode)
            showAlarmNotification(distanceMetres, screen);
        }
    }

    private void playAlarmSound(SharedPreferences prefs) {
        String uriStr = prefs.getString(PREF_RINGTONE_URI, null);
        Uri uri = uriStr != null
                ? Uri.parse(uriStr)
                : RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (uri == null) uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (uri == null) return;

        alarmRingtone = RingtoneManager.getRingtone(this, uri);
        if (alarmRingtone == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            alarmRingtone.setLooping(true);
        }
        alarmRingtone.play();
    }

    private void showAlarmNotification(float distanceMetres, boolean fullStyle) {
        // "Stop Alarm" taps the service directly via PendingIntent
        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP_ALARM);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // Full-screen intent launches the Flutter alarm screen
        Intent fsIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent fsPi = null;
        if (fsIntent != null) {
            fsIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            fsIntent.putExtra("route",          "/alarm");
            fsIntent.putExtra("stopId",         targetStopId);
            fsIntent.putExtra("stopName",       targetStopName);
            fsIntent.putExtra("distanceMetres", distanceMetres);
            fsPi = PendingIntent.getActivity(this, 0, fsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }

        NotificationCompat.Builder b = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("StopSnoozer – Wake Up!")
                .setContentText("Approaching: " + targetStopName)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setOngoing(true)
                .setAutoCancel(false)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Alarm", stopPi);

        if (fsPi != null) {
            b.setContentIntent(fsPi);
            if (fullStyle) b.setFullScreenIntent(fsPi, true);
        }

        // Replace the tracking notification with the alarm notification
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.cancel(TRACKING_NOTIF_ID);
        startForeground(ALARM_NOTIF_ID, b.build());
    }

    /**
     * Shows a MAX-priority notification with setFullScreenIntent so Android wakes the screen
     * and displays the alarm UI on top of the lock screen and any foreground app.
     */
    private void showAlarmScreenOverlay(float distanceMetres) {
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launchIntent == null) return;
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        launchIntent.putExtra("alarmFromService", true);

        PendingIntent fsPi = PendingIntent.getActivity(this, 2, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP_ALARM);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("StopSnoozer – Wake Up!")
                .setContentText("Approaching: " + targetStopName)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(fsPi)
                .setFullScreenIntent(fsPi, true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Alarm", stopPi)
                .build();

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.cancel(TRACKING_NOTIF_ID);
        startForeground(ALARM_NOTIF_ID, n);
    }

    /**
     * Silences the alarm and re-arms location tracking after {@code snoozeMinutes}.
     * The alarm notification is replaced with a "snoozed" banner so the user can
     * see how long is left.
     */
    private void snoozeAlarm(int snoozeMinutes) {
        // Stop ringtone immediately
        if (alarmRingtone != null) {
            alarmRingtone.stop();
            alarmRingtone = null;
        }

        // Cancel alarm notification, replace with a snooze status notification
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.cancel(ALARM_NOTIF_ID);

        String stopLabel = targetStopName != null ? targetStopName : "your stop";
        Notification snoozeNotif = new NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_recent_history)
                .setContentTitle("StopSnoozer – Snoozed")
                .setContentText("Re-checking " + stopLabel + " in " + snoozeMinutes + " min")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .build();
        startForeground(TRACKING_NOTIF_ID, snoozeNotif);

        // Re-arm tracking after the snooze delay
        alarmFired = false;
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (ACTION_START_GEOFENCE.equals(
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                            .getString(PREF_TRACKING_ACTION, null))) {
                startAboveGroundTracking();
            } else {
                startSubterraneanTracking();
            }
        }, snoozeMinutes * 60_000L);
    }

    /** Stops sound, cancels notification, and kills the service. */
    private void dismissAlarm() {
        clearTrackingState();
        stopSensors();
        if (alarmRingtone != null) {
            alarmRingtone.stop();
            alarmRingtone = null;
        }
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) {
            mgr.cancel(TRACKING_NOTIF_ID);
            mgr.cancel(ALARM_NOTIF_ID);
        }
        stopForeground(true);
        stopSelf();
    }

    // ── Tracking state persistence (survive process kill) ──────────────────

    private void saveTrackingState(String action) {
        SharedPreferences.Editor ed = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        ed.putString(PREF_TRACKING_ACTION,    action);
        ed.putString(PREF_TRACKING_STOP_ID,   targetStopId != null ? targetStopId : "");
        ed.putString(PREF_TRACKING_STOP_NAME, targetStopName != null ? targetStopName : "");
        if (ACTION_START_GEOFENCE.equals(action)) {
            ed.putLong(PREF_TRACKING_LAT,    Double.doubleToRawLongBits(targetLat));
            ed.putLong(PREF_TRACKING_LON,    Double.doubleToRawLongBits(targetLon));
            ed.putFloat(PREF_TRACKING_RADIUS, targetRadius);
        } else if (ACTION_START_WIFI.equals(action)) {
            ed.putString(PREF_TRACKING_SSID, targetSsid != null ? targetSsid : "");
        }
        ed.apply();
    }

    private void clearTrackingState() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .remove(PREF_TRACKING_ACTION)
                .remove(PREF_TRACKING_STOP_ID)
                .remove(PREF_TRACKING_STOP_NAME)
                .remove(PREF_TRACKING_LAT)
                .remove(PREF_TRACKING_LON)
                .remove(PREF_TRACKING_RADIUS)
                .remove(PREF_TRACKING_SSID)
                .remove("pending_alarm_stop_id")
                .remove("pending_alarm_stop_name")
                .remove("pending_alarm_distance")
                .apply();
    }

    private void resumeFromPrefs() {
        SharedPreferences prefs  = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        String action            = prefs.getString(PREF_TRACKING_ACTION, null);
        if (action == null) { stopSelf(); return; }

        startForeground(TRACKING_NOTIF_ID,
                buildTrackingNotification("StopSnoozer is watching your route…"));

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

        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("StopSnoozer – Location is off")
                .setContentText("Turn on location to track " + stopLabel)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "Your alarm for '" + stopLabel + "' activated but "
                        + "location services are off. Turn them on so StopSnoozer "
                        + "can alert you when you arrive."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(settingsPi)
                .addAction(android.R.drawable.ic_menu_mylocation, "Turn On Location", settingsPi)
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

        Notification n = new NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("StopSnoozer – Wi-Fi is off")
                .setContentText("Turn on Wi-Fi to detect " + stopLabel)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(
                        "Your alarm for '" + stopLabel + "' activated but Wi-Fi is "
                        + "turned off. Turn it on so StopSnoozer can detect the "
                        + "underground station and alert you when you arrive."))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(settingsPi)
                .addAction(android.R.drawable.ic_menu_share, "Turn On Wi-Fi", settingsPi)
                .build();

        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(LOCATION_OFF_NOTIF_ID + 1, n);
    }

    private void stopSensors() {
        stopAboveGroundTracking();
        stopSubterraneanTracking();
    }

    // ── Notification helpers ───────────────────────────────────────────────

    private void createNotificationChannels() {
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr == null) return;

        NotificationChannel tracking = new NotificationChannel(
                TRACKING_CHANNEL_ID, "StopSnoozer Tracking",
                NotificationManager.IMPORTANCE_LOW);
        tracking.setDescription("Active journey tracking — do not dismiss");
        tracking.setSound(null, null);
        mgr.createNotificationChannel(tracking);

        // Alarm channel: no sound (we play it via Ringtone to support user-selected tunes)
        NotificationChannel alarm = new NotificationChannel(
                ALARM_CHANNEL_ID, "StopSnoozer Alarm",
                NotificationManager.IMPORTANCE_HIGH);
        alarm.setDescription("Wake-up alert when approaching your stop");
        alarm.enableVibration(true);
        alarm.setSound(null, null); // sound played manually via Ringtone
        mgr.createNotificationChannel(alarm);
    }

    private Notification buildTrackingNotification(String text) {
        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(
                this, 0, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, TRACKING_CHANNEL_ID)
                .setContentTitle("StopSnoozer")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi)
                .build();
    }

    private void updateTrackingNotification(String text) {
        Notification notif = buildTrackingNotification(text);
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(TRACKING_NOTIF_ID, notif);
    }
}
