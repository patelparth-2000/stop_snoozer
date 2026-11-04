package com.stopsnoozer.app;

import static com.stopsnoozer.app.ServiceHarness.A;
import static com.stopsnoozer.app.ServiceHarness.B;
import static com.stopsnoozer.app.ServiceHarness.C;
import static com.stopsnoozer.app.ServiceHarness.D;
import static com.stopsnoozer.app.ServiceHarness.stop;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;

import org.json.JSONArray;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowAlarmManager;

import java.util.Calendar;
import java.util.List;

/**
 * What happens around the alarm: the app swiped away, the phone rebooted, the
 * alarm self-test, the early "get ready" nudge, and scheduled alarm times.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class LifecycleTest {

    private ServiceHarness h;

    @Before public void setUp() { h = new ServiceHarness(); }

    private void startAbc() {
        Intent i = h.intent(SnoozeTrackingService.ACTION_START_ROUTE);
        i.putExtra(SnoozeTrackingService.EXTRA_ROUTE_JSON, new JSONArray()
                .put(stop("Alpha", A)).put(stop("Bravo", B)).put(stop("Charlie", C)).toString());
        h.send(i);
    }

    private ShadowAlarmManager alarmManager() {
        return shadowOf((AlarmManager) h.app.getSystemService(Context.ALARM_SERVICE));
    }

    // ── App swiped away from Recents ─────────────────────────────────────

    @Test public void swipedAway_serviceIsRestarted_andTheTripCarriesOn() {
        startAbc();
        h.at(A);
        h.newAlarms();
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);

        h.service.onTaskRemoved(new Intent());
        ShadowAlarmManager.ScheduledAlarm restart = alarmManager().getNextScheduledAlarm();
        assertNotNull("swiping the app away must schedule a restart", restart);
        Intent restartIntent = shadowOf(restart.operation).getSavedIntent();

        h.killProcess();
        h.restart(restartIntent);
        h.at(A);
        assertTrue(h.newAlarms().isEmpty());
        h.at(B);
        assertEquals("trip continues at stop 2", List.of("Bravo"), h.newAlarms());
    }

    @Test public void swipedAway_withNothingTracked_doesNotRestart() {
        h.send(h.geofence("Alpha", A));
        h.at(A);
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.service.onTaskRemoved(new Intent());
        assertNull(alarmManager().getNextScheduledAlarm());
    }

    // ── Phone rebooted ───────────────────────────────────────────────────

    @Test public void reboot_restartsTheTrip_andReArmsScheduledAlarms() {
        AlarmScheduler.scheduleAndSave(h.app, "alarm1", 8, 0, "id_D", "Delta",
                D[0], D[1], null, 500f, "[1,2,3,4,5,6,7]", null, null, null);
        startAbc();
        h.at(A);
        h.newAlarms();
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.killProcess();
        // AlarmManager is cleared by a reboot.
        for (ShadowAlarmManager.ScheduledAlarm a : alarmManager().getScheduledAlarms()) {
            ((AlarmManager) h.app.getSystemService(Context.ALARM_SERVICE)).cancel(a.operation);
        }

        new BootReceiver().onReceive(h.app, new Intent(Intent.ACTION_BOOT_COMPLETED));

        assertFalse("commute alarm re-armed", alarmManager().getScheduledAlarms().isEmpty());
        Intent started = shadowOf(h.app).getNextStartedService();
        assertNotNull("tracking restarted after boot", started);
        h.restart(started);
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void reboot_withNothingTracked_startsNothing() {
        new BootReceiver().onReceive(h.app, new Intent(Intent.ACTION_BOOT_COMPLETED));
        assertNull(shadowOf(h.app).getNextStartedService());
    }

    // ── "Test your alarm" self-test ──────────────────────────────────────

    @Test public void selfTest_rings() {
        h.send(SnoozeTrackingService.ACTION_SELF_TEST_FIRE);
        assertEquals(List.of("Alarm Test — it works"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertTrue(h.stopped());
    }

    @Test public void selfTest_duringATrip_doesNotEndTheTrip() {
        startAbc();
        h.send(SnoozeTrackingService.ACTION_SELF_TEST_FIRE);
        assertEquals(List.of("Alarm Test — it works"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertFalse("the trip must survive the self-test", h.stopped());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.at(B);
        assertEquals("self-test dismiss must not have advanced the trip",
                List.of("Bravo"), h.newAlarms());
    }

    // ── Early "get ready" nudge ──────────────────────────────────────────

    @Test public void earlyNudge_comesBeforeTheAlarm_onceEach() {
        startAbc();
        NotificationManager nm = h.app.getSystemService(NotificationManager.class);
        h.at(new double[]{A[0] - 0.0054, A[1]});   // ~600 m out (radius 300)
        assertNotNull("nudge at 2.5x the wake radius", shadowOf(nm).getNotification(1004));
        assertTrue("no alarm yet", h.newAlarms().isEmpty());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        nm.cancelAll();
        h.at(new double[]{B[0] - 0.0054, B[1]});
        assertNotNull("next stop gets its own nudge", shadowOf(nm).getNotification(1004));
    }

    // ── Scheduled alarm times ────────────────────────────────────────────

    @Test public void nextFireTime_weekly_picksTheNextMatchingDay() {
        long t = AlarmScheduler.nextFireTime(7, 30, "[1,2,3,4,5,6,7]", null);
        long now = System.currentTimeMillis();
        assertTrue(t > now);
        assertTrue("within a day when every day is selected", t - now <= 24L * 3600_000L);
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(t);
        assertEquals(7, c.get(Calendar.HOUR_OF_DAY));
        assertEquals(30, c.get(Calendar.MINUTE));
    }

    @Test public void nextFireTime_singleWeekday_landsOnThatDay() {
        long t = AlarmScheduler.nextFireTime(9, 0, "[3]", null); // Wednesday
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(t);
        assertEquals(Calendar.WEDNESDAY, c.get(Calendar.DAY_OF_WEEK));
        assertTrue(t - System.currentTimeMillis() <= 7L * 24 * 3600_000L);
    }

    @Test public void cancelledCommuteAlarm_isGone_andNotReArmedOnReboot() {
        AlarmScheduler.scheduleAndSave(h.app, "alarm1", 8, 0, "id_D", "Delta",
                D[0], D[1], null, 500f, "[1,2,3,4,5,6,7]", null, null, null);
        assertEquals(1, alarmManager().getScheduledAlarms().size());
        AlarmScheduler.cancelAndRemove(h.app, "alarm1");
        assertTrue(alarmManager().getScheduledAlarms().isEmpty());
        new BootReceiver().onReceive(h.app, new Intent(Intent.ACTION_BOOT_COMPLETED));
        assertTrue("a deleted alarm must not come back after reboot",
                alarmManager().getScheduledAlarms().isEmpty());
    }

    @Test public void nextFireTime_oneOffInThePast_isNotScheduled() {
        assertEquals(-1L, AlarmScheduler.nextFireTime(9, 0, "[]", "2020-01-01"));
    }

    @Test public void nextFireTime_noDays_isNotScheduled() {
        assertEquals(-1L, AlarmScheduler.nextFireTime(9, 0, "[]", null));
    }
}
