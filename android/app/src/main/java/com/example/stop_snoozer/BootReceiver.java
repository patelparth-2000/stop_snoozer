package com.example.stop_snoozer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import androidx.core.content.ContextCompat;

/**
 * Runs after device reboot:
 *  1. Re-schedules all saved commute alarms via AlarmManager.
 *  2. Restarts SnoozeTrackingService if it was actively tracking when the
 *     device was powered off (resumeFromPrefs() will restore the session).
 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && !"android.intent.action.QUICKBOOT_POWERON".equals(intent.getAction())) {
            return;
        }

        // Re-arm all scheduled commute alarms
        AlarmScheduler.rescheduleAllFromPrefs(context);

        // If the service was tracking when the phone turned off, restart it
        SharedPreferences prefs = context.getSharedPreferences(
                SnoozeTrackingService.PREFS_NAME, Context.MODE_PRIVATE);
        if (prefs.getString("tracking_action", null) != null) {
            ContextCompat.startForegroundService(context,
                    new Intent(context, SnoozeTrackingService.class));
        }
    }
}
