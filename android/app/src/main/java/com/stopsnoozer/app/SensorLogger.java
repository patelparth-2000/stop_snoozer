package com.stopsnoozer.app;

import android.content.Context;
import android.os.Build;
import android.os.SystemClock;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * CSV logger for the underground field test.
 *
 * <p><b>Why this is a first-class feature, not debug code.</b> Every threshold in
 * {@link UndergroundEngine} is currently a literature-derived guess. Platform
 * depths, real inter-station times, this device's accelerometer noise floor, and
 * what {@code getAllCellInfo()} actually returns in a No Service tunnel cannot be
 * looked up — they have to be measured on the actual route. This produces the
 * measurements.
 *
 * <p><b>Protocol.</b> Ride the target route end to end with logging on, tapping
 * the ground-truth marker at each real arrival. Do it on <em>both</em> branches
 * of any split (Kennington), and keep at least one run that includes a
 * mid-tunnel hold — that is the negative case the fusion test exists to reject,
 * and it is the hardest thing to tune without real data.
 *
 * <p>Writes to the app's external files dir so logs can be pulled over MTP or
 * {@code adb pull} without root:
 * {@code /Android/data/com.stopsnoozer.app/files/sensor_logs/}
 *
 * <p>All writes are best-effort and swallow IO errors: a failed log line must
 * never disturb alarm tracking, which is the feature the user actually depends on.
 */
final class SensorLogger {

    private static final String DIR_NAME = "sensor_logs";

    private final File file;
    private FileWriter writer;
    private final long startedElapsed = SystemClock.elapsedRealtime();

    /** Buffered line count; we flush periodically rather than per line. */
    private int sinceFlush;
    private static final int FLUSH_EVERY = 25;

    private SensorLogger(File file) {
        this.file = file;
    }

    /**
     * Creates a logger writing a new timestamped CSV, or null when logging is
     * off or the file cannot be opened.
     */
    static SensorLogger createIfEnabled(Context ctx, boolean enabled, String label) {
        if (!enabled) return null;
        try {
            File dir = new File(ctx.getExternalFilesDir(null), DIR_NAME);
            if (!dir.exists() && !dir.mkdirs()) return null;
            String stamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
                    .format(new Date());
            String safe = label == null ? "run"
                    : label.replaceAll("[^A-Za-z0-9_-]", "_");
            SensorLogger l = new SensorLogger(new File(dir, stamp + "_" + safe + ".csv"));
            return l.open() ? l : null;
        } catch (Exception e) {
            return null;
        }
    }

    private boolean open() {
        try {
            writer = new FileWriter(file, true);
            writer.write("# StopSnoozer sensor log\n");
            writer.write("# device=" + Build.MANUFACTURER + " " + Build.MODEL
                    + " sdk=" + Build.VERSION.SDK_INT + "\n");
            writer.write("# started=" + new Date() + "\n");
            // Wide schema: one row type per event, unused columns left blank.
            writer.write("elapsed_ms,event,a,b,c,d,e,f,g\n");
            writer.flush();
            return true;
        } catch (IOException e) {
            writer = null;
            return false;
        }
    }

    String path() { return file.getAbsolutePath(); }

    // ── Event writers ──────────────────────────────────────────────────────

    /** Raw barometer sample plus derived depth. */
    void logPressure(double hpa, double depthMetres) {
        write("pressure", fmt(hpa), fmt(depthMetres), "", "", "", "");
    }

    /** One accelerometer analysis window: mean magnitude and std deviation. */
    void logAccelWindow(double mean, double stdDev) {
        write("accel", fmt(mean), fmt(stdDev), "", "", "", "");
    }

    /**
     * A detected full stop and how each fusion condition judged it. This is the
     * single most valuable row type: it shows exactly which condition rejected a
     * tunnel hold, or wrongly rejected a real platform.
     */
    /**
     * Logs both sides of the barometric comparison, not just the reading.
     *
     * <p>Column f is the altitude change measured since the last confirmed
     * platform; column g is the change the two platforms' known levels predict.
     * Recording only the measurement makes a {@code depthOk=false} row
     * uninterpretable — it cannot distinguish a bad sensor reading from a bad
     * prior, which are the two things calibration has to tell apart.
     */
    void logStopCandidate(String nextStopId, long elapsedMs, boolean timingOk,
                          boolean depthOk, boolean settled,
                          double measuredDescentM, double expectedDescentM) {
        write("stop_candidate", nextStopId, Long.toString(elapsedMs),
                Boolean.toString(timingOk), Boolean.toString(depthOk),
                Boolean.toString(settled), fmt(measuredDescentM),
                fmt(expectedDescentM));
    }

    /** An opportunistic fix that reset the tracker to certainty. */
    void logExternalFix(int index, String source) {
        write("external_fix", Integer.toString(index), source, "", "", "", "");
    }

    /** Wi-Fi scan result summary — count of visible APs, and whether throttled. */
    void logWifiScan(int apCount, boolean accepted) {
        write("wifi_scan", Integer.toString(apCount),
                Boolean.toString(accepted), "", "", "", "");
    }

    /**
     * A cell observation with its age.
     *
     * <p>Age is the point of this row. In No Service, {@code getAllCellInfo()}
     * can return cells cached from the previous station; logging the age proves
     * whether this device does that, which decides how much Cell-ID can ever be
     * trusted here.
     */
    void logCellInfo(int cellId, int ageMs, boolean registered, boolean accepted) {
        write("cell", Integer.toString(cellId), Integer.toString(ageMs),
                Boolean.toString(registered), Boolean.toString(accepted), "", "");
    }

    /** Telephony service state changes — marks true network entry/exit. */
    void logServiceState(String state) {
        write("service_state", state, "", "", "", "", "");
    }

    /** User-tapped ground truth: "I am arriving at X right now". */
    void logGroundTruth(String stopName) {
        write("ground_truth", stopName, "", "", "", "", "");
    }

    /** Free-form marker, e.g. "tunnel hold started". */
    void logNote(String note) {
        write("note", note, "", "", "", "", "");
    }

    // ── Plumbing ───────────────────────────────────────────────────────────

    private static String fmt(double d) {
        return String.format(Locale.US, "%.4f", d);
    }

    private void write(String event, String a, String b, String c,
                       String d, String e, String f) {
        write(event, a, b, c, d, e, f, "");
    }

    private synchronized void write(String event, String a, String b, String c,
                                    String d, String e, String f, String g) {
        if (writer == null) return;
        try {
            long t = SystemClock.elapsedRealtime() - startedElapsed;
            writer.write(t + "," + event + "," + csv(a) + "," + csv(b) + ","
                    + csv(c) + "," + csv(d) + "," + csv(e) + "," + csv(f) + ","
                    + csv(g) + "\n");
            if (++sinceFlush >= FLUSH_EVERY) {
                writer.flush();
                sinceFlush = 0;
            }
        } catch (IOException ignored) {
            // Never let logging break tracking.
        }
    }

    /** Minimal CSV escaping — stop names contain commas and parentheses. */
    private static String csv(String s) {
        if (s == null || s.isEmpty()) return "";
        if (s.indexOf(',') < 0 && s.indexOf('"') < 0) return s;
        return '"' + s.replace("\"", "\"\"") + '"';
    }

    synchronized void close() {
        if (writer == null) return;
        try {
            writer.flush();
            writer.close();
        } catch (IOException ignored) {
        } finally {
            writer = null;
        }
    }
}
