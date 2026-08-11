package com.stopsnoozer.app

import android.app.Activity
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val LOCATION_CHANNEL      = "com.stopsnoozer.app/location"
        private const val ALARM_CHANNEL          = "com.stopsnoozer.app/alarm_stream"
        private const val REQUEST_CODE_RINGTONE  = 42
    }

    private var pendingRingtoneResult: MethodChannel.Result? = null

    // ── Show over lock screen when launched from alarm notification ────────

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.getBooleanExtra("alarmFromService", false) == true) {
            applyAlarmWindowFlags()
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("alarmFromService", false)) {
            applyAlarmWindowFlags()
        }
    }

    private fun applyAlarmWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMethodChannel(flutterEngine)
        setupAlarmEventChannel(flutterEngine)
    }

    // ── Method channel ─────────────────────────────────────────────────────

    private fun setupMethodChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startGeofence" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_START_GEOFENCE
                            it.putExtra("stopId",       call.argument<String>("stopId")     ?: "")
                            it.putExtra("stopName",     call.argument<String>("stopName")   ?: "")
                            it.putExtra("lat",          call.argument<Double>("lat")        ?: 0.0)
                            it.putExtra("lon",          call.argument<Double>("lon")        ?: 0.0)
                            it.putExtra("radiusMetres",
                                (call.argument<Double>("radiusMetres") ?: 500.0).toFloat())
                            it.putExtra("alarmStyle",   call.argument<String>("alarmStyle") ?: "defconDrill")
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }

                    "startWifiSensing" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_START_WIFI
                            it.putExtra("stopId",     call.argument<String>("stopId")     ?: "")
                            it.putExtra("stopName",   call.argument<String>("stopName")   ?: "")
                            it.putExtra("targetSsid", call.argument<String>("targetSsid") ?: "")
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }

                    "updateTrackingTargets" -> {
                        val targetsJson = try {
                            val list = call.argument<List<Map<String, Any?>>>("targets") ?: emptyList()
                            org.json.JSONArray(list.map { org.json.JSONObject(it.filterValues { v -> v != null } as Map<*, *>) }).toString()
                        } catch (_: Exception) { "[]" }
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_UPDATE_TARGETS
                            it.putExtra("targetsJson", targetsJson)
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }

                    "startHybridSensing" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_START_HYBRID
                            it.putExtra("stopId",       call.argument<String>("stopId")     ?: "")
                            it.putExtra("stopName",     call.argument<String>("stopName")   ?: "")
                            it.putExtra("targetSsid",   call.argument<String>("targetSsid") ?: "")
                            it.putExtra("lat",          call.argument<Double>("lat")        ?: 0.0)
                            it.putExtra("lon",          call.argument<Double>("lon")        ?: 0.0)
                            it.putExtra("radiusMetres",
                                (call.argument<Double>("radiusMetres") ?: 300.0).toFloat())
                            it.putExtra("alarmStyle",   call.argument<String>("alarmStyle") ?: "defconDrill")
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }

                    "stopTracking" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }

                    "stopAlarm" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_STOP_ALARM
                        }
                        startService(intent)
                        result.success(null)
                    }

                    "snoozeAlarm" -> {
                        val minutes = call.argument<Int>("minutes") ?: 5
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_SNOOZE
                            it.putExtra(SnoozeTrackingService.EXTRA_SNOOZE_MINUTES, minutes)
                        }
                        startService(intent)
                        result.success(null)
                    }

                    "checkWifiEnabled" -> {
                        val wm = applicationContext.getSystemService(android.content.Context.WIFI_SERVICE)
                                as android.net.wifi.WifiManager
                        result.success(wm.isWifiEnabled)
                    }

                    "openWifiSettings" -> {
                        startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    }

                    "checkBatteryOptimization" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    "requestBatteryOptimization" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Exception) {}
                        }
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    "openRingtonePicker" -> {
                        pendingRingtoneResult = result
                        val prefs  = getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE)
                        val curUri = prefs.getString(SnoozeTrackingService.PREF_RINGTONE_URI, null)
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,         RingtoneManager.TYPE_ALARM)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,  false)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE,        "Select Alarm Tone")
                            if (curUri != null) {
                                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(curUri))
                            }
                        }
                        startActivityForResult(intent, REQUEST_CODE_RINGTONE)
                        // result returned asynchronously in onActivityResult
                    }

                    "getAlarmSettings" -> {
                        val prefs = getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE)
                        result.success(mapOf(
                            "alarmType"    to (prefs.getString(SnoozeTrackingService.PREF_ALARM_TYPE,    "both")            ?: "both"),
                            "ringtoneUri"  to (prefs.getString(SnoozeTrackingService.PREF_RINGTONE_URI,  "")                ?: ""),
                            "ringtoneName" to (prefs.getString(SnoozeTrackingService.PREF_RINGTONE_NAME, "Default Alarm")   ?: "Default Alarm")
                        ))
                    }

                    "setAlarmSettings" -> {
                        val editor = getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE).edit()
                        call.argument<String>("alarmType")?.let    { editor.putString(SnoozeTrackingService.PREF_ALARM_TYPE,    it) }
                        call.argument<String>("ringtoneUri")?.let  { editor.putString(SnoozeTrackingService.PREF_RINGTONE_URI,  it) }
                        call.argument<String>("ringtoneName")?.let { editor.putString(SnoozeTrackingService.PREF_RINGTONE_NAME, it) }
                        editor.apply()
                        result.success(null)
                    }

                    "canUseFullScreenIntent" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                            nm.canUseFullScreenIntent()
                        } else {
                            true
                        }
                        result.success(granted)
                    }

                    "requestFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            try {
                                // Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENTS = API 34
                                startActivity(
                                    Intent(
                                        "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENTS",
                                        Uri.parse("package:$packageName")
                                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                                )
                            } catch (_: Exception) {}
                        }
                        result.success(null)
                    }

                    "scheduleCommuteAlarm" -> {
                        val id          = call.argument<String>("alarmId")     ?: run { result.error("MISSING", "alarmId required", null); return@setMethodCallHandler }
                        val stopId      = call.argument<String>("stopId")      ?: ""
                        val stopName    = call.argument<String>("stopName")    ?: ""
                        val lat         = call.argument<Double>("lat")         ?: 0.0
                        val lon         = call.argument<Double>("lon")         ?: 0.0
                        val ssid        = call.argument<String>("ssid")
                        val radius      = (call.argument<Double>("radius")     ?: 500.0).toFloat()
                        val weekdays    = call.argument<String>("weekdays")    ?: "[]"
                        val specDate    = call.argument<String>("specificDate")
                        val hour        = call.argument<Int>("hour")           ?: 0
                        val minute      = call.argument<Int>("minute")         ?: 0
                        val tripGroupId = call.argument<String>("tripGroupId")
                        AlarmScheduler.scheduleAndSave(
                            this, id, hour, minute,
                            stopId, stopName, lat, lon,
                            ssid, radius, weekdays, specDate, tripGroupId
                        )
                        result.success(null)
                    }

                    "checkPendingTripGroup" -> {
                        val prefs       = getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE)
                        val tripGroupId = prefs.getString("pending_trip_group_id", null)
                        if (tripGroupId != null) {
                            prefs.edit().remove("pending_trip_group_id").apply()
                        }
                        result.success(tripGroupId)
                    }

                    "cancelCommuteAlarm" -> {
                        val id = call.argument<String>("alarmId") ?: run { result.error("MISSING", "alarmId required", null); return@setMethodCallHandler }
                        AlarmScheduler.cancelAndRemove(this, id)
                        result.success(null)
                    }

                    "checkPendingAlarm" -> {
                        val prefs    = getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE)
                        val stopId   = prefs.getString("pending_alarm_stop_id",   null)
                        val stopName = prefs.getString("pending_alarm_stop_name", null)
                        if (stopId == null) {
                            result.success(null)
                        } else {
                            val distance = prefs.getFloat("pending_alarm_distance", 0f).toDouble()
                            val firedAt  = prefs.getLong("pending_alarm_fired_at", 0L)
                            prefs.edit()
                                .remove("pending_alarm_stop_id")
                                .remove("pending_alarm_stop_name")
                                .remove("pending_alarm_distance")
                                .remove("pending_alarm_fired_at")
                                .apply()
                            result.success(mapOf(
                                "stopId"         to stopId,
                                "stopName"       to (stopName ?: "Your Stop"),
                                "distanceMetres" to distance,
                                "firedAt"        to firedAt,
                                "countdownSecs"  to 5
                            ))
                        }
                    }

                    "switchLauncherIcon" -> {
                        val index = call.argument<Int>("index") ?: 0
                        switchLauncherIcon(index)
                        result.success(null)
                    }

                    // ── U5–U9: underground sensor-fusion tracking ─────────────
                    "startUndergroundTracking" -> {
                        val plan = call.argument<String>("journeyPlan")
                        if (plan.isNullOrEmpty()) {
                            result.error("MISSING", "journeyPlan required", null)
                        } else {
                            val intent = Intent(this, SnoozeTrackingService::class.java).also {
                                it.action = SnoozeTrackingService.ACTION_START_UNDERGROUND
                                it.putExtra(SnoozeTrackingService.EXTRA_JOURNEY_PLAN, plan)
                                it.putExtra(
                                    SnoozeTrackingService.EXTRA_ENABLE_LOGGING,
                                    call.argument<Boolean>("enableSensorLogging") ?: false
                                )
                            }
                            ContextCompat.startForegroundService(this, intent)
                            result.success(null)
                        }
                    }

                    // Reports whether this device can run the underground engine.
                    "getUndergroundCapability" -> {
                        val sm = getSystemService(SENSOR_SERVICE)
                                as android.hardware.SensorManager
                        result.success(mapOf(
                            "hasBarometer" to (sm.getDefaultSensor(
                                android.hardware.Sensor.TYPE_PRESSURE) != null),
                            "hasAccelerometer" to (sm.getDefaultSensor(
                                android.hardware.Sensor.TYPE_ACCELEROMETER) != null)
                        ))
                    }

                    // Field-test ground-truth marker: "I am arriving right now".
                    // The sensor logs are unscoreable without these, so this is
                    // what makes threshold calibration possible at all.
                    "markGroundTruth" -> {
                        val intent = Intent(this, SnoozeTrackingService::class.java).also {
                            it.action = SnoozeTrackingService.ACTION_GROUND_TRUTH
                            it.putExtra(
                                SnoozeTrackingService.EXTRA_GROUND_TRUTH_LABEL,
                                call.argument<String>("label") ?: "arrival"
                            )
                        }
                        startService(intent)
                        result.success(null)
                    }

                    // Directory holding field-test CSVs, for the UI to surface.
                    "getSensorLogDir" -> {
                        result.success(java.io.File(
                            getExternalFilesDir(null), "sensor_logs").absolutePath)
                    }

                    // ── A9: OEM-specific background restriction settings ──────
                    "getOemBatteryInfo" -> {
                        result.success(mapOf(
                            "manufacturer" to (Build.MANUFACTURER ?: ""),
                            "oemName"      to OemBatteryHelper.oemName(),
                            "available"    to OemBatteryHelper.hasOemSettings(this)
                        ))
                    }

                    "openOemBatterySettings" -> {
                        result.success(OemBatteryHelper.openOemSettings(this))
                    }

                    // ── A10: "Test your alarm" ────────────────────────────────
                    "getAlarmDiagnostics" -> {
                        result.success(AlarmSelfTest.diagnostics(this))
                    }

                    "runAlarmSelfTest" -> {
                        val delay = call.argument<Int>("delaySeconds") ?: 10
                        result.success(AlarmSelfTest.schedule(this, delay))
                    }

                    "cancelAlarmSelfTest" -> {
                        AlarmSelfTest.cancel(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Ringtone picker result ─────────────────────────────────────────────

    @Deprecated("onActivityResult is still used for RingtoneManager picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_RINGTONE) return

        val pending = pendingRingtoneResult ?: return
        pendingRingtoneResult = null

        if (resultCode != Activity.RESULT_OK) {
            pending.success(null) // user cancelled
            return
        }

        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }

        if (uri == null) {
            pending.success(null)
            return
        }

        val name = try {
            RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Selected Alarm"
        } catch (_: Exception) { "Selected Alarm" }

        // Persist immediately
        getSharedPreferences(SnoozeTrackingService.PREFS_NAME, MODE_PRIVATE).edit()
            .putString(SnoozeTrackingService.PREF_RINGTONE_URI,  uri.toString())
            .putString(SnoozeTrackingService.PREF_RINGTONE_NAME, name)
            .apply()

        pending.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    // ── Dynamic launcher icon ─────────────────────────────────────────────

    private fun switchLauncherIcon(themeIndex: Int) {
        val aliases = listOf(
            "com.stopsnoozer.app.MainActivityAlias_Amber",
            "com.stopsnoozer.app.MainActivityAlias_Navy",
            "com.stopsnoozer.app.MainActivityAlias_Forest",
            "com.stopsnoozer.app.MainActivityAlias_Volcanic",
            "com.stopsnoozer.app.MainActivityAlias_Galactic"
        )
        val pm = packageManager
        aliases.forEachIndexed { i, alias ->
            val state = if (i == themeIndex)
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            try {
                pm.setComponentEnabledSetting(
                    ComponentName(this, alias),
                    state,
                    PackageManager.DONT_KILL_APP
                )
            } catch (_: Exception) {}
        }
    }

    // ── Alarm event channel ────────────────────────────────────────────────

    private fun setupAlarmEventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(ctx: Context, intent: Intent) {
                            val payload = mapOf(
                                "stopId"         to (intent.getStringExtra("stopId")   ?: ""),
                                "stopName"       to (intent.getStringExtra("stopName") ?: ""),
                                "distanceMetres" to intent.getFloatExtra("distanceMetres", 0f).toDouble(),
                                "firedAt"        to intent.getLongExtra("firedAt", 0L),
                                "countdownSecs"  to intent.getIntExtra("countdownSecs", 5)
                            )
                            events.success(payload)
                        }
                    }
                    ContextCompat.registerReceiver(
                        this@MainActivity, receiver,
                        IntentFilter(SnoozeTrackingService.ACTION_ALARM_TRIGGER),
                        ContextCompat.RECEIVER_NOT_EXPORTED
                    )
                }

                override fun onCancel(arguments: Any?) {
                    try { unregisterReceiver(receiver) } catch (_: Exception) {}
                    receiver = null
                }
            })
    }
}
