package com.stopsnoozer.app;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * A pre-selected underground journey, handed to the native engine as a
 * self-contained plan.
 *
 * <p>Design note: the engine deliberately does <em>not</em> query SQLite. Dart
 * owns the topology database and resolves the route once, at trip setup, while
 * the user is online and attentive. That is also where route pre-selection
 * happens — so by the time tracking starts there is exactly one ordered station
 * sequence and no ambiguity to resolve underground.
 *
 * <p>Everything the fusion test needs travels with the plan: per-station depth
 * (barometric expectation) and per-leg run time (timing gate).
 */
final class JourneyPlan {

    static final class Station {
        final String stopId;
        final String stopName;
        /**
         * Platform depth below the local street in metres; NaN when unknown.
         *
         * <p>For display and diagnostics. Do NOT match the barometer against
         * this — see {@link #platformLevelAslMetres}.
         */
        final double depthMetres;
        /**
         * Platform altitude in metres above Ordnance Datum; NaN when unknown.
         *
         * <p>This is what the barometer is matched against. A barometer reads a
         * <em>change</em> in altitude, so the expected reading between two
         * stations is the difference of their platform altitudes. Depth below
         * street cannot express that, because streets are not level with one
         * another: Tooting Broadway's is 16 m above sea level and Hampstead's
         * is 108 m. Matching descent-since-boarding against depth assumes every
         * street is at the same height, and is wrong by up to ~76 m across the
         * network — several times the match tolerance.
         */
        final double platformLevelAslMetres;
        /**
         * True when the altitude is the mean of the station's other platforms,
         * or ground level rather than a measured platform. Still usable, but
         * less precise, so the engine widens its matching tolerance.
         */
        final boolean depthIsFallback;
        /**
         * Unimpeded seconds from the previous station; <=0 when unknown.
         * This is the train moving with no holds — a physical floor, which is
         * what the timing gate's lower bound must be built from.
         */
        final int runTimeSecondsFromPrev;
        /**
         * AM-peak scheduled seconds for the same leg; <=0 when unknown.
         * Widens the gate's upper bound only, so congestion never raises the
         * floor and starts rejecting legitimate fast off-peak runs.
         */
        final int peakRunTimeSecondsFromPrev;
        /** True when this station should raise an alarm. */
        final boolean isAlarmTarget;

        Station(String stopId, String stopName, double depthMetres,
                double platformLevelAslMetres, boolean depthIsFallback,
                int runTimeSecondsFromPrev, int peakRunTimeSecondsFromPrev,
                boolean isAlarmTarget) {
            this.stopId   = stopId   != null ? stopId   : "";
            this.stopName = stopName != null ? stopName : "";
            this.depthMetres = depthMetres;
            this.platformLevelAslMetres = platformLevelAslMetres;
            this.depthIsFallback = depthIsFallback;
            this.runTimeSecondsFromPrev = runTimeSecondsFromPrev;
            this.peakRunTimeSecondsFromPrev = peakRunTimeSecondsFromPrev;
            this.isAlarmTarget = isAlarmTarget;
        }

        boolean hasDepth()   { return !Double.isNaN(depthMetres); }
        boolean hasRunTime() { return runTimeSecondsFromPrev > 0; }

        /** True when this station can take part in the barometric test. */
        boolean hasPlatformLevel() {
            return !Double.isNaN(platformLevelAslMetres);
        }

        /** Upper-bound reference: peak time when known, else the unimpeded one. */
        int ceilingRunTimeSeconds() {
            return peakRunTimeSecondsFromPrev > runTimeSecondsFromPrev
                    ? peakRunTimeSecondsFromPrev
                    : runTimeSecondsFromPrev;
        }
    }

    final String lineId;
    final String direction;
    final List<Station> stations;
    /** Index the journey starts from (the boarding station). */
    final int startIndex;

    private JourneyPlan(String lineId, String direction,
                        List<Station> stations, int startIndex) {
        this.lineId     = lineId;
        this.direction  = direction;
        this.stations   = stations;
        this.startIndex = startIndex;
    }

    int size() { return stations.size(); }

    Station at(int i) {
        if (i < 0 || i >= stations.size()) return null;
        return stations.get(i);
    }

    /** Index of the next alarm target at or after {@code from}, or -1. */
    int nextTargetIndex(int from) {
        for (int i = Math.max(0, from); i < stations.size(); i++) {
            if (stations.get(i).isAlarmTarget) return i;
        }
        return -1;
    }

    String toJsonString() {
        try {
            JSONObject o = new JSONObject();
            o.put("lineId", lineId);
            o.put("direction", direction);
            o.put("startIndex", startIndex);
            JSONArray arr = new JSONArray();
            for (Station s : stations) {
                JSONObject j = new JSONObject();
                j.put("stopId", s.stopId);
                j.put("stopName", s.stopName);
                if (s.hasDepth()) j.put("depthMetres", s.depthMetres);
                if (s.hasPlatformLevel()) {
                    j.put("platformLevelAslMetres", s.platformLevelAslMetres);
                }
                if (s.depthIsFallback) j.put("depthIsFallback", true);
                j.put("runTimeSeconds", s.runTimeSecondsFromPrev);
                if (s.peakRunTimeSecondsFromPrev > 0) {
                    j.put("peakRunTimeSeconds", s.peakRunTimeSecondsFromPrev);
                }
                j.put("isTarget", s.isAlarmTarget);
                arr.put(j);
            }
            o.put("stations", arr);
            return o.toString();
        } catch (JSONException e) {
            return "{}";
        }
    }

    /** Returns null when the JSON is unusable, so callers can fall back to GPS. */
    static JourneyPlan fromJson(String json) {
        if (json == null || json.isEmpty()) return null;
        try {
            JSONObject o = new JSONObject(json);
            JSONArray arr = o.optJSONArray("stations");
            if (arr == null || arr.length() < 2) return null;

            List<Station> list = new ArrayList<>(arr.length());
            for (int i = 0; i < arr.length(); i++) {
                JSONObject j = arr.getJSONObject(i);
                list.add(new Station(
                        j.optString("stopId"),
                        j.optString("stopName"),
                        j.has("depthMetres") ? j.optDouble("depthMetres", Double.NaN)
                                             : Double.NaN,
                        j.has("platformLevelAslMetres")
                                ? j.optDouble("platformLevelAslMetres", Double.NaN)
                                : Double.NaN,
                        j.optBoolean("depthIsFallback", false),
                        j.optInt("runTimeSeconds", 0),
                        j.optInt("peakRunTimeSeconds", 0),
                        j.optBoolean("isTarget", false)));
            }
            int start = Math.max(0, Math.min(o.optInt("startIndex", 0), list.size() - 1));
            return new JourneyPlan(
                    o.optString("lineId"), o.optString("direction"), list, start);
        } catch (JSONException e) {
            return null;
        }
    }
}
