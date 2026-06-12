import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

class AlarmState extends Equatable {
  const AlarmState({
    required this.stop,
    required this.distanceMetres,
    this.slideProgress = 0.0,
    this.isDismissed = false,
    this.isSnoozed = false,
    this.snoozeMinutes = 5,
    this.countdownSeconds = 0,
    this.isRinging = false,
  });

  final StopPoint stop;
  final double distanceMetres;
  final double slideProgress;
  final bool isDismissed;
  final bool isSnoozed;
  final int snoozeMinutes;
  /// Seconds remaining before ringtone starts (0 = already ringing).
  final int countdownSeconds;
  /// True once the 5-second countdown has elapsed and the ringtone is playing.
  final bool isRinging;

  AlarmState copyWith({
    StopPoint? stop,
    double? distanceMetres,
    double? slideProgress,
    bool? isDismissed,
    bool? isSnoozed,
    int? snoozeMinutes,
    int? countdownSeconds,
    bool? isRinging,
  }) =>
      AlarmState(
        stop:             stop             ?? this.stop,
        distanceMetres:   distanceMetres   ?? this.distanceMetres,
        slideProgress:    slideProgress    ?? this.slideProgress,
        isDismissed:      isDismissed      ?? this.isDismissed,
        isSnoozed:        isSnoozed        ?? this.isSnoozed,
        snoozeMinutes:    snoozeMinutes    ?? this.snoozeMinutes,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        isRinging:        isRinging        ?? this.isRinging,
      );

  @override
  List<Object?> get props =>
      [stop, distanceMetres, slideProgress, isDismissed, isSnoozed,
       snoozeMinutes, countdownSeconds, isRinging];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class AlarmCubit extends Cubit<AlarmState> {
  AlarmCubit({
    required StopPoint stop,
    required double distanceMetres,
    int initialCountdown = 0,
    this.onDismissed,
  }) : super(AlarmState(
          stop: stop,
          distanceMetres: distanceMetres,
          countdownSeconds: initialCountdown,
          isRinging: initialCountdown <= 0,
        )) {
    if (initialCountdown > 0) _startCountdown();
  }

  final void Function()? onDismissed;
  Timer? _countdownTimer;

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.countdownSeconds - 1;
      if (remaining <= 0) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        emit(state.copyWith(countdownSeconds: 0, isRinging: true));
      } else {
        emit(state.copyWith(countdownSeconds: remaining));
      }
    });
  }

  void updateDistance(double metres) =>
      emit(state.copyWith(distanceMetres: metres));

  void updateSlideProgress(double progress) =>
      emit(state.copyWith(slideProgress: progress.clamp(0.0, 1.0)));

  void dismiss() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    PlatformChannelService.instance.stopAlarm();
    onDismissed?.call();
    emit(state.copyWith(isDismissed: true, slideProgress: 1.0));
  }

  void snooze({int minutes = 5}) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    PlatformChannelService.instance.snoozeAlarm(minutes: minutes);
    emit(state.copyWith(isSnoozed: true, snoozeMinutes: minutes));
  }

  @override
  Future<void> close() {
    _countdownTimer?.cancel();
    return super.close();
  }
}
