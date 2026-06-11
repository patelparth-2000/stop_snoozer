package com.example.stop_snoozer;

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

        // ── Launch the tracking service ────────────────────────────────────
        Intent svcIntent = new Intent(context, SnoozeTrackingService.class);

        boolean useWifi = ssid != null && !ssid.isEmpty();
        if (useWifi) {
            svcIntent.setAction(SnoozeTrackingService.ACTION_START_WIFI);
            svcIntent.putExtra("stopId",     stopId);
            svcIntent.putExtra("stopName",   stopName);
            svcIntent.putExtra("targetSsid", ssid);
        } else {
            svcIntent.setAction(SnoozeTrackingService.ACTION_START_GEOFENCE);
            svcIntent.putExtra("stopId",       stopId);
            svcIntent.putExtra("stopName",     stopName);
            svcIntent.putExtra("lat",          lat);
            svcIntent.putExtra("lon",          lon);
            svcIntent.putExtra("radiusMetres", radius);
        }

        // ContextCompat.startForegroundService is allowed from setAlarmClock() callbacks
        ContextCompat.startForegroundService(context, svcIntent);

        // ── Reschedule the next weekly occurrence ──────────────────────────
        boolean isRecurring = specificDate == null || specificDate.isEmpty();
        if (isRecurring && alarmId != null && weekdays != null) {
            AlarmScheduler.rescheduleNext(context, alarmId);
        } else if (alarmId != null) {
            // One-off alarm — remove from prefs so it doesn't reschedule on reboot
            AlarmScheduler.remove(context, alarmId);
        }
    }
}
