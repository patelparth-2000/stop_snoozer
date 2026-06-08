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
import android.location.Location;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import java.util.List;

/**
 * Foreground service that handles both GPS geofencing (above ground) and
 * Wi-Fi SSID scanning (subterranean/underground) for StopSnoozer.
 *
 * Complies with Android 16KB page-size alignment requirements by using
 * only platform-standard JNI/SDK calls — no custom native libraries.
 */
public class SnoozeTrackingService extends Service {

    // ── Channel / Notification constants ──────────────────────────────────
    static final String ACTION_START_GEOFENCE  = "com.stopsnoozer.app.START_GEOFENCE";
    static final String ACTION_START_WIFI      = "com.stopsnoozer.app.START_WIFI";
    static final String ACTION_STOP            = "com.stopsnoozer.app.STOP_TRACKING";
    static final String ACTION_ALARM_TRIGGER   = "com.stopsnoozer.app.ALARM_TRIGGER";

    private static final String CHANNEL_ID   = "snooze_tracking";
    private static final int    NOTIF_ID     = 1001;
    private static final int    WIFI_SCAN_INTERVAL_MS = 8_000;

    // ── State ──────────────────────────────────────────────────────────────
    private FusedLocationProviderClient fusedClient;
    private LocationCallback            locationCallback;
    private WifiManager                 wifiManager;
    private BroadcastReceiver           wifiScanReceiver;
    private Handler                     wifiScanHandler;
    private Runnable                    wifiScanRunnable;

    // Target parameters set by incoming intent
    private String  targetStopId;
    private String  targetStopName;
    private double  targetLat;
    private double  targetLon;
    private float   targetRadius;
    private String  targetSsid;
    private boolean isWifiMode = false;

    // ── Lifecycle ──────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        fusedClient = LocationServices.getFusedLocationProviderClient(this);
        wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        wifiScanHandler = new Handler(Looper.getMainLooper());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_STICKY;

        startForeground(NOTIF_ID, buildNotification("StopSnoozer is watching your route…"));

        final String action = intent.getAction();
        if (action == null) return START_STICKY;

        targetStopId   = intent.getStringExtra("stopId");
        targetStopName = intent.getStringExtra("stopName");

        switch (action) {
            case ACTION_START_GEOFENCE:
                targetLat    = intent.getDoubleExtra("lat", 0);
                targetLon    = intent.getDoubleExtra("lon", 0);
                targetRadius = intent.getFloatExtra("radiusMetres", 500f);
                isWifiMode   = false;
                startAboveGroundTracking();
                break;

            case ACTION_START_WIFI:
                targetSsid = intent.getStringExtra("targetSsid");
                isWifiMode = true;
                startSubterraneanTracking();
                break;

            case ACTION_STOP:
                stopTracking();
                stopSelf();
                break;
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopTracking();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

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
                Location loc = result.getLastLocation();
                if (loc == null) return;

                float[] distResult = new float[1];
                Location.distanceBetween(
                        loc.getLatitude(), loc.getLongitude(),
                        targetLat, targetLon,
                        distResult);

                if (distResult[0] <= targetRadius) {
                    triggerAlarm(distResult[0]);
                }
            }
        };

        fusedClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper());
        updateNotification("Tracking: " + targetStopName);
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
                boolean success = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false);
                if (success) evaluateWifiResults();
            }
        };
        IntentFilter filter = new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
        registerReceiver(wifiScanReceiver, filter);

        // Periodic scan loop
        wifiScanRunnable = new Runnable() {
            @Override
            public void run() {
                if (wifiManager != null) wifiManager.startScan();
                wifiScanHandler.postDelayed(this, WIFI_SCAN_INTERVAL_MS);
            }
        };
        wifiScanHandler.post(wifiScanRunnable);
        updateNotification("Underground sensing: " + targetStopName);
    }

    private void evaluateWifiResults() {
        if (wifiManager == null || targetSsid == null) return;
        List<ScanResult> results = wifiManager.getScanResults();
        for (ScanResult result : results) {
            if (targetSsid.equalsIgnoreCase(result.SSID) ||
                    targetSsid.equalsIgnoreCase(result.BSSID)) {
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
        stopTracking();

        // Broadcast to Flutter EventChannel listener via MainActivity
        Intent alarmBroadcast = new Intent(ACTION_ALARM_TRIGGER);
        alarmBroadcast.putExtra("stopId",          targetStopId);
        alarmBroadcast.putExtra("stopName",        targetStopName);
        alarmBroadcast.putExtra("distanceMetres",  distanceMetres);
        sendBroadcast(alarmBroadcast);

        // Also launch the app directly to the alarm screen if backgrounded
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launchIntent != null) {
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            launchIntent.putExtra("route",          "/alarm");
            launchIntent.putExtra("stopId",         targetStopId);
            launchIntent.putExtra("stopName",       targetStopName);
            launchIntent.putExtra("distanceMetres", distanceMetres);
            startActivity(launchIntent);
        }
        stopSelf();
    }

    private void stopTracking() {
        stopAboveGroundTracking();
        stopSubterraneanTracking();
    }

    // ── Notification helpers ───────────────────────────────────────────────

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "StopSnoozer Tracking",
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Active journey tracking — do not dismiss");
        channel.setSound(null, null);
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.createNotificationChannel(channel);
    }

    private Notification buildNotification(String text) {
        Intent stopIntent = new Intent(this, SnoozeTrackingService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(
                this, 0, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("StopSnoozer")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setOngoing(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPi)
                .build();
    }

    private void updateNotification(String text) {
        Notification notif = buildNotification(text);
        NotificationManager mgr = getSystemService(NotificationManager.class);
        if (mgr != null) mgr.notify(NOTIF_ID, notif);
    }
}
