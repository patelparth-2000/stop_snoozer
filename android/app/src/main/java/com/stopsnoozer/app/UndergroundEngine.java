package com.stopsnoozer.app;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.SystemClock;

/**
 * Underground position tracking by sensor fusion.
 *
 * <p><b>Why this exists.</b> GPS is unavailable in deep tube and the phone often
 * shows literal No Service, so there is nothing to trilaterate. What remains is
 * the barometer (station depth), the accelerometer (stop/start), and knowledge of
 * how long each leg should take.
 *
 * <p><b>The one rule that matters.</b> Trains hold in tunnels. An accelerometer
 * full stop is therefore <em>not</em> evidence of arrival on its own — that
 * single mistake would over-count stops and wake users in the wrong place. An
 * arrival is declared only when all three agree:
 *
 * <pre>
 *   arrival ⟺ accelerometer full stop
 *           ∧ barometric settle near the expected station depth
 *           ∧ elapsed time inside the expected run-time window
 * </pre>
 *
 * A mid-tunnel hold satisfies the first and fails the third, which is exactly
 * what the timing gate is for.
 *
 * <p><b>Belief, not a counter.</b> The engine tracks a confidence value, not a
 * bare stop count. Detections that pass only partially still advance position
 * but cost confidence; when confidence falls below
 * {@link #CONFIDENCE_FAILSAFE_THRESHOLD} on approach to the target, the alarm
 * fires one station early with an honest message. Silently guessing is the one
 * outcome worse than waking someone slightly too soon.
 *
 * <p><b>Thresholds are provisional.</b> Every constant marked CALIBRATE below is
 * a literature-derived starting value, not a measured one. They must be tuned
 * against real logs from the instrumented field test before this engine is
 * trusted in production. {@link SensorLogger} exists to produce those logs.
 */
final class UndergroundEngine implements SensorEventListener {

    // ── Physical constants ─────────────────────────────────────────────────

    /** Barometric lapse near sea level: ~0.12 hPa per metre of altitude. */
    private static final double HPA_PER_METRE = 0.12;

    // ── Tunables (CALIBRATE against field logs) ────────────────────────────

    /**
     * Accelerometer magnitude standard deviation, m/s², below which the carriage
     * is considered stationary. CALIBRATE: depends on where the phone rides
     * (hand, pocket, bag) and on rolling stock.
     */
    private static final double STOPPED_STD_DEV = 0.35;

    /** Consecutive stationary windows required before declaring a full stop. */
    private static final int STOPPED_WINDOWS_REQUIRED = 3;

    /**
     * Accelerometer sampling rate.
     *
     * <p>20 Hz, not SENSOR_DELAY_GAME's ~50 Hz. A train stopping or starting is a
     * sub-1 Hz event, so 50 Hz was ~2.5× more data than the detector can use,
     * paid for in battery on every second of every commute. Continuous inertial
     * sampling is known to roughly quadruple idle drain.
     */
    private static final int SAMPLE_PERIOD_US = 50_000;   // 20 Hz
    /** One analysis window ≈ 1 s at {@link #SAMPLE_PERIOD_US}. */
    private static final int ACCEL_WINDOW = 20;

    /**
     * Batch latency while coasting between intermediate stations.
     *
     * <p>Batching is the single biggest power win available here: events
     * accumulate in the sensor hub's FIFO and are delivered together, letting the
     * application processor stay suspended instead of waking per sample.
     *
     * <p>5 s is a deliberate compromise. Longer batches save more power but delay
     * detection by up to the latency, and this is an alarm — arriving 20 s late at
     * the platform could mean the doors have closed. 5 s sits comfortably inside
     * platform dwell time while still eliminating the large majority of wakeups.
     */
    private static final int BATCH_LATENCY_COASTING_US = 5_000_000;

    /**
     * No batching once the next station is the alarm target: at that point
     * latency matters more than power, and it is a single leg's worth of drain.
     */
    private static final int BATCH_LATENCY_APPROACHING_US = 0;

