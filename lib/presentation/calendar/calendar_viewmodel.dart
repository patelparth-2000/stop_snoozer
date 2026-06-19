import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/alarm_event.dart';
import '../../data/models/commute_alarm.dart';
import '../../data/repositories/alarm_history_repository.dart';
import '../../data/repositories/commute_alarms_repository.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

class CommuteAlarmsState extends Equatable {
  const CommuteAlarmsState({
    this.alarms = const [],
    this.history = const [],
    this.isLoading = true,
  });

  final List<CommuteAlarm> alarms;
  final List<AlarmEvent>   history;
  final bool               isLoading;

  CommuteAlarmsState copyWith({
    List<CommuteAlarm>? alarms,
    List<AlarmEvent>?   history,
    bool?               isLoading,
  }) =>
      CommuteAlarmsState(
        alarms:    alarms    ?? this.alarms,
        history:   history   ?? this.history,
        isLoading: isLoading ?? this.isLoading,
      );

  @override
  List<Object?> get props => [alarms, history, isLoading];
}

// ── Cubit ──────────────────────────────────────────────────────────────────

class CommuteAlarmsCubit extends Cubit<CommuteAlarmsState> {
  CommuteAlarmsCubit({CommuteAlarmsRepository? repo})
      : _repo = repo ?? CommuteAlarmsRepository.instance,
        _platform = PlatformChannelService.instance,
        super(const CommuteAlarmsState());

  final CommuteAlarmsRepository _repo;
  final PlatformChannelService  _platform;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final results = await Future.wait([
      _repo.loadAll(),
      AlarmHistoryRepository.instance.loadRecent(),
    ]);
    emit(state.copyWith(
      alarms:    results[0] as List<CommuteAlarm>,
      history:   results[1] as List<AlarmEvent>,
      isLoading: false,
    ));
  }

  Future<void> clearHistory() async {
    await AlarmHistoryRepository.instance.clear();
    emit(state.copyWith(history: []));
  }

  Future<void> add(CommuteAlarm alarm) async {
    await _repo.insert(alarm);
    if (alarm.isActive) await _scheduleNative(alarm);
    final updated = [...state.alarms, alarm]
      ..sort((a, b) {
        final aMin = a.departureHour * 60 + a.departureMinute;
        final bMin = b.departureHour * 60 + b.departureMinute;
        return aMin.compareTo(bMin);
      });
    emit(state.copyWith(alarms: updated));
  }

  Future<void> toggle(String id) async {
    final index = state.alarms.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final updated = state.alarms[index].copyWith(
      isActive: !state.alarms[index].isActive,
    );
    await _repo.update(updated);
    if (updated.isActive) {
      await _scheduleNative(updated);
    } else {
      await _platform.cancelCommuteAlarm(updated.id);
    }
    final list = [...state.alarms];
    list[index] = updated;
    emit(state.copyWith(alarms: list));
  }

  Future<void> delete(String id) async {
    await _platform.cancelCommuteAlarm(id);
    await _repo.delete(id);
    emit(state.copyWith(
      alarms: state.alarms.where((a) => a.id != id).toList(),
    ));
  }

  Future<void> updateAlarm(CommuteAlarm alarm) async {
    await _repo.update(alarm);
    await _platform.cancelCommuteAlarm(alarm.id);
    if (alarm.isActive) await _scheduleNative(alarm);
    final list = [...state.alarms];
    final idx  = list.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) list[idx] = alarm;
    list.sort((a, b) {
      final aMin = a.departureHour * 60 + a.departureMinute;
      final bMin = b.departureHour * 60 + b.departureMinute;
      return aMin.compareTo(bMin);
    });
    emit(state.copyWith(alarms: list));
  }

  Future<void> _scheduleNative(CommuteAlarm a) => _platform.scheduleCommuteAlarm(
        alarmId:      a.id,
        hour:         a.departureHour,
        minute:       a.departureMinute,
        stopId:       a.stopId,
        stopName:     a.stopName,
        lat:          a.lat,
        lon:          a.lon,
        ssid:         a.wifiSsid,
        weekdays:     a.weekdays,
        specificDate: a.specificDate,
        tripGroupId:  a.tripGroupId,
      );
}
