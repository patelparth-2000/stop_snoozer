package com.stopsnoozer.app;

import static com.stopsnoozer.app.ServiceHarness.A;
import static com.stopsnoozer.app.ServiceHarness.B;
import static com.stopsnoozer.app.ServiceHarness.C;
import static com.stopsnoozer.app.ServiceHarness.D;
import static com.stopsnoozer.app.ServiceHarness.stop;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Intent;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.util.List;

/**
 * A trip with several stops in order ("route"): each stop alarms in turn, and
 * dismissing one alarm moves on to the next stop instead of ending the trip.
 * The route lives in the native service, so none of this needs the app open.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class RouteAlarmTest {

    private ServiceHarness h;

    @Before public void setUp() { h = new ServiceHarness(); }

    private Intent route(JSONObject... stops) {
        JSONArray arr = new JSONArray();
        for (JSONObject s : stops) arr.put(s);
        Intent i = h.intent(SnoozeTrackingService.ACTION_START_ROUTE);
        i.putExtra(SnoozeTrackingService.EXTRA_ROUTE_JSON, arr.toString());
        return i;
    }

    private void startAbc() {
        h.send(route(stop("Alpha", A), stop("Bravo", B), stop("Charlie", C)));
    }

    private void dismiss() { h.send(SnoozeTrackingService.ACTION_STOP_ALARM); }

    @Test public void dismissingEachStop_movesOnToTheNext_untilTheEnd() {
        startAbc();
        h.at(B);
        assertTrue("only the current stop is armed", h.newAlarms().isEmpty());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        dismiss();
        assertFalse("dismissing stop 1 must not end the trip", h.stopped());
        h.at(A);
        assertTrue("a finished stop does not ring again", h.newAlarms().isEmpty());
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
        dismiss();
        h.at(C);
        assertEquals(List.of("Charlie"), h.newAlarms());
        dismiss();
        assertTrue("trip ends after the last stop", h.stopped());
    }

    @Test public void dismissedFromNotificationAndScreen_doesNotSkipAStop() {
        startAbc();
        h.at(A);
        h.newAlarms();
        dismiss();   // notification "Stop Alarm"
        dismiss();   // in-app slide-to-dismiss, same alarm
        h.at(C);
        assertTrue("stop 3 must not be armed yet", h.newAlarms().isEmpty());
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void snooze_ringsTheSameStopAgain_thenContinues() {
        startAbc();
        h.at(A);
        h.newAlarms();
        Intent s = h.intent(SnoozeTrackingService.ACTION_SNOOZE);
        s.putExtra(SnoozeTrackingService.EXTRA_SNOOZE_MINUTES, 2);
        h.send(s);
        h.at(A);
        assertTrue("silent during the snooze", h.newAlarms().isEmpty());
        h.advanceMinutes(3);
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        dismiss();
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void appKilledMidTrip_resumesAtTheCurrentStop() {
        startAbc();
        h.at(A);
        h.newAlarms();
        dismiss();
        h.killProcess();
        h.restartSticky();
        h.at(A);
        assertTrue(h.newAlarms().isEmpty());
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
        dismiss();
        h.at(C);
        assertEquals(List.of("Charlie"), h.newAlarms());
    }

    @Test public void appKilledWhileRinging_dismissAfterRestart_continuesTrip() {
        startAbc();
        h.at(A);
        h.newAlarms();
        h.killProcess();           // alarm sound dies with the process
        h.restartSticky();
        h.at(A);
        assertEquals("an unacknowledged alarm rings again", List.of("Alpha"), h.newAlarms());
        dismiss();
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void stopTrackingButton_endsTheWholeTrip() {
        startAbc();
        h.send(SnoozeTrackingService.ACTION_STOP);
        assertTrue(h.stopped());
        h.at(A);
        assertTrue(h.newAlarms().isEmpty());
    }

    @Test public void tripAndSavedStops_bothAlarm() {
        h.send(h.updateTargets(stop("Delta", D)));
        h.send(route(stop("Alpha", A), stop("Bravo", B)));
        h.at(A);
        assertEquals("the trip's stop must alarm", List.of("Alpha"), h.newAlarms());
        dismiss();
        h.at(D);
        assertEquals("saved stop still tracked", List.of("Delta"), h.newAlarms());
        dismiss();
        h.at(B);
        assertEquals(List.of("Bravo"), h.newAlarms());
    }

    @Test public void savedStopsResentOnAppOpen_doNotCancelTheTrip() {
        startAbc();
        // DashboardCubit re-sends active saved stops on every cold start.
        h.send(h.updateTargets(stop("Delta", D)));
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    @Test public void turningOffAllSavedStops_keepsTheTrip() {
        h.send(h.updateTargets(stop("Delta", D)));
        startAbc();
        h.send(h.updateTargets());
        assertFalse(h.stopped());
        h.at(D);
        assertTrue(h.newAlarms().isEmpty());
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    @Test public void endingTheTrip_keepsSavedStops() {
        h.send(h.updateTargets(stop("Delta", D)));
        startAbc();
        h.send(SnoozeTrackingService.ACTION_STOP_ROUTE);
        h.at(A);
        assertTrue("trip ended", h.newAlarms().isEmpty());
        h.at(D);
        assertEquals(List.of("Delta"), h.newAlarms());
    }

    @Test public void endingTheTrip_withNothingElse_stopsTheService() {
        startAbc();
        h.send(SnoozeTrackingService.ACTION_STOP_ROUTE);
        assertTrue(h.stopped());
    }

    @Test public void scheduledAlarmForTheSameStop_ringsOnlyOnce() {
        // A commute alarm fired (ADD_TARGET for stop 1) and the app then loaded
        // the same trip group as a route.
        h.send(h.addTarget("Alpha", A));
        startAbc();
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.advanceSeconds(10);
        h.at(A);
        assertTrue("no duplicate alarm for the same stop", h.newAlarms().isEmpty());
    }

    @Test public void locationOff_warnsTheUser_andKeepsTheTripForWhenItComesBack() {
        android.location.LocationManager lm = (android.location.LocationManager)
                h.app.getSystemService(android.content.Context.LOCATION_SERVICE);
        org.robolectric.Shadows.shadowOf(lm).setLocationEnabled(false);
        startAbc();
        android.app.NotificationManager nm =
                h.app.getSystemService(android.app.NotificationManager.class);
        assertTrue("user must be told location is off",
                org.robolectric.Shadows.shadowOf(nm).getNotification(1003) != null);
        assertFalse("trip is kept, not thrown away", h.stopped());
        org.robolectric.Shadows.shadowOf(lm).setLocationEnabled(true);
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
    }

    @Test public void newTripReplacesTheOldOne() {
        startAbc();
        h.send(route(stop("Delta", D)));
        h.at(A);
        assertTrue(h.newAlarms().isEmpty());
        h.at(D);
        assertEquals(List.of("Delta"), h.newAlarms());
    }
}
