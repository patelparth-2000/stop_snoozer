package com.stopsnoozer.app;

import android.app.AlarmManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.PowerManager;

import org.json.JSONObject;

/**
 * "Test your alarm" — end-to-end verification that this device will actually
 * fire an alarm while the app is backgrounded.
 *
 * <p>Motivation: several OEM skins silently kill foreground services (see
 * {@link OemBatteryHelper}), and exact-alarm permission can be revoked on
 * API 31–32. Both failures are invisible until the user misses their stop. This
 * lets them find out on the sofa instead of on the train.
 *
 * <p>Design decision — the test deliberately goes through the <em>real</em>
 * scheduling path ({@link AlarmScheduler}-style AlarmManager wake-up →
 * {@link CommuteAlarmReceiver} → {@link SnoozeTrackingService}) rather than
 * calling the service directly. A direct call would prove only that the code
 * runs in-process, which is never the thing that breaks. What breaks is the OS
 * waking a backgrounded app, so that is what we exercise.
 */
final class AlarmSelfTest {

    private AlarmSelfTest() {}

    static final String PREF_SELFTEST_SCHEDULED_AT = "selftest_scheduled_at";
    static final String PREF_SELFTEST_FIRED_AT     = "selftest_fired_at";
    static final String EXTRA_SELF_TEST            = "isSelfTest";

    /** Request code kept distinct from real alarms (which hash their alarmId). */
    private static final int SELF_TEST_REQUEST_CODE = 987_654;

    /**
     * Snapshot of everything that determines whether alarms will work here.
     * Returned to Dart as a JSON string so the UI can explain specifics rather
     * than showing a bare pass/fail.
     */
    static String diagnostics(Context ctx) {
        JSONObject o = new JSONObject();
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            PowerManager pm = (PowerManager) ctx.getSystemService(Context.POWER_SERVICE);
            NotificationManager nm = ctx.getSystemService(NotificationManager.class);

            boolean canExact = am != null
                    && (Build.VERSION.SDK_INT < Build.VERSION_CODES.S
                        || am.canScheduleExactAlarms());
            boolean batteryExempt = pm != null
                    && pm.isIgnoringBatteryOptimizations(ctx.getPackageName());
            boolean notifsOn = nm == null || nm.areNotificationsEnabled();
            boolean fullScreen = Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                    || (nm != null && nm.canUseFullScreenIntent());

            o.put("canScheduleExactAlarms", canExact);
            o.put("batteryOptimizationExempt", batteryExempt);
            o.put("notificationsEnabled", notifsOn);
            o.put("canUseFullScreenIntent", fullScreen);
            o.put("manufacturer", Build.MANUFACTURER == null ? "" : Build.MANUFACTURER);
            o.put("androidSdk", Build.VERSION.SDK_INT);

            String oem = OemBatteryHelper.oemName();
            o.put("oemName", oem == null ? JSONObject.NULL : oem);
            o.put("oemSettingsAvailable", OemBatteryHelper.hasOemSettings(ctx));

            SharedPreferences p = prefs(ctx);
            o.put("lastTestScheduledAt", p.getLong(PREF_SELFTEST_SCHEDULED_AT, 0L));
            o.put("lastTestFiredAt",     p.getLong(PREF_SELFTEST_FIRED_AT, 0L));
        } catch (Exception ignored) {}
        return o.toString();
    }

    /**
     * Schedules a self-test alarm {@code delaySeconds} from now.
     *
     * <p>Returns true if it was scheduled exactly. False means it fell back to
     * an inexact alarm — it should still fire, but possibly late, and the UI
     * must say so rather than implying the test is a clean pass.
     */
    static boolean schedule(Context ctx, int delaySeconds) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return false;

        long fireAt = System.currentTimeMillis() + delaySeconds * 1000L;

        prefs(ctx).edit()
                .putLong(PREF_SELFTEST_SCHEDULED_AT, System.currentTimeMillis())
                .remove(PREF_SELFTEST_FIRED_AT)
                .apply();

        Intent i = new Intent(ctx, CommuteAlarmReceiver.class);
        i.putExtra(EXTRA_SELF_TEST, true);
        i.putExtra("alarmId",  "__selftest__");
        i.putExtra("stopName", "Alarm Test");
        i.putExtra("stopId",   "__selftest__");
        // lat/lon 0 and radius 0 mean the receiver must not start GPS tracking.
        i.putExtra("lat", 0.0);
        i.putExtra("lon", 0.0);
        i.putExtra("radius", 0f);
        i.putExtra("weekdays", "[]");

        android.app.PendingIntent pi = android.app.PendingIntent.getBroadcast(
                ctx, SELF_TEST_REQUEST_CODE, i,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
                        | android.app.PendingIntent.FLAG_IMMUTABLE);

        boolean canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S
                || am.canScheduleExactAlarms();
        if (canExact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi);
                return true;
            } catch (SecurityException ignored) {
                // Revoked between check and call — fall through.
            }
        }
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi);
        return false;
    }

    /** Records that the self-test alarm actually fired. Called by the receiver. */
    static void recordFired(Context ctx) {
        prefs(ctx).edit()
                .putLong(PREF_SELFTEST_FIRED_AT, System.currentTimeMillis())
                .apply();
    }

    static void cancel(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(ctx, CommuteAlarmReceiver.class);
        android.app.PendingIntent pi = android.app.PendingIntent.getBroadcast(
                ctx, SELF_TEST_REQUEST_CODE, i,
                android.app.PendingIntent.FLAG_NO_CREATE
                        | android.app.PendingIntent.FLAG_IMMUTABLE);
        if (pi != null && am != null) am.cancel(pi);
        prefs(ctx).edit()
                .remove(PREF_SELFTEST_SCHEDULED_AT)
                .remove(PREF_SELFTEST_FIRED_AT)
                .apply();
    }

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(SnoozeTrackingService.PREFS_NAME, Context.MODE_PRIVATE);
    }
}
