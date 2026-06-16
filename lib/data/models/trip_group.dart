import 'package:equatable/equatable.dart';
import 'stop_point.dart';
import 'trip_leg.dart';

class TripGroup extends Equatable {
  const TripGroup({
    required this.id,
    required this.name,
    required this.legs,
  });

  final String id;
  final String name;
  final List<TripLeg> legs;

  TripGroup copyWith({String? id, String? name, List<TripLeg>? legs}) =>
      TripGroup(id: id ?? this.id, name: name ?? this.name, legs: legs ?? this.legs);

  Map<String, dynamic> toJson() => {
        'id':   id,
        'name': name,
        'legs': legs.map(_legToJson).toList(),
      };

  factory TripGroup.fromJson(Map<String, dynamic> j) => TripGroup(
        id:   j['id']   as String,
        name: j['name'] as String,
        legs: (j['legs'] as List<dynamic>)
            .map((e) => _legFromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, dynamic> _legToJson(TripLeg leg) => {
        'stopId':         leg.stop.id,
        'stopName':       leg.stop.name,
        'latitude':       leg.stop.latitude,
        'longitude':      leg.stop.longitude,
        'mode':           leg.stop.transitTypeString,
        'wifiSsid':       leg.stop.wifiSsid,
        'indicator':      leg.stop.indicator,
        'radiusMetres':   leg.wakeRadiusMetres,
        'alarmStyle':     leg.alarmStyle.index,
      };

  static TripLeg _legFromJson(Map<String, dynamic> m) => TripLeg(
        stop: StopPoint.fromMap({
          'id':           m['stopId'],
          'name':         m['stopName'],
          'latitude':     m['latitude'],
          'longitude':    m['longitude'],
          'transit_type': m['mode'] ?? 'bus',
          'wifi_ssid':    m['wifiSsid'],
          'indicator':    m['indicator'],
        }),
        wakeRadiusMetres: (m['radiusMetres'] as num?)?.toDouble() ?? 300.0,
        alarmStyle: AlarmStyle.values[(m['alarmStyle'] as int?) ?? 1],
      );

  @override
  List<Object?> get props => [id, name, legs];
}