    /**
     * Tolerated depth error when matching a barometric reading to a station's
     * known depth, in metres. Generous because absolute pressure drifts with
     * weather; only *relative* change within a journey is reliable.
     * CALIBRATE.
     */
    private static final double DEPTH_MATCH_TOLERANCE_M = 12.0;

    /**
     * Multiplier applied when the depth is a cross-platform mean rather than
     * this line's own figure. Interchanges can differ by ~9 m between lines
     * (Bank: 20.5 m Central, 29.6 m Northern), so the fallback needs headroom.
     */
    private static final double DEPTH_FALLBACK_TOLERANCE_FACTOR = 1.6;

    /** Pressure change below this (hPa) counts as settled, i.e. not moving vertically. */
    private static final double PRESSURE_SETTLE_HPA = 0.08;

    /**
     * Run-time window, applied <b>asymmetrically</b> and for good reason.
     *
     * <p>The priors are TfL's scheduled figures: {@code runTimeSecondsFromPrev}
     * is the <i>unimpeded</i> time (train moving, no holds) and
     * {@code peakRunTimeSecondsFromPrev} the AM-peak time. Unimpeded is close to
     * a physical floor — a train rarely beats it by much — so the lower bound
     * sits just under it. Delays, congestion and signal holds only ever add
     * time, so the upper bound is generous.
     *
     * <p>Why asymmetry matters more than it looks: a too-high floor rejects
     * <i>real</i> arrivals, and because a timing rejection deliberately costs no
     * confidence, the tracker would fall silently behind while still reporting
     * high confidence — so the fail-safe never fires either. An over-tight floor
     * is therefore the single most dangerous misconfiguration in this class.
     * CALIBRATE against field logs, but widen the ceiling before the floor.
     */
    private static final double RUN_TIME_FLOOR_FRACTION   = 0.85;
    private static final double RUN_TIME_CEILING_FRACTION = 3.00;

    /** Absolute floor for a plausible inter-station leg, ms. */
    private static final long MIN_LEG_MS = 30_000L;

    /** Confidence bookkeeping. */
    private static final double CONFIDENCE_START             = 1.0;
    private static final double CONFIDENCE_FULL_MATCH_GAIN   = 0.10;
    private static final double CONFIDENCE_PARTIAL_PENALTY   = 0.25;
    private static final double CONFIDENCE_FAILSAFE_THRESHOLD = 0.55;

    /** Descent (metres) that indicates entering/leaving the network. */
    private static final double NETWORK_TRANSITION_DEPTH_M = 8.0;

    // ── Collaborators ──────────────────────────────────────────────────────

    interface Listener {
        /** Confident arrival at the alarm target. */
        void onTargetReached(String stopId, String stopName);

        /**
         * Confidence too low to be sure — wake the user early rather than risk
         * sailing past. {@code reason} is user-facing.
         */
        void onLowConfidenceApproach(String stopId, String stopName, String reason);

        /** Position advanced; useful for the notification and for logging. */
        void onPositionChanged(int index, String stopName, double confidence);

        /** Barometer says we surfaced — GPS should be usable again. */
        void onSurfaced();

        /**
         * Barometer says we descended into the network. GPS will not fix down
         * here, so the caller should shut it down rather than burn power on it.
         */
        void onSubmerged();

        /**
         * Belief state changed and should be checkpointed, so an OEM process
         * kill mid-journey does not lose our position.
         */
        void onPersistState(int index, double confidence, long msSinceArrival);
    }

    private final Context context;
    private final JourneyPlan plan;
    private final Listener listener;
    private final SensorLogger logger;

    private SensorManager sensorManager;
    private Sensor pressureSensor;
    private Sensor accelSensor;

    // ── Mutable state ──────────────────────────────────────────────────────

    private int    currentIndex;
    private double confidence = CONFIDENCE_START;
    private long   lastArrivalElapsedMs;
    private boolean finished;

    /** Baseline surface pressure, captured before descending. */
    private double surfacePressureHpa = Double.NaN;

