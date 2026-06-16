import 'dart:convert';
import 'package:equatable/equatable.dart';

class CommuteAlarm extends Equatable {
  const CommuteAlarm({
    required this.id,
    required this.departureHour,
    required this.departureMinute,
    required this.stopId,
    required this.stopName,
    required this.transitMode,
    required this.routeLabel,
    required this.weekdays,
    required this.lat,
    required this.lon,
    this.wifiSsid,
    this.specificDate,
    this.isActive = true,
    this.tripGroupId,
  });

  final String id;
  final int departureHour;    // 0–23
  final int departureMinute;  // 0–59
  final String stopId;
  final String stopName;
  final String transitMode;
  final String routeLabel;
  final List<int> weekdays;   // 1=Mon … 7=Sun; empty when specificDate is set
  final double lat;
  final double lon;
  final String? wifiSsid;     // non-null → underground Wi-Fi sensing
  final String? specificDate; // "yyyy-MM-dd"; null → use weekdays
  final bool isActive;
  final String? tripGroupId;  // non-null → alarm fires all legs of this group

  // ── Derived display helpers ────────────────────────────────────────────────

  String get timeLabel {
    final h12 = departureHour == 0 ? 12
        : departureHour > 12 ? departureHour - 12
        : departureHour;
    final amPm = departureHour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:'
        '${departureMinute.toString().padLeft(2, '0')} $amPm';
  }

  String get modeEmoji {
    switch (transitMode) {
      case 'underground': return '🚇';
      case 'dlr':         return '🚈';
      case 'overground':  return '🚆';
      case 'tram':        return '🚊';
      case 'train':       return '🚂';
      case 'ferry':       return '⛴';
      default:            return '🚌';
    }
  }

  List<DayChip> get dayChips {
    if (specificDate != null) return [];
    const labels = {1: 'M', 2: 'T', 3: 'W', 4: 'Th', 5: 'F', 6: 'Sa', 7: 'Su'};
    return List.generate(7, (i) {
      final day = i + 1;
      return DayChip(label: labels[day]!, active: weekdays.contains(day));
    });
  }

  String get specificDateLabel {
    if (specificDate == null) return '';
    try {
      final d = DateTime.parse(specificDate!);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return 'Only on ${months[d.month]} ${d.day}';
    } catch (_) {
      return specificDate!;
    }
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id':               id,
        'departure_hour':   departureHour,
        'departure_minute': departureMinute,
        'stop_id':          stopId,
        'stop_name':        stopName,
        'transit_mode':     transitMode,
        'route_label':      routeLabel,
        'weekdays':         jsonEncode(weekdays),
        'lat':              lat,
        'lon':              lon,
        'wifi_ssid':        wifiSsid,
        'specific_date':    specificDate,
        'is_active':        isActive ? 1 : 0,
        'trip_group_id':    tripGroupId,
      };

  factory CommuteAlarm.fromMap(Map<String, dynamic> m) {
    final List<dynamic> decoded =
        jsonDecode(m['weekdays'] as String? ?? '[]') as List;
    return CommuteAlarm(
      id:              m['id']               as String,
      departureHour:   m['departure_hour']   as int,
      departureMinute: m['departure_minute'] as int,
      stopId:          m['stop_id']          as String,
      stopName:        m['stop_name']        as String,
      transitMode:     m['transit_mode']     as String,
      routeLabel:      m['route_label']      as String,
      weekdays:        decoded.cast<int>(),
      lat:             (m['lat']  as num?)?.toDouble() ?? 0.0,
      lon:             (m['lon']  as num?)?.toDouble() ?? 0.0,
      wifiSsid:        m['wifi_ssid']        as String?,
      specificDate:    m['specific_date']    as String?,
      isActive:        (m['is_active']       as int) == 1,
      tripGroupId:     m['trip_group_id']    as String?,
    );
  }

  CommuteAlarm copyWith({
    String? id,
    int? departureHour,
    int? departureMinute,
    String? stopId,
    String? stopName,
    String? transitMode,
    String? routeLabel,
    List<int>? weekdays,
    double? lat,
    double? lon,
    String? wifiSsid,
    String? specificDate,
    bool? isActive,
    String? tripGroupId,
    bool clearSpecificDate = false,
    bool clearTripGroupId  = false,
  }) =>
      CommuteAlarm(
        id:              id              ?? this.id,
        departureHour:   departureHour   ?? this.departureHour,
        departureMinute: departureMinute ?? this.departureMinute,
        stopId:          stopId          ?? this.stopId,
        stopName:        stopName        ?? this.stopName,
        transitMode:     transitMode     ?? this.transitMode,
        routeLabel:      routeLabel      ?? this.routeLabel,
        weekdays:        weekdays        ?? this.weekdays,
        lat:             lat             ?? this.lat,
        lon:             lon             ?? this.lon,
        wifiSsid:        wifiSsid        ?? this.wifiSsid,
        specificDate:    clearSpecificDate  ? null : (specificDate ?? this.specificDate),
        isActive:        isActive        ?? this.isActive,
        tripGroupId:     clearTripGroupId   ? null : (tripGroupId ?? this.tripGroupId),
      );

  @override
  List<Object?> get props => [
        id, departureHour, departureMinute, stopId, stopName,
        transitMode, routeLabel, weekdays, lat, lon, wifiSsid,
        specificDate, isActive, tripGroupId,
      ];
}

class DayChip {
  const DayChip({required this.label, required this.active});
  final String label;
  final bool active;
}
