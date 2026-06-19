import 'package:flutter/services.dart';

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
