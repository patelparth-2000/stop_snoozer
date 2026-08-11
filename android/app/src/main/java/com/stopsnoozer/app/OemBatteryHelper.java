package com.stopsnoozer.app;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Build;

import java.util.List;
import java.util.Locale;

/**
 * Deep-links into manufacturer-specific "protected app" / "auto-start" screens.
 *
 * <p>The standard {@code REQUEST_IGNORE_BATTERY_OPTIMIZATIONS} dialog is not
 * sufficient on several OEM skins: Xiaomi/MIUI, Huawei, Oppo, Vivo and others
 * run an additional proprietary killer that terminates background services even
 * when the app holds the AOSP battery exemption. Those settings are only
 * reachable through undocumented Activities, so each entry here is a best-effort
 * guess that must be resolve-checked before use.
 *
 * <p>Reference: dontkillmyapp.com — the community catalogue of these behaviours.
 *
 * <p>Deliberately conservative: if nothing resolves we report that rather than
 * firing a blind Intent, because an ActivityNotFoundException on a user's phone
 * is worse than telling them the screen does not exist on their device.
 */
final class OemBatteryHelper {

    private OemBatteryHelper() {}

    /** Candidate Activities per manufacturer, most specific first. */
    private static final String[][] MIUI = {
        {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
        {"com.miui.securitycenter", "com.miui.powercenter.PowerSettings"},
    };
    private static final String[][] HUAWEI = {
        {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
        {"com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"},
        {"com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"},
    };
    private static final String[][] OPPO = {
        {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
        {"com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"},
        {"com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"},
    };
    private static final String[][] VIVO = {
        {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"},
        {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"},
        {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"},
    };
    private static final String[][] SAMSUNG = {
        {"com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"},
        {"com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"},
    };
    private static final String[][] ASUS = {
        {"com.asus.mobilemanager", "com.asus.mobilemanager.powersaver.PowerSaverSettings"},
        {"com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"},
    };
    private static final String[][] LETV = {
        {"com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"},
    };
    private static final String[][] HONOR = {
        {"com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
    };
    private static final String[][] ONEPLUS = {
        {"com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"},
    };

    /** Returns the candidate list for the running device, or null if unknown. */
    private static String[][] candidatesForDevice() {
        String m = Build.MANUFACTURER == null
                ? "" : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco")) return MIUI;
        if (m.contains("huawei"))   return HUAWEI;
        if (m.contains("honor"))    return HONOR;
        if (m.contains("oppo") || m.contains("realme")) return OPPO;
        if (m.contains("vivo"))     return VIVO;
        if (m.contains("samsung"))  return SAMSUNG;
        if (m.contains("asus"))     return ASUS;
        if (m.contains("letv"))     return LETV;
        if (m.contains("oneplus"))  return ONEPLUS;
        return null;
    }

    /**
     * Human-readable label for the OEM restriction screen, or null when the
     * device is not known to need one. The UI uses null to hide the whole card
     * rather than sending users hunting for a screen they do not have.
     */
    static String oemName() {
        String m = Build.MANUFACTURER == null
                ? "" : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco")) return "Xiaomi / MIUI";
        if (m.contains("huawei"))   return "Huawei";
        if (m.contains("honor"))    return "Honor";
        if (m.contains("oppo"))     return "Oppo";
        if (m.contains("realme"))   return "Realme";
        if (m.contains("vivo"))     return "Vivo";
        if (m.contains("samsung"))  return "Samsung";
        if (m.contains("asus"))     return "Asus";
        if (m.contains("letv"))     return "LeEco";
        if (m.contains("oneplus"))  return "OnePlus";
        return null;
    }

    /** True when at least one OEM settings Activity actually resolves here. */
    static boolean hasOemSettings(Context ctx) {
        return resolveFirst(ctx) != null;
    }

    /**
     * Launches the OEM auto-start / protected-app screen.
     *
     * @return true if an Activity was started, false if none resolved.
     */
    static boolean openOemSettings(Context ctx) {
        Intent intent = resolveFirst(ctx);
        if (intent == null) return false;
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            ctx.startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** First candidate Intent that the PackageManager can actually resolve. */
    private static Intent resolveFirst(Context ctx) {
        String[][] candidates = candidatesForDevice();
        if (candidates == null) return null;
        PackageManager pm = ctx.getPackageManager();
        for (String[] c : candidates) {
            Intent i = new Intent();
            i.setComponent(new ComponentName(c[0], c[1]));
            List<ResolveInfo> matches = pm.queryIntentActivities(
                    i, PackageManager.MATCH_DEFAULT_ONLY);
            if (matches != null && !matches.isEmpty()) return i;
        }
        return null;
    }
}
