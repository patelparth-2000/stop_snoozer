package com.stopsnoozer.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import androidx.core.content.ContextCompat;

/**
 * Receives AlarmManager.setAlarmClock() callbacks.
 * Starts SnoozeTrackingService and reschedules the next occurrence
 * for recurring (weekday-based) alarms.
 */
public class CommuteAlarmReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;

        // ── "Test your alarm" self-test ────────────────────────────────────
        // Reaching here proves the OS woke a backgrounded app on schedule —
        // exactly the step OEM battery killers break. Record the proof and fire
        // the alarm UI, but skip target tracking and rescheduling: there is no
        // real stop and no recurrence.
        if (intent.getBooleanExtra(AlarmSelfTest.EXTRA_SELF_TEST, false)) {
            AlarmSelfTest.recordFired(context);
            Intent test = new Intent(context, SnoozeTrackingService.class);
            test.setAction(SnoozeTrackingService.ACTION_SELF_TEST_FIRE);
            ContextCompat.startForegroundService(context, test);
            return;
        }

        String alarmId      = intent.getStringExtra("alarmId");
        String stopId       = intent.getStringExtra("stopId");
        String stopName     = intent.getStringExtra("stopName");
        double lat          = intent.getDoubleExtra("lat", 0.0);
        double lon          = intent.getDoubleExtra("lon", 0.0);
        String ssid         = intent.getStringExtra("ssid");
        float  radius       = intent.getFloatExtra("radius", 500f);
        String weekdays     = intent.getStringExtra("weekdays");
        String specificDate = intent.getStringExtra("specificDate");
        int    hour         = intent.getIntExtra("hour", 0);
        int    minute       = intent.getIntExtra("minute", 0);
        String tripGroupId  = intent.getStringExtra("tripGroupId");

        // ── Trip group: start the whole trip natively ──────────────────────
        // Read before rescheduling/removal below, which rewrite the record.
        // Without this only the first stop was armed, and the rest of the trip
        // existed only if the user happened to open the app afterwards.
        String routeJson = AlarmScheduler.routeJsonFor(context, alarmId);
        if (routeJson != null) {
            Intent routeIntent = new Intent(context, SnoozeTrackingService.class);
            routeIntent.setAction(SnoozeTrackingService.ACTION_START_ROUTE);
            routeIntent.putExtra(SnoozeTrackingService.EXTRA_ROUTE_JSON, routeJson);
            ContextCompat.startForegroundService(context, routeIntent);
            rescheduleOrRemove(context, alarmId, weekdays, specificDate);
            return;
        }

        // ── Launch the tracking service ────────────────────────────────────
        // ACTION_ADD_TARGET merges this stop with any already-active tracking targets
        // so manual saved-location tracking is not interrupted by a scheduled alarm.
        Intent svcIntent = new Intent(context, SnoozeTrackingService.class);
        svcIntent.setAction(SnoozeTrackingService.ACTION_ADD_TARGET);
        svcIntent.putExtra("stopId",       stopId);
        svcIntent.putExtra("stopName",     stopName);
        svcIntent.putExtra("lat",          lat);
        svcIntent.putExtra("lon",          lon);
        svcIntent.putExtra("radiusMetres", radius);
        if (ssid != null && !ssid.isEmpty()) svcIntent.putExtra("ssid", ssid);

        // ContextCompat.startForegroundService is allowed from setAlarmClock() callbacks
        ContextCompat.startForegroundService(context, svcIntent);

        // ── Persist trip group ID so Flutter can load all legs on resume ───
        if (tripGroupId != null && !tripGroupId.isEmpty()) {
            context.getSharedPreferences(SnoozeTrackingService.PREFS_NAME, Context.MODE_PRIVATE)
                   .edit()
                   .putString("pending_trip_group_id", tripGroupId)
                   .apply();
        }

        rescheduleOrRemove(context, alarmId, weekdays, specificDate);
    }

    /** Reschedules the next weekly occurrence, or forgets a one-off alarm. */
    private static void rescheduleOrRemove(Context context, String alarmId,
                                           String weekdays, String specificDate) {
        boolean isRecurring = specificDate == null || specificDate.isEmpty();
        if (isRecurring && alarmId != null && weekdays != null) {
            AlarmScheduler.rescheduleNext(context, alarmId);
        } else if (alarmId != null) {
            // One-off alarm — remove from prefs so it doesn't reschedule on reboot
            AlarmScheduler.remove(context, alarmId);
        }
    }
}
