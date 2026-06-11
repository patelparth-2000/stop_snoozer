package com.example.stop_snoozer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Re-schedules all commute alarms after device reboot.
 * Requires RECEIVE_BOOT_COMPLETED permission (already in manifest).
 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && !"android.intent.action.QUICKBOOT_POWERON".equals(intent.getAction())) {
            return;
        }
        AlarmScheduler.rescheduleAllFromPrefs(context);
    }
}
