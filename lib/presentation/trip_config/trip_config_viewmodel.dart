import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';
import '../../data/models/trip_leg.dart';

// ── State ──────────────────────────────────────────────────────────────────

class TripConfigState extends Equatable {
  const TripConfigState({this.legs = const []});

  final List<TripLeg> legs;

  bool get hasLegs => legs.isNotEmpty;

  TripConfigState copyWith({List<TripLeg>? legs}) =>
      TripConfigState(legs: legs ?? this.legs);

  @override
  List<Object?> get props => [legs];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class TripConfigCubit extends Cubit<TripConfigState> {
  TripConfigCubit() : super(const TripConfigState());

  void addLeg(StopPoint stop) =>
      emit(state.copyWith(legs: [...state.legs, TripLeg(stop: stop)]));

  void removeLeg(int index) {
    final legs = [...state.legs]..removeAt(index);
    emit(state.copyWith(legs: legs));
  }

  void reorderLegs(int oldIndex, int newIndex) {
    final legs = [...state.legs];
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final leg = legs.removeAt(oldIndex);
    legs.insert(adjusted, leg);
    emit(state.copyWith(legs: legs));
  }

  void updateRadius(int index, double metres) {
    final legs = [...state.legs];
    legs[index] = legs[index].copyWith(wakeRadiusMetres: metres);
    emit(state.copyWith(legs: legs));
  }

  void updateAlarmStyle(int index, AlarmStyle style) {
    final legs = [...state.legs];
    legs[index] = legs[index].copyWith(alarmStyle: style);
    emit(state.copyWith(legs: legs));
  }

  void clear() => emit(const TripConfigState());

  List<TripLeg> buildArmedLegs() {
    if (state.legs.isEmpty) return [];
    return [
      state.legs.first.copyWith(status: LegStatus.active),
      ...state.legs.skip(1).map((l) => l.copyWith(status: LegStatus.queued)),
    ];
  }
}
