import 'dart:convert';

import 'package:flutter/services.dart';

/// Everything that determines whether an alarm will actually fire on this
/// device. Produced by AlarmSelfTest.diagnostics() on the native side.
class AlarmDiagnostics {
  const AlarmDiagnostics({
    required this.canScheduleExactAlarms,
    required this.batteryOptimizationExempt,
    required this.notificationsEnabled,
    required this.canUseFullScreenIntent,
    required this.manufacturer,
    required this.androidSdk,
    required this.oemName,
    required this.oemSettingsAvailable,
    required this.lastTestScheduledAt,
    required this.lastTestFiredAt,
  });

  final bool canScheduleExactAlarms;
  final bool batteryOptimizationExempt;
  final bool notificationsEnabled;
  final bool canUseFullScreenIntent;
  final String manufacturer;
  final int androidSdk;

  /// Non-null when this manufacturer is known to run an extra background killer.
  final String? oemName;
  final bool oemSettingsAvailable;

  final int lastTestScheduledAt;
  final int lastTestFiredAt;

  /// True when nothing is known to block alarms.
  bool get allClear =>
      canScheduleExactAlarms &&
      batteryOptimizationExempt &&
      notificationsEnabled;

  /// True when a self-test was started and the alarm actually fired afterwards.
  bool get lastTestPassed =>
      lastTestScheduledAt > 0 && lastTestFiredAt >= lastTestScheduledAt;

  static const empty = AlarmDiagnostics(
    canScheduleExactAlarms: true,
    batteryOptimizationExempt: false,
    notificationsEnabled: true,
    canUseFullScreenIntent: true,
    manufacturer: '',
    androidSdk: 0,
    oemName: null,
    oemSettingsAvailable: false,
    lastTestScheduledAt: 0,
    lastTestFiredAt: 0,
  );

  factory AlarmDiagnostics.fromJson(Map<String, dynamic> j) => AlarmDiagnostics(
        canScheduleExactAlarms: j['canScheduleExactAlarms'] as bool? ?? true,
        batteryOptimizationExempt:
            j['batteryOptimizationExempt'] as bool? ?? false,
        notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
        canUseFullScreenIntent: j['canUseFullScreenIntent'] as bool? ?? true,
        manufacturer: j['manufacturer'] as String? ?? '',
        androidSdk: j['androidSdk'] as int? ?? 0,
        oemName: j['oemName'] as String?,
        oemSettingsAvailable: j['oemSettingsAvailable'] as bool? ?? false,
        lastTestScheduledAt: (j['lastTestScheduledAt'] as num?)?.toInt() ?? 0,
        lastTestFiredAt: (j['lastTestFiredAt'] as num?)?.toInt() ?? 0,
      );
}

class PlatformChannelService {
  PlatformChannelService._();
  static final PlatformChannelService instance = PlatformChannelService._();

  static const _method = MethodChannel('com.stopsnoozer.app/location');
  static const _alarm  = EventChannel('com.stopsnoozer.app/alarm_stream');

  Stream<Map<String, dynamic>> get alarmStream => _alarm
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  Future<void> startGeofence({
    required String stopId,
    required String stopName,
    required double lat,
    required double lon,
    required double radiusMetres,
    String alarmStyle = 'defconDrill',
  }) async {
    try {
      await _method.invokeMethod<void>('startGeofence', {
        'stopId': stopId,
        'stopName': stopName,
        'lat': lat,
        'lon': lon,
        'radiusMetres': radiusMetres,
        'alarmStyle': alarmStyle,
      });
    } on PlatformException catch (_) {}
  }

  Future<void> startWifiSensing({
    required String targetSsid,
    required String stopId,
    required String stopName,
  }) async {
    try {
      await _method.invokeMethod<void>('startWifiSensing', {
        'targetSsid': targetSsid,
        'stopId': stopId,
        'stopName': stopName,
      });
    } on PlatformException catch (_) {}
  }

  /// Runs GPS geofencing and WiFi SSID scanning simultaneously.
  /// Whichever fires first triggers the alarm — GPS handles above-ground
  /// approach while WiFi handles underground platform arrival.
  Future<void> startHybridSensing({
    required String targetSsid,
    required String stopId,
    required String stopName,
    required double lat,
    required double lon,
    double radiusMetres = 300.0,
    String alarmStyle = 'defconDrill',
  }) async {
    try {
      await _method.invokeMethod<void>('startHybridSensing', {
        'targetSsid':   targetSsid,
        'stopId':       stopId,
        'stopName':     stopName,
        'lat':          lat,
        'lon':          lon,
        'radiusMetres': radiusMetres,
        'alarmStyle':   alarmStyle,
      });
    } on PlatformException catch (_) {}
  }

  /// Replaces the full set of actively-tracked stops.
  /// Passing an empty list stops the service.
  Future<void> updateTrackingTargets(List<Map<String, dynamic>> targets) async {
    try {
      await _method.invokeMethod<void>('updateTrackingTargets', {'targets': targets});
    } on PlatformException catch (_) {}
  }

