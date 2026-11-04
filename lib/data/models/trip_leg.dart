import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';
import 'stop_point.dart';

enum AlarmStyle { subtlePulse, defconDrill }

enum LegStatus { queued, active, complete }

class TripLeg extends Equatable {
  const TripLeg({
    required this.stop,
    this.wakeRadiusMetres = AppConstants.defaultWakeRadiusMetres,
    this.alarmStyle = AlarmStyle.defconDrill,
    this.status = LegStatus.queued,
  });

  final StopPoint stop;
  final double wakeRadiusMetres;
  final AlarmStyle alarmStyle;
  final LegStatus status;

  TripLeg copyWith({
    StopPoint? stop,
    double? wakeRadiusMetres,
    AlarmStyle? alarmStyle,
    LegStatus? status,
  }) =>
      TripLeg(
        stop: stop ?? this.stop,
        wakeRadiusMetres: wakeRadiusMetres ?? this.wakeRadiusMetres,
        alarmStyle: alarmStyle ?? this.alarmStyle,
        status: status ?? this.status,
      );

  /// The shape the native service's route takes for one stop
  /// (see SnoozeTrackingService.TargetStop.fromJson).
  Map<String, dynamic> toNativeRouteLeg() => <String, dynamic>{
        'stopId':       stop.id,
        'stopName':     stop.name,
        'lat':          stop.latitude,
        'lon':          stop.longitude,
        'radiusMetres': wakeRadiusMetres,
        'alarmStyle':   alarmStyle == AlarmStyle.subtlePulse
            ? 'subtlePulse'
            : 'defconDrill',
        'mode':         stop.mode.name,
        if (stop.wifiSsid != null) 'ssid': stop.wifiSsid!,
      };

  @override
  List<Object?> get props => [stop, wakeRadiusMetres, alarmStyle, status];
}