    /**
     * Smoothed pressure as it was at the last confirmed platform.
     *
     * <p>The reference for {@link #depthMatchesStation}. Distinct from
     * {@link #surfacePressureHpa}, which is a one-shot baseline captured
     * wherever the phone happened to be when tracking started and is used only
     * for the coarse submerged/surfaced transition. Re-anchoring here at every
     * arrival is what keeps the barometric test free of both weather drift and
     * any assumption about where the journey began.
     */
    private double anchorPressureHpa = Double.NaN;

    /**
     * True when {@link #anchorPressureHpa} was captured at a station we believe
     * we were actually at.
     *
     * <p>False after a process restart: the pressure history died with the
     * process, so the next sample is taken wherever the train happens to be —
     * possibly mid-tunnel, already part-way through the leg's descent. Anchoring
     * there and calling it a platform would assert a descent that never
     * happened. The barometric test abstains until the next confirmed arrival
     * re-anchors it, which is honest rather than confidently wrong.
     */
    private boolean anchorIsPlatform = false;
    private double lastPressureHpa    = Double.NaN;
    private double smoothedPressureHpa = Double.NaN;
    private boolean belowGround;

    private final double[] accelWindow = new double[ACCEL_WINDOW];
    private int accelCount;
    private int stationaryWindows;
    private boolean currentlyStopped;
    private boolean batchingSuspended;

    /** Wall-clock/monotonic pair for detecting how long a process kill lasted. */
    private long lastPersistWallMs;

    UndergroundEngine(Context context, JourneyPlan plan,
                      Listener listener, SensorLogger logger) {
        this.context  = context;
        this.plan     = plan;
        this.listener = listener;
        this.logger   = logger;
        this.currentIndex = plan.startIndex;
        this.lastArrivalElapsedMs = SystemClock.elapsedRealtime();
    }

