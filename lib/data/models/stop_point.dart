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
    this.indicator,
    this.distanceKm,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final TransitMode mode;
  final List<String> lines;
  final String? wifiSsid;
  /// NaPTAN Indicator — e.g. "Stop A", "W", "opp Church". Non-null when the
  /// stop has a positional identifier that helps users locate it physically.
  final String? indicator;
  final double? distanceKm;

  StopPoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    TransitMode? mode,
    List<String>? lines,
    String? wifiSsid,
    String? indicator,
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
        indicator: indicator ?? this.indicator,
        distanceKm: distanceKm ?? this.distanceKm,
      );

  factory StopPoint.fromMap(Map<String, dynamic> map) => StopPoint(
        id: map['id'] as String,
        name: map['name'] as String,
        latitude: ((map['latitude'] ?? map['lat']) as num).toDouble(),
        longitude: ((map['longitude'] ?? map['lng']) as num).toDouble(),
        mode: _transitTypeToMode(
          (map['transit_type'] ?? map['mode'] as String?) ?? 'bus',
        ),
        wifiSsid: map['wifi_ssid'] as String?,
        indicator: map['indicator'] as String?,
      );

  static TransitMode _transitTypeToMode(String type) {
    switch (type.toLowerCase()) {
      case 'underground':
      case 'tube':
        return TransitMode.tube;
      case 'dlr':
        return TransitMode.dlr;
      case 'overground':
        return TransitMode.overground;
      case 'tram':
        return TransitMode.tram;
      case 'ferry':
        return TransitMode.ferry;
      case 'train':
      case 'rail':
        return TransitMode.rail;
      default:
        return TransitMode.bus;
    }
  }

  String get transitTypeString => _modeToTransitType(mode);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'transit_type': _modeToTransitType(mode),
        'wifi_ssid': wifiSsid,
        'indicator': indicator,
      };

  static String _modeToTransitType(TransitMode mode) {
    switch (mode) {
      case TransitMode.tube:       return 'underground';
      case TransitMode.dlr:        return 'dlr';
      case TransitMode.overground: return 'overground';
      case TransitMode.tram:       return 'tram';
      case TransitMode.ferry:      return 'ferry';
      case TransitMode.rail:       return 'train';
      case TransitMode.bus:        return 'bus';
    }
  }

  @override
  List<Object?> get props => [id, name, latitude, longitude, mode, wifiSsid, indicator];
}
