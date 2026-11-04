package com.stopsnoozer.app;

import static com.stopsnoozer.app.ServiceHarness.A;
import static com.stopsnoozer.app.ServiceHarness.B;
import static com.stopsnoozer.app.ServiceHarness.stop;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.content.Intent;

import org.json.JSONArray;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.util.List;

/** A scheduled commute alarm attached to a multi-stop trip group. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class CommuteRouteTest {

    private ServiceHarness h;
    private String routeJson;

    @Before public void setUp() {
        h = new ServiceHarness();
        routeJson = new JSONArray().put(stop("Alpha", A)).put(stop("Bravo", B)).toString();
    }

    private void schedule(String weekdays, String specificDate) {
        AlarmScheduler.scheduleAndSave(h.app, "alarm1", 8, 0,
                "id_Alpha", "Alpha", A[0], A[1], null, 500f,
                weekdays, specificDate, "group1", routeJson);
    }

    /** Fires the receiver exactly as AlarmManager would, then hands the
     *  service-start it produced to the service. */
    private Intent fire() {
        Intent alarm = new Intent(h.app, CommuteAlarmReceiver.class);
        alarm.putExtra("alarmId", "alarm1");
        alarm.putExtra("stopId", "id_Alpha");
        alarm.putExtra("stopName", "Alpha");
        alarm.putExtra("lat", A[0]);
        alarm.putExtra("lon", A[1]);
        alarm.putExtra("weekdays", "[1,2,3,4,5,6,7]");
        alarm.putExtra("tripGroupId", "group1");
        new CommuteAlarmReceiver().onReceive(h.app, alarm);
        Intent started = shadowOf(h.app).getNextStartedService();
        assertNotNull("the alarm must start the tracking service", started);
        return started;
    }

    @Test public void scheduledTrip_startsTheWholeRoute_andWalksIt() {
        schedule("[1,2,3,4,5,6,7]", null);
        Intent started = fire();
        assertEquals(SnoozeTrackingService.ACTION_START_ROUTE, started.getAction());
        h.send(started);
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        h.at(B);
        assertEquals("stop 2 armed without the app", List.of("Bravo"), h.newAlarms());
    }

    @Test public void scheduledTrip_doesNotLeaveAPendingGroupThatWouldRestartIt() {
        schedule("[1,2,3,4,5,6,7]", null);
        fire();
        assertNull(h.prefs().getString("pending_trip_group_id", null));
    }

    @Test public void recurringTrip_keepsItsStopsForNextWeek() {
        schedule("[1,2,3,4,5,6,7]", null);
        fire();
        assertEquals(routeJson, AlarmScheduler.routeJsonFor(h.app, "alarm1"));
    }

    @Test public void rebootReschedule_keepsTheTripStops() {
        schedule("[1,2,3,4,5,6,7]", null);
        AlarmScheduler.rescheduleAllFromPrefs(h.app);
        assertEquals(routeJson, AlarmScheduler.routeJsonFor(h.app, "alarm1"));
    }

    @Test public void singleStopCommuteAlarm_stillUsesAddTarget() {
        AlarmScheduler.scheduleAndSave(h.app, "alarm1", 8, 0,
                "id_Alpha", "Alpha", A[0], A[1], null, 500f,
                "[1,2,3,4,5,6,7]", null, null, null);
        Intent started = fire();
        assertEquals(SnoozeTrackingService.ACTION_ADD_TARGET, started.getAction());
        h.send(started);
        h.at(A);
        assertEquals(List.of("Alpha"), h.newAlarms());
        h.send(SnoozeTrackingService.ACTION_STOP_ALARM);
        assertTrue(h.stopped());
    }
}
