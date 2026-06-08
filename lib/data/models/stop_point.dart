import 'package:equatable/equatable.dart';

enum TransitMode { tube, bus, rail, dlr, overground, tram, ferry }

class StopPoint extends Equatable {
  const StopPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.mode,
    this.lines = const [],
    this.wifiSsid,
    this.distanceKm,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final TransitMode mode;
  final List<String> lines;
  final String? wifiSsid;
  final double? distanceKm;

  StopPoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    TransitMode? mode,
    List<String>? lines,
    String? wifiSsid,
    double? distanceKm,
  }) =>
      StopPoint(
        id: id ?? this.id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        mode: mode ?? this.mode,
        lines: lines ?? this.lines,
        wifiSsid: wifiSsid ?? this.wifiSsid,
        distanceKm: distanceKm ?? this.distanceKm,
      );

  factory StopPoint.fromMap(Map<String, dynamic> map) => StopPoint(
        id: map['id'] as String,
        name: map['name'] as String,
        latitude: (map['lat'] as num).toDouble(),
        longitude: (map['lng'] as num).toDouble(),
        mode: TransitMode.values.firstWhere(
          (m) => m.name == (map['mode'] as String),
          orElse: () => TransitMode.bus,
        ),
        wifiSsid: map['wifi_ssid'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
        'mode': mode.name,
        'wifi_ssid': wifiSsid,
      };

  @override
  List<Object?> get props => [id, name, latitude, longitude, mode, wifiSsid];
}
