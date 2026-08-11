package com.stopsnoozer.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import androidx.core.content.ContextCompat;

/**
 * Runs after device reboot:
 *  1. Re-schedules all saved commute alarms via AlarmManager.
 *  2. Restarts SnoozeTrackingService if it was actively tracking when the
 *     device was powered off (resumeFromPrefs() will restore the session).
 */
public class BootReceiver extends BroadcastReceiver {

    private static final String TAG = "BootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && !"android.intent.action.QUICKBOOT_POWERON".equals(intent.getAction())) {
            return;
        }

        // Re-arm all scheduled commute alarms
        AlarmScheduler.rescheduleAllFromPrefs(context);

        // If the service was tracking when the phone turned off, restart it.
        //
        // This start is best-effort and must stay that way. Android 15 began
        // refusing foreground-service starts from BOOT_COMPLETED for several
        // service types, and the restricted set has grown with each release; a
        // refusal arrives as a ForegroundServiceStartNotAllowedException, which
        // from a boot receiver would surface as a crash every time the phone
        // powers on. The user's actual alarms do not depend on this — they were
        // re-armed above via setAlarmClock(), which is Doze-exempt and survives
        // independently — so swallowing the refusal degrades to "tracking
        // resumes when the user next opens the app" rather than a boot loop.
        SharedPreferences prefs = context.getSharedPreferences(
                SnoozeTrackingService.PREFS_NAME, Context.MODE_PRIVATE);
        if (prefs.getString("tracking_action", null) != null) {
            try {
                ContextCompat.startForegroundService(context,
                        new Intent(context, SnoozeTrackingService.class));
            } catch (Exception e) {
                Log.w(TAG, "Boot-time tracking restart refused by OS: " + e);
            }
        }
    }
}
