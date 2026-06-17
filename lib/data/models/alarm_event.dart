class AlarmEvent {
  const AlarmEvent({
    required this.id,
    required this.stopId,
    required this.stopName,
    required this.firedAt,
    required this.distanceMetres,
  });

  final String   id;
  final String   stopId;
  final String   stopName;
  final DateTime firedAt;
  final double   distanceMetres;

  factory AlarmEvent.fromMap(Map<String, dynamic> m) => AlarmEvent(
        id:             m['id']           as String,
        stopId:         m['stop_id']      as String,
        stopName:       m['stop_name']    as String,
        firedAt:        DateTime.parse(m['fired_at'] as String),
        distanceMetres: (m['distance_metres'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id':              id,
        'stop_id':         stopId,
        'stop_name':       stopName,
        'fired_at':        firedAt.toIso8601String(),
        'distance_metres': distanceMetres,
      };
}
