package com.stopsnoozer.app;

import static org.robolectric.Shadows.shadowOf;

import android.Manifest;
import android.app.Application;
import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.location.Location;
import android.location.LocationManager;
import android.os.Looper;


import org.json.JSONArray;
import org.json.JSONObject;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.android.controller.ServiceController;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Drives the real {@link SnoozeTrackingService} the way the OS and the app do:
 * intents in, fake GPS fixes in, alarm broadcasts and notifications out.
 *
 * <p>{@link #killProcess()} simulates Android killing the app: the service
 * object is thrown away without {@code onDestroy}, SharedPreferences survive,
 * and {@link #restartSticky()} delivers the null intent START_STICKY uses.
 */
final class ServiceHarness {

    // Three stops on a line, ~2 km apart, plus a point far from all of them.
    static final double[] A = {51.5000, -0.1000};
    static final double[] B = {51.5180, -0.1000};
    static final double[] C = {51.5360, -0.1000};
    static final double[] D = {51.5540, -0.1000};
    static final double[] FAR = {51.4000, -0.3000};

    final Application app = RuntimeEnvironment.getApplication();
    ServiceController<SnoozeTrackingService> controller;
    SnoozeTrackingService service;
    private int startId = 1;
    private int alarmsSeen = 0;

    ServiceHarness() {
        shadowOf(app).grantPermissions(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                Manifest.permission.POST_NOTIFICATIONS);
        LocationManager lm = (LocationManager) app.getSystemService(Context.LOCATION_SERVICE);
        shadowOf(lm).setLocationEnabled(true);
        newProcess();
    }

    private void newProcess() {
        controller = Robolectric.buildService(SnoozeTrackingService.class).create();
        service = controller.get();
    }

    // ── Inputs ───────────────────────────────────────────────────────────

    void send(Intent intent) {
        controller.withIntent(intent).startCommand(0, startId++);
        idle();
    }

    void send(String action) { send(intent(action)); }

    Intent intent(String action) {
        Intent i = new Intent(app, SnoozeTrackingService.class);
        i.setAction(action);
        return i;
    }

    /** A fake GPS fix, exactly as the fused location callback would deliver it. */
    void at(double[] p) {
        if (service == null) return;
        Location loc = new Location("gps");
        loc.setLatitude(p[0]);
        loc.setLongitude(p[1]);
        loc.setAccuracy(10f);
        service.checkLocationAndTrigger(loc);
        idle();
    }

    void advanceMinutes(int minutes) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(minutes));
    }

    void advanceSeconds(int seconds) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(seconds));
    }

    void idle() { shadowOf(Looper.getMainLooper()).idle(); }

    /** Android kills the process. Prefs survive; in-memory state does not. */
    void killProcess() {
        service = null;
        controller = null;
    }

    /** A fresh process receiving {@code intent} (e.g. the swipe-away restart). */
    void restart(Intent intent) {
        newProcess();
        controller.withIntent(intent).startCommand(0, startId++);
        idle();
    }

    /** START_STICKY / onTaskRemoved restart: a null intent into a fresh object. */
    void restartSticky() {
        newProcess();
        controller.withIntent(null).startCommand(0, startId++);
        idle();
    }

    // ── Outputs ──────────────────────────────────────────────────────────

    /** Stop names of every alarm broadcast so far. */
    List<String> alarms() {
        List<String> out = new ArrayList<>();
        for (Intent i : shadowOf(app).getBroadcastIntents()) {
            if (SnoozeTrackingService.ACTION_ALARM_TRIGGER.equals(i.getAction())) {
                out.add(i.getStringExtra("stopName"));
            }
        }
        return out;
    }

    /** Alarms fired since the last call. */
    List<String> newAlarms() {
        List<String> all = alarms();
        List<String> fresh = new ArrayList<>(all.subList(alarmsSeen, all.size()));
        alarmsSeen = all.size();
        return fresh;
    }

    boolean stopped() {
        return service == null || shadowOf(service).isStoppedBySelf();
    }

    SharedPreferences prefs() {
        return app.getSharedPreferences(SnoozeTrackingService.PREFS_NAME, Context.MODE_PRIVATE);
    }

    boolean alarmNotificationShowing() {
        NotificationManager nm = app.getSystemService(NotificationManager.class);
        return shadowOf(nm).getNotification(1002) != null;
    }

    String trackingNotificationText() {
        NotificationManager nm = app.getSystemService(NotificationManager.class);
        Notification n = shadowOf(nm).getNotification(1001);
        if (n == null) return null;
        CharSequence t = n.extras.getCharSequence(Notification.EXTRA_TEXT);
        return t == null ? null : t.toString();
    }

    // ── Builders for the app's own intents ───────────────────────────────

    static JSONObject stop(String name, double[] p) {
        try {
            JSONObject o = new JSONObject();
            o.put("stopId", "id_" + name);
            o.put("stopName", name);
            o.put("lat", p[0]);
            o.put("lon", p[1]);
            o.put("radiusMetres", 300.0);
            return o;
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    /** What MainActivity sends for dashboard saved-location toggles. */
    Intent updateTargets(JSONObject... stops) {
        JSONArray arr = new JSONArray();
        for (JSONObject s : stops) arr.put(s);
        Intent i = intent(SnoozeTrackingService.ACTION_UPDATE_TARGETS);
        i.putExtra("targetsJson", arr.toString());
        return i;
    }

    /** What MainActivity sends for a single-stop geofence (today's trip leg). */
    Intent geofence(String name, double[] p) {
        Intent i = intent(SnoozeTrackingService.ACTION_START_GEOFENCE);
        i.putExtra("stopId", "id_" + name);
        i.putExtra("stopName", name);
        i.putExtra("lat", p[0]);
        i.putExtra("lon", p[1]);
        i.putExtra("radiusMetres", 300f);
        return i;
    }

    /** What CommuteAlarmReceiver sends when a scheduled commute alarm fires. */
    Intent addTarget(String name, double[] p) {
        Intent i = intent(SnoozeTrackingService.ACTION_ADD_TARGET);
        i.putExtra("stopId", "id_" + name);
        i.putExtra("stopName", name);
        i.putExtra("lat", p[0]);
        i.putExtra("lon", p[1]);
        i.putExtra("radiusMetres", 300f);
        return i;
    }
}
