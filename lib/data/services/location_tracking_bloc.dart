import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/stop_point.dart';
import '../models/trip_leg.dart';

// ── Events ────────────────────────────────────────────────────────────────

abstract class LocationTrackingEvent extends Equatable {
  const LocationTrackingEvent();
  @override
  List<Object?> get props => [];
}

class InitializeDatabaseEvent extends LocationTrackingEvent {
  const InitializeDatabaseEvent();
}

class StartPlaylistTrackingEvent extends LocationTrackingEvent {
  const StartPlaylistTrackingEvent(this.queue);
  final List<StopPoint> queue;
  @override
  List<Object?> get props => [queue];
}

class TransitionToNextLegEvent extends LocationTrackingEvent {
  const TransitionToNextLegEvent();
}

class HardwareAlarmTriggeredEvent extends LocationTrackingEvent {
  const HardwareAlarmTriggeredEvent({
    required this.stopId,
    required this.stopName,
    required this.distanceMetres,
  });
  final String stopId;
  final String stopName;
  final double distanceMetres;
  @override
  List<Object?> get props => [stopId, stopName, distanceMetres];
}

class DismissActiveAlarmEvent extends LocationTrackingEvent {
  const DismissActiveAlarmEvent();
}

// ── States ────────────────────────────────────────────────────────────────

abstract class LocationTrackingState extends Equatable {
  const LocationTrackingState();
  @override
  List<Object?> get props => [];
}

class LocationInitialState extends LocationTrackingState {
  const LocationInitialState();
}

class DatabaseDecompressingState extends LocationTrackingState {
  const DatabaseDecompressingState(this.progress);
  final double progress;
  @override
  List<Object?> get props => [progress];
}

class LocationIdleState extends LocationTrackingState {
  const LocationIdleState();
}

class AboveGroundTrackingActiveState extends LocationTrackingState {
  const AboveGroundTrackingActiveState(this.activeLeg);
  final TripLeg activeLeg;
  @override
  List<Object?> get props => [activeLeg];
}

class SubterraneanSensingActiveState extends LocationTrackingState {
  const SubterraneanSensingActiveState(this.activeLeg);
  final TripLeg activeLeg;
  @override
  List<Object?> get props => [activeLeg];
}

class AlarmTriggeredState extends LocationTrackingState {
  const AlarmTriggeredState({
    required this.stop,
    required this.distanceMetres,
  });
  final StopPoint stop;
  final double distanceMetres;
  @override
  List<Object?> get props => [stop, distanceMetres];
}

// ── Bloc ──────────────────────────────────────────────────────────────────

class LocationTrackingBloc
    extends Bloc<LocationTrackingEvent, LocationTrackingState> {
  LocationTrackingBloc() : super(const LocationInitialState()) {
    on<InitializeDatabaseEvent>(_onInitialize);
    on<StartPlaylistTrackingEvent>(_onStartPlaylist);
    on<TransitionToNextLegEvent>(_onTransition);
    on<HardwareAlarmTriggeredEvent>(_onAlarmTriggered);
    on<DismissActiveAlarmEvent>(_onDismiss);

    _bindNativeAlarmStream();
  }

  static const _methodChannel = MethodChannel('com.stopsnoozer.app/location');
  static const _alarmChannel  = EventChannel('com.stopsnoozer.app/alarm_stream');

  StreamSubscription<dynamic>? _alarmSub;
  List<TripLeg> _queue = [];
  int _currentIndex = 0;

  // Pipe native EventChannel directly into bloc as HardwareAlarmTriggeredEvent
  void _bindNativeAlarmStream() {
    _alarmSub = _alarmChannel.receiveBroadcastStream().listen((event) {
      final data = Map<String, dynamic>.from(event as Map);
      add(HardwareAlarmTriggeredEvent(
        stopId: data['stopId'] as String? ?? '',
        stopName: data['stopName'] as String? ?? 'Your Stop',
        distanceMetres: (data['distanceMetres'] as num?)?.toDouble() ?? 0.0,
      ));
    });
  }

  Future<void> _onInitialize(
    InitializeDatabaseEvent event,
    Emitter<LocationTrackingState> emit,
  ) async {
    for (var p = 0.0; p <= 1.0; p += 0.1) {
      emit(DatabaseDecompressingState(p));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    emit(const LocationIdleState());
  }

  Future<void> _onStartPlaylist(
    StartPlaylistTrackingEvent event,
    Emitter<LocationTrackingState> emit,
  ) async {
    if (event.queue.isEmpty) return;
    _queue = event.queue
        .map((s) => TripLeg(stop: s))
        .toList();
    _currentIndex = 0;
    await _activateLeg(emit);
  }

  Future<void> _activateLeg(Emitter<LocationTrackingState> emit) async {
    if (_currentIndex >= _queue.length) {
      emit(const LocationIdleState());
      return;
    }
    final leg  = _queue[_currentIndex];
    final stop = leg.stop;

    if (stop.wifiSsid != null) {
      emit(SubterraneanSensingActiveState(leg));
      try {
        await _methodChannel.invokeMethod<void>('startUndergroundTracking', {
          'id': stop.id,
          'targetSsid': stop.wifiSsid,
          'targetName': stop.name,
        });
      } on PlatformException catch (_) {}
    } else {
      emit(AboveGroundTrackingActiveState(leg));
      try {
        await _methodChannel.invokeMethod<void>('startAboveGroundTracking', {
          'id': stop.id,
          'lat': stop.latitude,
          'lng': stop.longitude,
          'radius': leg.wakeRadiusMetres,
        });
      } on PlatformException catch (_) {}
    }
  }

  Future<void> _onTransition(
    TransitionToNextLegEvent event,
    Emitter<LocationTrackingState> emit,
  ) async {
    _currentIndex++;
    await _activateLeg(emit);
  }

  void _onAlarmTriggered(
    HardwareAlarmTriggeredEvent event,
    Emitter<LocationTrackingState> emit,
  ) {
    final stop = _currentIndex < _queue.length
        ? _queue[_currentIndex].stop
        : StopPoint(
            id: event.stopId,
            name: event.stopName,
            latitude: 0,
            longitude: 0,
            mode: TransitMode.tube,
          );
    emit(AlarmTriggeredState(stop: stop, distanceMetres: event.distanceMetres));
  }

  void _onDismiss(
    DismissActiveAlarmEvent event,
    Emitter<LocationTrackingState> emit,
  ) {
    try {
      _methodChannel.invokeMethod<void>('stopActiveTracking');
    } on PlatformException catch (_) {}
    emit(const LocationIdleState());
  }

  @override
  Future<void> close() {
    _alarmSub?.cancel();
    return super.close();
  }
}