  Future<void> stopTracking() async {
    try {
      await _method.invokeMethod<void>('stopTracking');
    } on PlatformException catch (_) {}
  }

  Future<bool> checkWifiEnabled() async {
    try {
      return await _method.invokeMethod<bool>('checkWifiEnabled') ?? false;
    } on PlatformException catch (_) {
      return true;
    }
  }

  Future<void> openWifiSettings() async {
    try {
      await _method.invokeMethod<void>('openWifiSettings');
    } on PlatformException catch (_) {}
  }

  Future<bool> checkBatteryOptimizationStatus() async {
    try {
      return await _method.invokeMethod<bool>('checkBatteryOptimization') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      return await _method.invokeMethod<bool>('requestBatteryOptimization') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Returns true if USE_FULL_SCREEN_INTENT is granted (always true below Android 14).
  Future<bool> checkFullScreenIntentPermission() async {
    try {
      return await _method.invokeMethod<bool>('canUseFullScreenIntent') ?? true;
    } on PlatformException catch (_) {
      return true;
    }
  }

  /// Opens the system settings page to grant USE_FULL_SCREEN_INTENT (Android 14+ only).
  Future<void> requestFullScreenIntentPermission() async {
    try {
      await _method.invokeMethod<void>('requestFullScreenIntent');
    } on PlatformException catch (_) {}
  }

  /// Stops alarm sound and cancels the alarm notification.
  Future<void> stopAlarm() async {
    try {
      await _method.invokeMethod<void>('stopAlarm');
    } on PlatformException catch (_) {}
  }

  /// Silences the alarm and re-arms tracking after [minutes] (default 5).
  Future<void> snoozeAlarm({int minutes = 5}) async {
    try {
      await _method.invokeMethod<void>('snoozeAlarm', {'minutes': minutes});
    } on PlatformException catch (_) {}
  }

  /// Opens the system alarm ringtone picker.
  /// Returns `{'uri': '...', 'name': '...'}` or null if cancelled.
  Future<Map<String, String>?> openRingtonePicker() async {
    try {
      final result = await _method.invokeMapMethod<String, dynamic>('openRingtonePicker');
      if (result == null) return null;
      return {'uri': result['uri'] as String, 'name': result['name'] as String};
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Returns current alarm settings: alarmType, ringtoneUri, ringtoneName.
  Future<Map<String, String>> getAlarmSettings() async {
    try {
      final result = await _method.invokeMapMethod<String, dynamic>('getAlarmSettings');
      if (result == null) return {'alarmType': 'both', 'ringtoneUri': '', 'ringtoneName': 'Default Alarm'};
      return {
        'alarmType':    result['alarmType']    as String? ?? 'both',
        'ringtoneUri':  result['ringtoneUri']  as String? ?? '',
        'ringtoneName': result['ringtoneName'] as String? ?? 'Default Alarm',
      };
    } on PlatformException catch (_) {
      return {'alarmType': 'both', 'ringtoneUri': '', 'ringtoneName': 'Default Alarm'};
    }
  }

  /// Schedules a commute alarm via AlarmManager.setAlarmClock().
  Future<void> scheduleCommuteAlarm({
    required String alarmId,
    required int hour,
    required int minute,
    required String stopId,
    required String stopName,
    required double lat,
    required double lon,
    String? ssid,
    double radius = 500.0,
    required List<int> weekdays,
    String? specificDate,
    String? tripGroupId,
  }) async {
    try {
      await _method.invokeMethod<void>('scheduleCommuteAlarm', {
        'alarmId':      alarmId,
        'hour':         hour,
        'minute':       minute,
        'stopId':       stopId,
        'stopName':     stopName,
        'lat':          lat,
        'lon':          lon,
        'ssid':         ssid,
        'radius':       radius,
        'weekdays':     _encodeWeekdays(weekdays),
        'specificDate': specificDate,
        'tripGroupId':  tripGroupId,
      });
    } on PlatformException catch (_) {}
  }

  /// Returns the trip group ID saved by CommuteAlarmReceiver when a
  /// group-based alarm fired, then clears it. Returns null if none.
  Future<String?> checkPendingTripGroup() async {
    try {
      return await _method.invokeMethod<String>('checkPendingTripGroup');
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Cancels a previously scheduled commute alarm.
  Future<void> cancelCommuteAlarm(String alarmId) async {
    try {
      await _method.invokeMethod<void>('cancelCommuteAlarm', {'alarmId': alarmId});
    } on PlatformException catch (_) {}
  }

  /// Returns pending alarm data saved by the service while the app was killed,
  /// or null if there is no pending alarm. Clears the data after reading.
  Future<Map<String, dynamic>?> checkPendingAlarm() async {
    try {
      final result = await _method.invokeMapMethod<String, dynamic>('checkPendingAlarm');
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  // ── U5–U9: underground sensor-fusion tracking ───────────────────────────

  /// Hands a resolved journey plan to the native fusion engine.
  ///
  /// [journeyPlan] must be the output of `RouteTopologyRepository.encodePlan`.
  /// Set [enableSensorLogging] only for field-test runs — it writes a CSV per
  /// journey to external storage.
  Future<void> startUndergroundTracking({
    required String journeyPlan,
    bool enableSensorLogging = false,
  }) async {
    try {
      await _method.invokeMethod<void>('startUndergroundTracking', {
        'journeyPlan': journeyPlan,
        'enableSensorLogging': enableSensorLogging,
      });
    } on PlatformException catch (_) {}
  }

  /// Whether this device has the sensors the underground engine needs.
  ///
  /// A missing barometer is not fatal but materially degrades accuracy, so the
  /// UI should say so rather than promising underground tracking it cannot
  /// deliver.
  Future<({bool hasBarometer, bool hasAccelerometer})>
      getUndergroundCapability() async {
    try {
      final r = await _method
          .invokeMapMethod<String, dynamic>('getUndergroundCapability');
      return (
        hasBarometer: r?['hasBarometer'] as bool? ?? false,
        hasAccelerometer: r?['hasAccelerometer'] as bool? ?? false,
      );
    } on PlatformException catch (_) {
      return (hasBarometer: false, hasAccelerometer: false);
    }
  }

  /// Records a field-test ground-truth marker: "I am arriving right now".
  ///
  /// Sensor logs cannot be scored without these — a trace with no reference
  /// points cannot tell a correct detection from a lucky one, which is why
  /// calibration depends on this being used during the ride.
  Future<void> markGroundTruth({String label = 'arrival'}) async {
    try {
      await _method.invokeMethod<void>('markGroundTruth', {'label': label});
    } on PlatformException catch (_) {}
  }

  /// Directory holding field-test sensor CSVs.
  Future<String?> getSensorLogDir() async {
    try {
      return await _method.invokeMethod<String>('getSensorLogDir');
    } on PlatformException catch (_) {
      return null;
    }
  }

  // ── A9: OEM background-restriction settings ─────────────────────────────

  /// Returns `(oemName, settingsAvailable)` for this device.
  ///
  /// `oemName` is null on manufacturers with no known extra background killer —
  /// the UI hides the whole card in that case rather than sending users hunting
  /// for a screen their phone does not have.
  Future<({String? oemName, bool available, String manufacturer})>
      getOemBatteryInfo() async {
    try {
      final r = await _method.invokeMapMethod<String, dynamic>('getOemBatteryInfo');
      return (
        oemName: r?['oemName'] as String?,
        available: r?['available'] as bool? ?? false,
        manufacturer: r?['manufacturer'] as String? ?? '',
      );
    } on PlatformException catch (_) {
      return (oemName: null, available: false, manufacturer: '');
    }
  }

  /// Opens the manufacturer's auto-start / protected-app screen.
  /// Returns false when no such Activity resolved.
  Future<bool> openOemBatterySettings() async {
    try {
      return await _method.invokeMethod<bool>('openOemBatterySettings') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  // ── A10: "Test your alarm" ──────────────────────────────────────────────

  Future<AlarmDiagnostics> getAlarmDiagnostics() async {
    try {
      final raw = await _method.invokeMethod<String>('getAlarmDiagnostics');
      if (raw == null || raw.isEmpty) return AlarmDiagnostics.empty;
      return AlarmDiagnostics.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on PlatformException catch (_) {
      return AlarmDiagnostics.empty;
    } on FormatException catch (_) {
      return AlarmDiagnostics.empty;
    }
  }

  /// Schedules a real alarm [delaySeconds] out, through the same
  /// AlarmManager → BroadcastReceiver → foreground-service path a commute alarm
  /// uses. Returns false if it could only be scheduled *inexactly*, in which
  /// case it may fire late and the UI must say so.
  Future<bool> runAlarmSelfTest({int delaySeconds = 10}) async {
    try {
      return await _method.invokeMethod<bool>(
            'runAlarmSelfTest',
            {'delaySeconds': delaySeconds},
          ) ??
          false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> cancelAlarmSelfTest() async {
    try {
      await _method.invokeMethod<void>('cancelAlarmSelfTest');
    } on PlatformException catch (_) {}
  }

  Future<void> switchLauncherIcon(int index) async {
    try {
      await _method.invokeMethod<void>('switchLauncherIcon', {'index': index});
    } on PlatformException catch (_) {}
  }

  static String _encodeWeekdays(List<int> days) {
    return '[${days.join(',')}]';
  }

  /// Persists alarm settings.
  Future<void> setAlarmSettings({
    required String alarmType,
    String? ringtoneUri,
    String? ringtoneName,
  }) async {
    try {
      final args = <String, dynamic>{'alarmType': alarmType};
      if (ringtoneUri  != null) args['ringtoneUri']  = ringtoneUri;
      if (ringtoneName != null) args['ringtoneName'] = ringtoneName;
      await _method.invokeMethod<void>('setAlarmSettings', args);
    } on PlatformException catch (_) {}
  }
}
