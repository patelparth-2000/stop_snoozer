import 'package:equatable/equatable.dart';
import 'stop_point.dart';

class SavedLocation extends Equatable {
  const SavedLocation({
    required this.id,
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required this.mode,
    this.wifiSsid,
    this.radius = 500.0,
    this.isActive = false,
  });

  final String  id;
  final String  stopId;
  final String  stopName;
  final double  latitude;
  final double  longitude;
  final String  mode;
  final String? wifiSsid;
  final double  radius;
  final bool    isActive;

  factory SavedLocation.fromStop(StopPoint stop, {double radius = 500.0}) =>
      SavedLocation(
        id:        stop.id,
        stopId:    stop.id,
        stopName:  stop.name,
        latitude:  stop.latitude,
        longitude: stop.longitude,
        mode:      stop.mode.name,
        wifiSsid:  stop.wifiSsid,
        radius:    radius,
      );

  StopPoint toStopPoint() => StopPoint(
        id:        stopId,
        name:      stopName,
        latitude:  latitude,
        longitude: longitude,
        mode:      _parseMode(mode),
        wifiSsid:  wifiSsid,
      );

  static TransitMode _parseMode(String m) {
    switch (m) {
      case 'tube':        return TransitMode.tube;
      case 'dlr':         return TransitMode.dlr;
      case 'overground':  return TransitMode.overground;
      case 'tram':        return TransitMode.tram;
      case 'rail':        return TransitMode.rail;
      case 'ferry':       return TransitMode.ferry;
      default:            return TransitMode.bus;
    }
  }

  SavedLocation copyWith({bool? isActive}) => SavedLocation(
        id:        id,
        stopId:    stopId,
        stopName:  stopName,
        latitude:  latitude,
        longitude: longitude,
        mode:      mode,
        wifiSsid:  wifiSsid,
        radius:    radius,
        isActive:  isActive ?? this.isActive,
      );

  Map<String, dynamic> toMap() => {
        'id':        id,
        'stop_id':   stopId,
        'stop_name': stopName,
        'latitude':  latitude,
        'longitude': longitude,
        'mode':      mode,
        'wifi_ssid': wifiSsid,
        'radius':    radius,
        'is_active': isActive ? 1 : 0,
      };

  factory SavedLocation.fromMap(Map<String, dynamic> m) => SavedLocation(
        id:        m['id']        as String,
        stopId:    m['stop_id']   as String,
        stopName:  m['stop_name'] as String,
        latitude:  (m['latitude']  as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        mode:      m['mode']      as String,
        wifiSsid:  m['wifi_ssid'] as String?,
        radius:    (m['radius']   as num?)?.toDouble() ?? 500.0,
        isActive:  (m['is_active'] as int) == 1,
      );

  @override
  List<Object?> get props =>
      [id, stopId, stopName, latitude, longitude, mode, wifiSsid, radius, isActive];
}
