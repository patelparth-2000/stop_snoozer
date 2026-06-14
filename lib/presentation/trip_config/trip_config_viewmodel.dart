import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/stop_point.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_group.dart';
import '../../data/repositories/trip_groups_repository.dart';

// ── Queue mode ─────────────────────────────────────────────────────────────

enum QueueMode { singleStop, tripGroup }

// ── State ──────────────────────────────────────────────────────────────────

class TripConfigState extends Equatable {
  const TripConfigState({
    this.legs = const [],
    this.savedGroups = const [],
    this.queueMode = QueueMode.singleStop,
  });

  final List<TripLeg>   legs;
  final List<TripGroup> savedGroups;
  final QueueMode       queueMode;

  bool get hasLegs => legs.isNotEmpty;

  TripConfigState copyWith({
    List<TripLeg>?   legs,
    List<TripGroup>? savedGroups,
    QueueMode?       queueMode,
  }) =>
      TripConfigState(
        legs:        legs        ?? this.legs,
        savedGroups: savedGroups ?? this.savedGroups,
        queueMode:   queueMode   ?? this.queueMode,
      );

  @override
  List<Object?> get props => [legs, savedGroups, queueMode];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class TripConfigCubit extends Cubit<TripConfigState> {
  TripConfigCubit() : super(const TripConfigState()) {
    _loadGroups();
  }

  final _groupsRepo = TripGroupsRepository.instance;

  Future<void> _loadGroups() async {
    final groups = await _groupsRepo.loadAll();
    emit(state.copyWith(savedGroups: groups));
  }

  void setQueueMode(QueueMode mode) => emit(state.copyWith(queueMode: mode));

  void addLeg(StopPoint stop) =>
      emit(state.copyWith(legs: [...state.legs, TripLeg(stop: stop)]));

  void removeLeg(int index) {
    final legs = [...state.legs]..removeAt(index);
    emit(state.copyWith(legs: legs));
  }

  void reorderLegs(int oldIndex, int newIndex) {
    final legs     = [...state.legs];
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final leg      = legs.removeAt(oldIndex);
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

  void clear() => emit(state.copyWith(legs: []));

  /// Saves the current queue as a named trip group.
  Future<void> saveCurrentAsGroup(String name) async {
    if (state.legs.isEmpty) return;
    final group = TripGroup(
      id:   const Uuid().v4(),
      name: name.trim().isEmpty ? 'Trip ${state.savedGroups.length + 1}' : name.trim(),
      legs: state.legs.map((l) => l.copyWith(status: LegStatus.queued)).toList(),
    );
    await _groupsRepo.save(group);
    emit(state.copyWith(savedGroups: [...state.savedGroups, group]));
  }

  /// Loads a saved group and auto-switches to Single Stop mode so the user
  /// can immediately see, reorder, and arm the loaded legs.
  void loadGroup(TripGroup group) {
    emit(state.copyWith(
      legs:      group.legs.map((l) => l.copyWith(status: LegStatus.queued)).toList(),
      queueMode: QueueMode.singleStop,
    ));
  }

  /// Deletes a saved group.
  Future<void> deleteGroup(String id) async {
    await _groupsRepo.delete(id);
    emit(state.copyWith(
      savedGroups: state.savedGroups.where((g) => g.id != id).toList(),
    ));
  }

  List<TripLeg> buildArmedLegs() {
    if (state.legs.isEmpty) return [];
    return [
      state.legs.first.copyWith(status: LegStatus.active),
      ...state.legs.skip(1).map((l) => l.copyWith(status: LegStatus.queued)),
    ];
  }
}
