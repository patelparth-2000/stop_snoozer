package com.stopsnoozer.app;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Calendar;

/**
 * Schedules and cancels commute alarms via AlarmManager.setAlarmClock().
 * setAlarmClock fires even in deep Doze and shows a clock icon in the status bar —
 * the best API for user-visible, time-critical alarms.
 */
public class AlarmScheduler {

    static final String PREFS_NAME = "commute_alarm_schedules";
    static final String KEY_ALARMS = "scheduled_alarms";

    // ── Public API ─────────────────────────────────────────────────────────────

    /** Persist alarm data, calculate next fire time, and register with AlarmManager. */
    static void scheduleAndSave(Context ctx,
            String alarmId, int hour, int minute,
            String stopId, String stopName,
            double lat, double lon,
            String ssid, float radius,
            String weekdaysJson, String specificDate,
            String tripGroupId) {

        save(ctx, alarmId, hour, minute, stopId, stopName,
                lat, lon, ssid, radius, weekdaysJson, specificDate, tripGroupId);

        long fireAt = nextFireTime(hour, minute, weekdaysJson, specificDate);
        if (fireAt < 0) return;

        PendingIntent trigger = buildPendingIntent(ctx, alarmId,
                stopId, stopName, lat, lon, ssid, radius,
                weekdaysJson, specificDate, hour, minute, tripGroupId);

        Intent launchIntent = ctx.getPackageManager()
                .getLaunchIntentForPackage(ctx.getPackageName());
        PendingIntent showPi = PendingIntent.getActivity(ctx, 0,
                launchIntent != null ? launchIntent : new Intent(),
                PendingIntent.FLAG_IMMUTABLE);

        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        scheduleExactOrFallback(am, fireAt, showPi, trigger);
    }

