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
  }) async {
    try {
      await _method.invokeMethod<void>('startGeofence', {
        'stopId': stopId,
        'stopName': stopName,
        'lat': lat,
        'lon': lon,
        'radiusMetres': radiusMetres,
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

  Future<void> stopTracking() async {
    try {
      await _method.invokeMethod<void>('stopTracking');
    } on PlatformException catch (_) {}
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      return await _method.invokeMethod<bool>('requestBatteryOptimization') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
