import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';

// ── State ──────────────────────────────────────────────────────────────────

class AlarmState extends Equatable {
  const AlarmState({
    required this.stop,
    required this.distanceMetres,
    this.slideProgress = 0.0,
    this.isDismissed = false,
  });

  final StopPoint stop;
  final double distanceMetres;
  final double slideProgress;
  final bool isDismissed;

  AlarmState copyWith({
    StopPoint? stop,
    double? distanceMetres,
    double? slideProgress,
    bool? isDismissed,
  }) =>
      AlarmState(
        stop: stop ?? this.stop,
        distanceMetres: distanceMetres ?? this.distanceMetres,
        slideProgress: slideProgress ?? this.slideProgress,
        isDismissed: isDismissed ?? this.isDismissed,
      );

  @override
  List<Object?> get props => [stop, distanceMetres, slideProgress, isDismissed];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class AlarmCubit extends Cubit<AlarmState> {
  AlarmCubit({required StopPoint stop, required double distanceMetres})
      : super(AlarmState(stop: stop, distanceMetres: distanceMetres));

  void updateDistance(double metres) =>
      emit(state.copyWith(distanceMetres: metres));

  void updateSlideProgress(double progress) =>
      emit(state.copyWith(slideProgress: progress.clamp(0.0, 1.0)));

  void dismiss() =>
      emit(state.copyWith(isDismissed: true, slideProgress: 1.0));
}
