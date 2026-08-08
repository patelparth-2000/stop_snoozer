package com.stopsnoozer.app;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.SystemClock;
import android.telephony.CellInfo;
import android.telephony.CellInfoGsm;
import android.telephony.CellInfoLte;
import android.telephony.CellInfoNr;
import android.telephony.CellInfoWcdma;
import android.telephony.CellIdentityLte;
import android.telephony.CellIdentityNr;
import android.telephony.TelephonyManager;

import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.List;

/**
 * Opportunistic Cell-ID observation — <b>never</b> a primary positioning signal.
 *
 * <p><b>Why demoted.</b> In deep tube the handset reports literal No Service.
 * {@code getAllCellInfo()} then returns either nothing or, far worse, cells
 * <em>cached from the previous station</em>. Acting on a stale cell would place
 * the user at a station they left minutes ago — a false positive that is more
 * damaging than no reading at all. The one API that could enumerate
 * unregisterable cells, {@code requestNetworkScan()}, needs
 * {@code MODIFY_PHONE_STATE}, which is signature/system-only and unavailable to
 * Play Store apps.
 *
 * <p><b>The rule.</b> Every observation carries {@link CellInfo#getTimestampMillis()}
 * and anything older than {@link #MAX_AGE_MS} is discarded. AOSP's own
 * {@code ServiceStateTracker} caches for 2 s
 * ({@code LAST_CELL_INFO_LIST_MAX_AGE_MS}), so a 5 s ceiling is deliberately
 * tight — the cost of dropping a good reading is one missed corroboration, while
 * the cost of accepting a stale one is waking the user in the wrong place.
 */
final class CellObserver {

    /** Readings older than this are rejected outright. Not negotiable. */
    static final long MAX_AGE_MS = 5_000L;

    static final class Observation {
        final int cellId;
        final long ageMs;
        final boolean registered;

        Observation(int cellId, long ageMs, boolean registered) {
            this.cellId = cellId;
            this.ageMs = ageMs;
            this.registered = registered;
        }
    }

    private final Context context;
    private final SensorLogger logger;

    CellObserver(Context context, SensorLogger logger) {
        this.context = context;
        this.logger  = logger;
    }

    private boolean hasPermission() {
        return ContextCompat.checkSelfPermission(
                context, Manifest.permission.READ_PHONE_STATE)
                == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * Returns only observations fresh enough to trust.
     *
     * <p>Empty is a completely normal result underground and must be treated as
     * "no information", never as "position unchanged".
     */
    List<Observation> observeFresh() {
        List<Observation> out = new ArrayList<>();
        if (!hasPermission()) return out;

        TelephonyManager tm =
                (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        if (tm == null) return out;

        List<CellInfo> infos;
        try {
            infos = tm.getAllCellInfo();
        } catch (SecurityException e) {
            return out;
        }
        if (infos == null) return out;

        long nowNanos = SystemClock.elapsedRealtimeNanos();
        for (CellInfo info : infos) {
            long ageMs = ageMillis(info, nowNanos);
            int  id    = identityOf(info);
            boolean accepted = ageMs >= 0 && ageMs <= MAX_AGE_MS
                    && id != CellInfo.UNAVAILABLE;

            if (logger != null) {
                logger.logCellInfo(id, (int) ageMs, info.isRegistered(), accepted);
            }
            if (accepted) {
                out.add(new Observation(id, ageMs, info.isRegistered()));
            }
        }
        return out;
    }

    /**
     * Age of a reading in ms, or -1 when it cannot be determined.
     *
     * <p>An indeterminable age is treated as untrustworthy rather than fresh:
     * assuming freshness here is precisely the stale-cache bug.
     */
    private static long ageMillis(CellInfo info, long nowNanos) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                long stampMs = info.getTimestampMillis();
                if (stampMs <= 0) return -1;
                return (nowNanos / 1_000_000L) - stampMs;
            }
            @SuppressWarnings("deprecation")
            long nanos = info.getTimeStamp();
            if (nanos <= 0) return -1;
            return (nowNanos - nanos) / 1_000_000L;
        } catch (Exception e) {
            return -1;
        }
    }

    /** A stable per-cell integer, or {@link CellInfo#UNAVAILABLE}. */
    private static int identityOf(CellInfo info) {
        try {
            if (info instanceof CellInfoLte) {
                CellIdentityLte id = ((CellInfoLte) info).getCellIdentity();
                return id.getCi();
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    && info instanceof CellInfoNr) {
                CellIdentityNr id = (CellIdentityNr) ((CellInfoNr) info).getCellIdentity();
                // NCI is 36-bit; fold to int for use as an opaque key only.
                return (int) (id.getNci() & 0x7FFFFFFFL);
            }
            if (info instanceof CellInfoGsm) {
                return ((CellInfoGsm) info).getCellIdentity().getCid();
            }
            if (info instanceof CellInfoWcdma) {
                return ((CellInfoWcdma) info).getCellIdentity().getCid();
            }
        } catch (Exception ignored) {
        }
        return CellInfo.UNAVAILABLE;
    }
}
