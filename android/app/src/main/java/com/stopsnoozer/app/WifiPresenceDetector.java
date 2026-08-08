package com.stopsnoozer.app;

import android.content.Context;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiManager;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Wi-Fi as a <b>presence</b> signal, not an identity one. (U3)
 *
 * <p><b>What was wrong before.</b> The previous implementation matched a
 * per-stop {@code wifi_ssid} string against scan results, expecting an SSID to
 * identify <em>which</em> station the user was at. That cannot work: London
 * Underground Wi-Fi is provider-branded and identical across all 260+ stations
 * ("TfL WiFi", "EE WiFi", "Three_WiFi" appear network-wide), and no open dataset
 * publishes per-station access-point identifiers. The column could never be
 * populated with anything meaningful.
 *
 * <p><b>What replaces it.</b> Identity comes from the route model — the journey
 * is pre-selected, so the engine already knows which station is next. The signal
 * only has to answer a much easier question: <em>are we at a station at all?</em>
 * Seeing any station-grade Wi-Fi is sufficient corroboration for an arrival the
 * engine already expects.
 *
 * <p><b>Cadence.</b> Android throttles scans to 4 per 2 minutes and a foreground
 * service does not exempt us, so this cannot be a metronome. Scans are requested
 * around expected arrival windows and treated as bonus confirmation.
 */
final class WifiPresenceDetector {

    /**
     * SSID fragments that indicate transit infrastructure rather than a home or
     * shop network. Matched case-insensitively as substrings because operators
     * append suffixes ("TfL WiFi", "_TfL WiFi Auto").
     */
    private static final String[] STATION_SSID_HINTS = {
        "tfl wifi", "tflwifi",
        "virgin media", "virginmedia",
        "ee wifi", "three_wifi", "vodafone wifi", "o2 wifi",
        "lul-free-wifi",          // legacy TfL naming, still seen at some sites
        "boldyn", "wifi_by_boldyn",
        "network rail", "nationalrail", "_thetrainline",
        "gwr wifi", "avanti", "lner", "southeastern",
    };

    private final WifiManager wifiManager;
    private final SensorLogger logger;

    WifiPresenceDetector(Context ctx, SensorLogger logger) {
        this.wifiManager = (WifiManager) ctx.getApplicationContext()
                .getSystemService(Context.WIFI_SERVICE);
        this.logger = logger;
    }

    boolean isWifiEnabled() {
        return wifiManager != null && wifiManager.isWifiEnabled();
    }

    /**
     * Requests a scan.
     *
     * @return false when the request was throttled, so the caller can back off
     *         rather than hammering an API that is rate-limited anyway.
     */
    @SuppressWarnings("deprecation")
    boolean requestScan() {
        if (wifiManager == null) return false;
        try {
            return wifiManager.startScan();
        } catch (Exception e) {
            return false;
        }
    }

    /** Snapshot of the current scan cache. */
    static final class Presence {
        /** True when at least one transit-grade network is visible. */
        final boolean atStation;
        /** All visible BSSIDs — used to build the self-learned fingerprint. */
        final List<String> bssids;
        final int apCount;

        Presence(boolean atStation, List<String> bssids, int apCount) {
            this.atStation = atStation;
            this.bssids    = bssids;
            this.apCount   = apCount;
        }

        static final Presence none =
                new Presence(false, new ArrayList<>(), 0);
    }

    @SuppressWarnings("deprecation")
    Presence evaluate() {
        if (wifiManager == null) return Presence.none;
        List<ScanResult> results;
        try {
            results = wifiManager.getScanResults();
        } catch (SecurityException e) {
            return Presence.none;
        }
        if (results == null || results.isEmpty()) return Presence.none;

        boolean atStation = false;
        List<String> bssids = new ArrayList<>(results.size());
        for (ScanResult r : results) {
            String ssid = ssidOf(r);
            if (ssid != null && looksLikeStationNetwork(ssid)) atStation = true;
            if (r.BSSID != null) bssids.add(r.BSSID);
        }
        if (logger != null) logger.logWifiScan(results.size(), true);
        return new Presence(atStation, bssids, results.size());
    }

    @SuppressWarnings("deprecation")
    private static String ssidOf(ScanResult r) {
        // getWifiSsid() (API 33+) is the non-deprecated accessor, but its
        // toString() wraps the value in quotes, so normalise both paths.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                if (r.getWifiSsid() != null) {
                    String s = r.getWifiSsid().toString();
                    return s.replaceAll("^\"|\"$", "");
                }
            } catch (Exception ignored) {
            }
        }
        return r.SSID;
    }

    /** True when this SSID belongs to transit infrastructure. */
    static boolean looksLikeStationNetwork(String ssid) {
        if (ssid == null || ssid.isEmpty()) return false;
        String s = ssid.toLowerCase(Locale.ROOT);
        for (String hint : STATION_SSID_HINTS) {
            if (s.contains(hint)) return true;
        }
        return false;
    }
}