    /**
     * Registers the alarm, preferring setAlarmClock() for deep-Doze accuracy.
     *
     * On API 31+ setAlarmClock() requires exact-alarm permission. We declare
     * USE_EXACT_ALARM (auto-granted on API 33+) and SCHEDULE_EXACT_ALARM
     * (maxSdkVersion 32) — but on API 31–32 the user can revoke the latter in
     * Settings, and setAlarmClock() then throws SecurityException. Because
     * rescheduleAllFromPrefs() runs on boot, an unguarded throw there would
     * abort the loop and silently kill every stored alarm.
     *
     * Fallback is setAndAllowWhileIdle(): still fires in Doze, but inexact.
     */
    private static void scheduleExactOrFallback(AlarmManager am, long fireAt,
            PendingIntent showPi, PendingIntent trigger) {
        boolean canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S
                || am.canScheduleExactAlarms();
        if (canExact) {
            try {
                am.setAlarmClock(new AlarmManager.AlarmClockInfo(fireAt, showPi), trigger);
                return;
            } catch (SecurityException ignored) {
                // Revoked between the check and the call — fall through to inexact.
            }
        }
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, trigger);
    }

    /** Cancel the pending AlarmManager intent and remove persisted data. */
    static void cancelAndRemove(Context ctx, String alarmId) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        Intent intent = new Intent(ctx, CommuteAlarmReceiver.class);
        intent.putExtra("alarmId", alarmId);
        PendingIntent pi = PendingIntent.getBroadcast(ctx,
                Math.abs(alarmId.hashCode()), intent,
                PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        if (pi != null && am != null) am.cancel(pi);
        remove(ctx, alarmId);
    }

    /** Re-schedule a recurring alarm for its next occurrence (called after it fires). */
    static void rescheduleNext(Context ctx, String alarmId) {
        SharedPreferences prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String json = prefs.getString(KEY_ALARMS, "{}");
        try {
            JSONObject all = new JSONObject(json);
            if (!all.has(alarmId)) return;
            JSONObject a = all.getJSONObject(alarmId);
            scheduleAndSave(ctx,
                    alarmId,
                    a.getInt("hour"),        a.getInt("minute"),
                    a.getString("stopId"),   a.getString("stopName"),
                    a.getDouble("lat"),      a.getDouble("lon"),
                    a.optString("ssid", null),
                    (float) a.optDouble("radius", 500.0),
                    a.getString("weekdays"),
                    a.optString("specificDate", null),
                    a.optString("tripGroupId", null));
        } catch (JSONException ignored) {}
    }

    /** Re-schedules every stored alarm — called on device reboot. */
    static void rescheduleAllFromPrefs(Context ctx) {
        SharedPreferences prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String json = prefs.getString(KEY_ALARMS, "{}");

        JSONObject all;
        JSONArray  keys;
        try {
            all  = new JSONObject(json);
            keys = all.names();
        } catch (JSONException e) {
            return;
        }
        if (keys == null) return;

        for (int i = 0; i < keys.length(); i++) {
            // Per-entry catch: one malformed record must not abort the loop,
            // or a single bad alarm would silently cancel every later one on boot.
            try {
                String id = keys.getString(i);
                JSONObject a = all.getJSONObject(id);
                scheduleAndSave(ctx,
                        id,
                        a.getInt("hour"),        a.getInt("minute"),
                        a.getString("stopId"),   a.getString("stopName"),
                        a.getDouble("lat"),      a.getDouble("lon"),
                        a.optString("ssid", null),
                        (float) a.optDouble("radius", 500.0),
                        a.getString("weekdays"),
                        a.optString("specificDate", null),
                        a.optString("tripGroupId", null));
            } catch (JSONException ignored) {}
        }
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    private static void save(Context ctx,
            String alarmId, int hour, int minute,
            String stopId, String stopName,
            double lat, double lon,
            String ssid, float radius,
            String weekdaysJson, String specificDate,
            String tripGroupId) {
        SharedPreferences prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String existing = prefs.getString(KEY_ALARMS, "{}");
        try {
            JSONObject all = new JSONObject(existing);
            JSONObject a   = new JSONObject();
            a.put("hour",      hour);
            a.put("minute",    minute);
            a.put("stopId",    stopId);
            a.put("stopName",  stopName);
            a.put("lat",       lat);
            a.put("lon",       lon);
            if (ssid != null && !ssid.isEmpty()) a.put("ssid", ssid);
            a.put("radius",    radius);
            a.put("weekdays",  weekdaysJson);
            if (specificDate  != null && !specificDate.isEmpty())
                a.put("specificDate", specificDate);
            if (tripGroupId != null && !tripGroupId.isEmpty())
                a.put("tripGroupId", tripGroupId);
            all.put(alarmId, a);
            prefs.edit().putString(KEY_ALARMS, all.toString()).apply();
        } catch (JSONException ignored) {}
    }

    static void remove(Context ctx, String alarmId) {
        SharedPreferences prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String existing = prefs.getString(KEY_ALARMS, "{}");
        try {
            JSONObject all = new JSONObject(existing);
            all.remove(alarmId);
            prefs.edit().putString(KEY_ALARMS, all.toString()).apply();
        } catch (JSONException ignored) {}
    }

    private static PendingIntent buildPendingIntent(Context ctx, String alarmId,
            String stopId, String stopName, double lat, double lon,
            String ssid, float radius, String weekdaysJson, String specificDate,
            int hour, int minute, String tripGroupId) {
        Intent i = new Intent(ctx, CommuteAlarmReceiver.class);
        i.putExtra("alarmId",      alarmId);
        i.putExtra("stopId",       stopId);
        i.putExtra("stopName",     stopName);
        i.putExtra("lat",          lat);
        i.putExtra("lon",          lon);
        i.putExtra("ssid",         ssid);
        i.putExtra("radius",       radius);
        i.putExtra("weekdays",     weekdaysJson);
        i.putExtra("specificDate", specificDate);
        i.putExtra("hour",         hour);
        i.putExtra("minute",       minute);
        if (tripGroupId != null && !tripGroupId.isEmpty())
            i.putExtra("tripGroupId", tripGroupId);
        return PendingIntent.getBroadcast(ctx,
                Math.abs(alarmId.hashCode()), i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /**
     * Calculates the next UTC millis at which this alarm should fire.
     * Returns -1 if no future time exists (e.g. one-off date already passed).
     *
     * Weekday convention: 1=Mon … 7=Sun  (matches Flutter model).
     * Java Calendar.DAY_OF_WEEK: SUNDAY=1, MONDAY=2 … SATURDAY=7.
     * Conversion: ourDow = calDow > 1 ? calDow - 1 : 7
     */
    static long nextFireTime(int hour, int minute, String weekdaysJson, String specificDate) {
        Calendar now    = Calendar.getInstance();
        Calendar target = (Calendar) now.clone();
        target.set(Calendar.HOUR_OF_DAY, hour);
        target.set(Calendar.MINUTE,      minute);
        target.set(Calendar.SECOND,      0);
        target.set(Calendar.MILLISECOND, 0);

        // ── One-off date ───────────────────────────────────────────────────────
        if (specificDate != null && !specificDate.isEmpty()) {
            try {
                String[] parts = specificDate.split("-");
                target.set(Calendar.YEAR,         Integer.parseInt(parts[0]));
                target.set(Calendar.MONTH,        Integer.parseInt(parts[1]) - 1);
                target.set(Calendar.DAY_OF_MONTH, Integer.parseInt(parts[2]));
                return target.getTimeInMillis() > now.getTimeInMillis()
                        ? target.getTimeInMillis() : -1;
            } catch (Exception ignored) {
                return -1;
            }
        }

        // ── Weekly recurring ───────────────────────────────────────────────────
        try {
            JSONArray days = new JSONArray(weekdaysJson);
            if (days.length() == 0) return -1;

            // Search today through today+6 (guarantees finding the next occurrence)
            for (int offset = 0; offset <= 7; offset++) {
                Calendar candidate = (Calendar) target.clone();
                if (offset > 0) candidate.add(Calendar.DAY_OF_MONTH, offset);

                int calDow = candidate.get(Calendar.DAY_OF_WEEK);
                int ourDow = calDow > 1 ? calDow - 1 : 7; // 1=Mon … 7=Sun

                for (int d = 0; d < days.length(); d++) {
                    if (days.getInt(d) == ourDow
                            && candidate.getTimeInMillis() > now.getTimeInMillis()) {
                        return candidate.getTimeInMillis();
                    }
                }
            }
        } catch (JSONException ignored) {}
        return -1;
    }
}