    /** @return false when the device lacks the sensors this engine needs. */
    boolean start() {
        sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        if (sensorManager == null) return false;

        pressureSensor = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE);
        accelSensor    = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);

        // The accelerometer is mandatory; without stop detection there is no
        // event to gate. The barometer is strongly preferred but many budget
        // devices omit it, in which case we degrade to timing + accelerometer
        // and start from lower confidence to reflect the weaker evidence.
        if (accelSensor == null) return false;
        if (pressureSensor == null) {
            confidence = CONFIDENCE_FAILSAFE_THRESHOLD + 0.05;
        } else {
            // Pressure changes slowly; NORMAL rate is ample and cheap.
            sensorManager.registerListener(
                    this, pressureSensor, SensorManager.SENSOR_DELAY_NORMAL,
                    BATCH_LATENCY_COASTING_US);
        }
        registerAccel(isApproachingTarget());
        return true;
    }

    /**
     * (Re-)registers the accelerometer with a batch latency appropriate to how
     * close the target is. Batching keeps the application processor asleep
     * between deliveries; we give that up only for the final approach.
     */
    private void registerAccel(boolean approaching) {
        if (sensorManager == null || accelSensor == null) return;
        sensorManager.unregisterListener(this, accelSensor);
        sensorManager.registerListener(this, accelSensor, SAMPLE_PERIOD_US,
                approaching ? BATCH_LATENCY_APPROACHING_US
                            : BATCH_LATENCY_COASTING_US);
        batchingSuspended = approaching;
    }

    /** True when the next station is the alarm target. */
    private boolean isApproachingTarget() {
        int t = plan.nextTargetIndex(currentIndex);
        return t >= 0 && t - currentIndex <= 1;
    }

    void stop() {
        if (sensorManager != null) {
            try { sensorManager.unregisterListener(this); } catch (Exception ignored) {}
        }
        finished = true;
    }

    boolean hasBarometer() { return pressureSensor != null; }

    double confidence() { return confidence; }

    int currentIndex() { return currentIndex; }

    // ── SensorEventListener ────────────────────────────────────────────────

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) { }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (finished) return;
        switch (event.sensor.getType()) {
            case Sensor.TYPE_PRESSURE:     onPressure(event.values[0]); break;
            case Sensor.TYPE_ACCELEROMETER: onAccel(event.values);      break;
            default: break;
        }
    }

    // ── Barometer (signal rank 1) ──────────────────────────────────────────

    private void onPressure(float hpa) {
        lastPressureHpa = hpa;
        // Light exponential smoothing: the barometer is noisy at 1-sample level
        // but the signal we care about (metres of descent) is large and slow.
        smoothedPressureHpa = Double.isNaN(smoothedPressureHpa)
                ? hpa
                : smoothedPressureHpa * 0.8 + hpa * 0.2;

        if (Double.isNaN(surfacePressureHpa)) {
            surfacePressureHpa = smoothedPressureHpa;
        }
        if (Double.isNaN(anchorPressureHpa)) {
            // First leg only. Anchored wherever tracking started, so if the
            // user began above ground the first expectation is out by the
            // boarding station's own depth. Self-corrects at the first
            // confirmed arrival, which re-anchors to a known platform.
            anchorPressureHpa = smoothedPressureHpa;
            anchorIsPlatform = true;
        }

        double depth = currentDepthMetres();
        if (logger != null) logger.logPressure(hpa, depth);

        // Network entry/exit detection (expected-transition, not classification).
        boolean nowBelow = depth > NETWORK_TRANSITION_DEPTH_M;
        if (nowBelow != belowGround) {
            belowGround = nowBelow;
            if (listener == null) return;
            if (belowGround) {
                // GPS cannot fix at platform depth. Leaving it running is pure
                // battery waste, and it is the most expensive radio we hold.
                listener.onSubmerged();
            } else {
                listener.onSurfaced();
            }
        }
    }

    /**
     * Depth below the captured surface baseline, in metres.
     *
     * <p>Relative by construction: absolute barometric altitude is useless here
     * because weather shifts sea-level pressure by far more than a platform's
     * depth. Only the change since boarding carries information.
     */
    private double currentDepthMetres() {
        if (Double.isNaN(surfacePressureHpa) || Double.isNaN(smoothedPressureHpa)) {
            return 0.0;
        }
        return (smoothedPressureHpa - surfacePressureHpa) / HPA_PER_METRE;
    }

    // ── Accelerometer (signal rank 2) ──────────────────────────────────────

    private void onAccel(float[] v) {
        double magnitude = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        accelWindow[accelCount++] = magnitude;
        if (accelCount < ACCEL_WINDOW) return;
        accelCount = 0;

        double mean = 0;
        for (double d : accelWindow) mean += d;
        mean /= ACCEL_WINDOW;
        double variance = 0;
        for (double d : accelWindow) variance += (d - mean) * (d - mean);
        double stdDev = Math.sqrt(variance / ACCEL_WINDOW);

        if (logger != null) logger.logAccelWindow(mean, stdDev);

        if (stdDev < STOPPED_STD_DEV) {
            stationaryWindows++;
            if (stationaryWindows >= STOPPED_WINDOWS_REQUIRED && !currentlyStopped) {
                currentlyStopped = true;
                onFullStopDetected();
            }
        } else {
            stationaryWindows = 0;
            currentlyStopped  = false;
        }
    }

    // ── Fusion (the tunnel-hold discriminator) ─────────────────────────────

    /**
     * Called once per detected full stop. Decides whether this is a platform or
     * a tunnel hold, using the barometric and timing conditions.
     */
    private void onFullStopDetected() {
        int nextIndex = currentIndex + 1;
        JourneyPlan.Station next = plan.at(nextIndex);
        if (next == null) return;

        long now     = SystemClock.elapsedRealtime();
        long elapsed = now - lastArrivalElapsedMs;

        boolean timingOk = timingWindowSatisfied(next, elapsed);
        boolean depthOk  = depthMatchesStation(next);
        boolean pressureSettled = pressureIsSettled();

        if (logger != null) {
            logger.logStopCandidate(next.stopId, elapsed, timingOk,
                    depthOk, pressureSettled,
                    measuredDescentSinceAnchor(), expectedDescentTo(next));
        }

        // ── Reject: a tunnel hold arrives too early for the next platform ──
        if (!timingOk) {
            // Costs no confidence: correctly rejecting a hold is the system
            // working, not degrading.
            return;
        }

        boolean fullMatch = pressureSettled
                && (depthOk || !next.hasDepth() || !hasBarometer());

        if (fullMatch) {
            confidence = Math.min(1.0, confidence + CONFIDENCE_FULL_MATCH_GAIN);
        } else {
            // Timing agreed but the barometer did not corroborate. Most likely a
            // real arrival with a poor depth reading, so advance — but pay for
            // the uncertainty so repeated weak matches trip the fail-safe.
            confidence = Math.max(0.0, confidence - CONFIDENCE_PARTIAL_PENALTY);
        }

        advanceTo(nextIndex, now);
    }

    /**
     * Asymmetric timing gate.
     *
     * <p>Floor is derived from the unimpeded prior (a physical minimum), ceiling
     * from the peak prior (delays only add time). See the constants for why the
     * asymmetry is load-bearing rather than cosmetic.
     */
    private boolean timingWindowSatisfied(JourneyPlan.Station next, long elapsedMs) {
        if (elapsedMs < MIN_LEG_MS) return false;
        if (!next.hasRunTime()) {
            // No prior available — accept, but this is weak evidence. Legs like
            // this are why the plan preview flags missing timing data.
            return true;
        }
        long floorMs = (long) (next.runTimeSecondsFromPrev * 1000L
                * RUN_TIME_FLOOR_FRACTION);
        long ceilingMs = (long) (next.ceilingRunTimeSeconds() * 1000L
                * RUN_TIME_CEILING_FRACTION);
        return elapsedMs >= floorMs && elapsedMs <= ceilingMs;
    }

    /**
     * Does the barometer agree that we have reached {@code station}?
     *
     * <p>Compares the altitude <em>change since the last confirmed platform</em>
     * against the altitude change the two platforms' known levels predict. Both
     * sides are differences, which is what makes this correct:
     *
     * <ul>
     *   <li>It does not care where the pressure baseline was captured. The old
     *       form compared descent-since-boarding against depth-below-street,
     *       which silently assumed every station's street was at the same
     *       height. Streets vary by ~76 m across the network against a 12 m
     *       tolerance, so on Tooting Broadway to Euston the expectation was out
     *       by 21.8 m at the destination and the test could never pass there.
     *   <li>Re-anchoring at every arrival stops slow weather drift accumulating
     *       over a long journey.
     * </ul>
     *
     * <p>Falls back to the old depth comparison only when altitudes are absent,
     * which means a pre-v6 database asset. That path carries the flaw above and
     * exists purely so an app update ahead of an asset update still functions.
     */
    private boolean depthMatchesStation(JourneyPlan.Station station) {
        if (!hasBarometer()) return false;

        // A fallback level is the mean across a station's platforms, or ground
        // level rather than a measured platform, so it can be several metres
        // out. Widen rather than reject: a loose match beats no signal.
        double tolerance = station.depthIsFallback
                ? DEPTH_MATCH_TOLERANCE_M * DEPTH_FALLBACK_TOLERANCE_FACTOR
                : DEPTH_MATCH_TOLERANCE_M;

        double expected = expectedDescentTo(station);
        if (!Double.isNaN(expected)) {
            return Math.abs(measuredDescentSinceAnchor() - expected) <= tolerance;
        }

        // Legacy path: pre-v6 asset with depths but no platform altitudes.
        if (!station.hasDepth()) return false;
        return Math.abs(currentDepthMetres() - station.depthMetres) <= tolerance;
    }

    /**
     * Altitude drop the plan predicts between the current platform and
     * {@code station}, or NaN when either altitude is unknown.
     *
     * <p>Negative when the next platform is higher, which is common and must
     * stay signed: Camden Town's Northern line platforms sit 10 m above sea
     * level while Tooting Broadway's sit at 3 m, so that leg is a climb.
     */
    private double expectedDescentTo(JourneyPlan.Station station) {
        JourneyPlan.Station here = plan.at(currentIndex);
        if (station == null || here == null
                || !station.hasPlatformLevel() || !here.hasPlatformLevel()
                || Double.isNaN(anchorPressureHpa) || !anchorIsPlatform) {
            return Double.NaN;
        }
        return here.platformLevelAslMetres - station.platformLevelAslMetres;
    }

    /** Altitude drop measured since the last confirmed platform, in metres. */
    private double measuredDescentSinceAnchor() {
        if (Double.isNaN(anchorPressureHpa) || Double.isNaN(smoothedPressureHpa)) {
            return 0.0;
        }
        return (smoothedPressureHpa - anchorPressureHpa) / HPA_PER_METRE;
    }

    /** True when vertical movement has stopped — a platform, not an incline. */
    private boolean pressureIsSettled() {
        if (!hasBarometer() || Double.isNaN(lastPressureHpa)
                || Double.isNaN(smoothedPressureHpa)) {
            return false;
        }
        return Math.abs(lastPressureHpa - smoothedPressureHpa) < PRESSURE_SETTLE_HPA;
    }

    // ── Position & alarm decisions ─────────────────────────────────────────

    private void advanceTo(int index, long nowElapsed) {
        currentIndex = index;
        lastArrivalElapsedMs = nowElapsed;

        // Re-anchor the barometric reference to this platform. Every subsequent
        // match is then a single-leg altitude difference, which neither
        // accumulates weather drift nor depends on where tracking started.
        if (!Double.isNaN(smoothedPressureHpa)) {
            anchorPressureHpa = smoothedPressureHpa;
            anchorIsPlatform = true;
        }

        JourneyPlan.Station here = plan.at(index);
        if (here == null) return;

        // Checkpoint on every advance. Advances happen a handful of times per
        // journey, so this is cheap — and without it an OEM kill loses the whole
        // belief state and the tracker silently restarts from the boarding station.
        persistState();

        // Give up batching for the final approach, where latency matters more
        // than power.
        if (!batchingSuspended && isApproachingTarget()) {
            registerAccel(true);
        }

        if (listener != null) {
            listener.onPositionChanged(index, here.stopName, confidence);
        }

        if (here.isAlarmTarget) {
            finished = true;
            if (listener != null) listener.onTargetReached(here.stopId, here.stopName);
            return;
        }

        // ── Fail-safe: approaching the target with weak belief ────────────
        int targetIndex = plan.nextTargetIndex(index);
        if (targetIndex > 0 && targetIndex - index == 1
                && confidence < CONFIDENCE_FAILSAFE_THRESHOLD) {
            JourneyPlan.Station target = plan.at(targetIndex);
            finished = true;
            if (listener != null && target != null) {
                listener.onLowConfidenceApproach(
                        target.stopId, target.stopName,
                        hasBarometer()
                            ? "Couldn't confirm your exact position — waking you "
                              + "one stop early to be safe."
                            : "This phone has no pressure sensor, so underground "
                              + "position is estimated. Waking you one stop early.");
            }
        }
    }

    // ── Belief-state persistence ───────────────────────────────────────────

    private void persistState() {
        lastPersistWallMs = System.currentTimeMillis();
        if (listener != null) {
            listener.onPersistState(currentIndex, confidence,
                    SystemClock.elapsedRealtime() - lastArrivalElapsedMs);
        }
    }

    /**
     * Restores a checkpointed belief after a process restart.
     *
     * <p>{@code gapMs} is how long we were dead, and confidence is reduced in
     * proportion: while the process was gone the train kept moving and no stops
     * were counted, so the saved index is stale by an unknown amount. Restoring
     * at full confidence would suppress the fail-safe exactly when it is most
     * needed — which is what made the original "restart from the boarding
     * station" behaviour dangerous rather than merely wrong.
     *
     * <p>A gap long enough to have covered a whole leg is treated as
     * unrecoverable: confidence drops below the fail-safe threshold so the user
     * gets woken early with an honest message instead of a confident guess.
     */
    void restoreState(int index, double savedConfidence, long msSinceArrival,
                      long gapMs) {
        if (index < 0 || index >= plan.size()) return;
        currentIndex = index;
        lastArrivalElapsedMs = SystemClock.elapsedRealtime() - msSinceArrival;
        // The pressure history died with the process; whatever we sample next
        // is not a platform reading. Abstain until a real arrival re-anchors.
        anchorPressureHpa = Double.NaN;
        anchorIsPlatform = false;

        JourneyPlan.Station next = plan.at(index + 1);
        long legMs = (next != null && next.hasRunTime())
                ? next.runTimeSecondsFromPrev * 1000L
                : 120_000L;

        if (gapMs >= legMs) {
            // Could have passed one or more stations unobserved.
            confidence = Math.min(savedConfidence,
                    CONFIDENCE_FAILSAFE_THRESHOLD - 0.05);
        } else {
            double fraction = (double) gapMs / (double) legMs;
            confidence = Math.max(0.0,
                    savedConfidence - CONFIDENCE_PARTIAL_PENALTY * fraction);
        }
        if (logger != null) {
            logger.logNote("restored index=" + index + " gapMs=" + gapMs
                    + " confidence=" + String.format(java.util.Locale.US, "%.2f",
                                                     confidence));
        }
    }

    /**
     * Weak corroboration that we are at <em>a</em> station — typically a
     * transit-operator Wi-Fi sighting.
     *
     * <p>Deliberately NOT the same as {@link #confirmPosition}. Wi-Fi presence
     * carries no identity: Underground SSIDs are identical network-wide, so a
     * sighting says "some station", never "which station". Treating it as an
     * absolute fix and advancing the index on every sighting would over-advance
     * — two scans on one platform, or signal bleeding through a tunnel near a
     * station, would each step the tracker forward — and resetting confidence to
     * full would then hide the error from the fail-safe.
     *
     * <p>So this only advances when the timing gate <em>already</em> agrees that
     * the next station is plausible, and at most once per index.
     *
     * @return true if the position advanced
     */
    boolean corroborateArrival(String source) {
        if (finished) return false;
        if (lastCorroboratedIndex == currentIndex) return false;   // debounce

        JourneyPlan.Station next = plan.at(currentIndex + 1);
        if (next == null) return false;

        long now = SystemClock.elapsedRealtime();
        if (!timingWindowSatisfied(next, now - lastArrivalElapsedMs)) {
            // Too early to be the next platform — almost certainly Wi-Fi from a
            // station we are passing through or near, not one we have reached.
            if (logger != null) logger.logNote("wifi corroboration rejected: timing");
            return false;
        }

        lastCorroboratedIndex = currentIndex;
        confidence = Math.min(1.0, confidence + CONFIDENCE_FULL_MATCH_GAIN);
        if (logger != null) logger.logExternalFix(currentIndex + 1, source);
        advanceTo(currentIndex + 1, now);
        return true;
    }

    /** Index most recently corroborated, so one arrival cannot advance twice. */
    private int lastCorroboratedIndex = -1;

    /**
     * Absolute positional fix from a signal that carries identity — a
     * fingerprint match, or a GPS fix at a shallow/open-air station.
     *
     * <p>This is the "reset to certainty" path: such a fix is far stronger
     * evidence than sensor coasting, so it overrides the dead-reckoned index
     * outright. Callers must not use it for identity-free signals like bare
     * Wi-Fi presence — use {@link #corroborateArrival} for those.
     */
    void confirmPosition(int index, String source) {
        if (finished) return;
        if (index < 0 || index >= plan.size()) return;
        currentIndex = index;
        confidence = CONFIDENCE_START;
        lastArrivalElapsedMs = SystemClock.elapsedRealtime();
        if (!Double.isNaN(smoothedPressureHpa)) {
            anchorPressureHpa = smoothedPressureHpa;
            anchorIsPlatform = true;
        }
        persistState();
        if (logger != null) logger.logExternalFix(index, source);

        JourneyPlan.Station here = plan.at(index);
        if (here != null && listener != null) {
            listener.onPositionChanged(index, here.stopName, confidence);
            if (here.isAlarmTarget) {
                finished = true;
                listener.onTargetReached(here.stopId, here.stopName);
            }
        }
    }
}
