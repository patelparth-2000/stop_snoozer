package com.stopsnoozer.app;

import static com.stopsnoozer.app.ServiceHarness.A;
import static com.stopsnoozer.app.ServiceHarness.B;
import static com.stopsnoozer.app.ServiceHarness.FAR;
import static com.stopsnoozer.app.ServiceHarness.stop;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.util.List;

/**
 * End-to-end alarm behaviour of the tracking service, driven by fake GPS fixes.
 * Each test states what a user should experience; it does not pin internals.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class AlarmFlowTest {

    private ServiceHarness h;

    @Before public void setUp() { h = new ServiceHarness(); }

    // ── Single stop ──────────────────────────────────────────────────────

    @Test public void singleStop_alarmsOnArrival_andStopEndsTracking() {
        h.send(h.geofence("Alpha", A));
        h.at(FAR);
        assertTrue(h.newAlarms().isEmpty());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertTrue("service should end after the only stop", h.stopped());
    }

    @Test public void singleStop_snooze_reAlarmsAfterDelay() {
        h.send(h.geofence("Alpha", A));
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(snooze(2));
        h.advanceMinutes(3);
        h.at(A);
        assertEquals("snoozed alarm must ring again", List.of("Alpha"), h.newAlarms());
    }

    @Test public void singleStop_survivesProcessKill() {
        h.send(h.geofence("Alpha", A));
        h.killProcess();
        h.restartSticky();
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    // ── Several saved stops tracked together ─────────────────────────────

    @Test public void savedStops_dismissingOne_keepsTheOthers() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertFalse(h.stopped());
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void savedStops_stopTrackingButton_actuallyStops() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.send(SnoozeTrackingService.ACTION_STOP);   // notification "Stop Tracking"
        assertTrue("'Stop Tracking' must stop tracking", h.stopped());
        h.at(A);
        assertTrue("no alarm after the user stopped tracking", h.newAlarms().isEmpty());
    }

    @Test public void savedStops_turningOffTheLastOne_stopsItsAlarm() {
        h.send(h.updateTargets(stop("Alpha", A)));
        // What DashboardCubit.toggleSavedLocation sends when the last one goes off.
        h.send(h.updateTargets());
        h.at(A);
        assertTrue("a switched-off stop must not alarm", h.newAlarms().isEmpty());
        assertTrue("nothing left to track", h.stopped());
    }

    @Test public void savedStops_snooze_reAlarmsTheSnoozedStop() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(snooze(2));
        h.advanceMinutes(3);
        h.at(A);
        assertEquals("snoozed alarm must ring again", List.of("Alpha"), h.newAlarms());
    }

    @Test public void savedStops_honourTheUsersWakeRadius() throws Exception {
        org.json.JSONObject wide = stop("Alpha", A);
        wide.put("radiusMetres", 1000.0);
        h.send(h.updateTargets(wide));
        h.at(new double[]{A[0] + 0.0063, A[1]});   // ~700 m from Alpha
        assertEquals("700 m is inside a 1 km wake radius", List.of("Alpha"), h.newAlarms());
    }

    @Test public void savedStops_surviveProcessKill() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.killProcess();
        h.restartSticky();
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void savedStops_killAfterOneWasDismissed_otherStillAlarms() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.at(A);
        h.newAlarms();
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.killProcess();
        h.restartSticky();
        h.at(A);
        assertTrue("a dismissed stop must not ring twice", h.newAlarms().isEmpty());
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void savedStops_killWhileRinging_ringsAgain() {
        // The ringtone dies with the process, so an unacknowledged alarm must
        // not be lost: being at that stop again re-rings it.
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.at(A);
        h.newAlarms();
        h.killProcess();
        h.restartSticky();
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    @Test public void dismissWithNoAlarmRinging_changesNothing() {
        h.send(h.updateTargets(stop("Alpha", A), stop("Bravo", B)));
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertFalse(h.stopped());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    // ── Mixing a trip with saved stops / scheduled alarms ────────────────

    @Test public void tripLeg_alarmsEvenWhenSavedStopsAreActive() {
        h.send(h.updateTargets(stop("Bravo", B)));
        h.send(h.geofence("Alpha", A));    // trip leg armed from Trip Config
        h.at(A);
        assertEquals("the trip's stop must alarm", List.of("Alpha"), h.newAlarms());
    }

    @Test public void scheduledCommuteAlarm_mergesWithSavedStops() {
        h.send(h.updateTargets(stop("Bravo", B)));
        h.send(h.addTarget("Alpha", A));
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    private android.content.Intent snooze(int minutes) {
        android.content.Intent i = h.intent(SnoozeTrackingService.ACTION_SNOOZE);
        i.putExtra(SnoozeTrackingService.EXTRA_SNOOZE_MINUTES, minutes);
        return i;
    }
}
