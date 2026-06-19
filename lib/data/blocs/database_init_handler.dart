import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/stop_points_db.dart';

// ── Events ────────────────────────────────────────────────────────────────────

abstract class DatabaseInitEvent {
  const DatabaseInitEvent();
}

/// Dispatched automatically when the BLoC is created (see app_router.dart).
class CheckDatabaseOnBootEvent extends DatabaseInitEvent {
  const CheckDatabaseOnBootEvent();
}

/// Fired internally as the decompression isolate sends progress updates.
class DecompressionProgressUpdatedEvent extends DatabaseInitEvent {
  const DecompressionProgressUpdatedEvent(this.progressPercentage);
  final double progressPercentage;
}

// ── States ────────────────────────────────────────────────────────────────────

abstract class DatabaseInitState {
  const DatabaseInitState();
}

class DatabaseInitialState extends DatabaseInitState {
  const DatabaseInitialState();
}

class DatabaseDecompressingState extends DatabaseInitState {
  const DatabaseDecompressingState(this.progressPercentage);
  final double progressPercentage;
}

class DatabaseReadyState extends DatabaseInitState {
  const DatabaseReadyState();
}

class DatabaseErrorState extends DatabaseInitState {
  const DatabaseErrorState(this.errorMessage);
  final String errorMessage;
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class DatabaseInitHandler extends Bloc<DatabaseInitEvent, DatabaseInitState> {
  DatabaseInitHandler({StopPointsDb? db})
      : _db = db ?? StopPointsDb.instance,
        super(const DatabaseInitialState()) {
    on<CheckDatabaseOnBootEvent>(_onCheckDatabase);
    on<DecompressionProgressUpdatedEvent>(_onProgressUpdated);
  }

  final StopPointsDb _db;

  Future<void> _onCheckDatabase(
    CheckDatabaseOnBootEvent event,
    Emitter<DatabaseInitState> emit,
  ) async {
    if (_db.isReady) {
      emit(const DatabaseReadyState());
      return;
    }
    emit(const DatabaseDecompressingState(0.0));
    try {
      await _db.initialize(
        onProgress: (p) => add(DecompressionProgressUpdatedEvent(p)),
      );
      emit(const DatabaseReadyState());
    } catch (e) {
      emit(DatabaseErrorState(e.toString()));
    }
  }

  void _onProgressUpdated(
    DecompressionProgressUpdatedEvent event,
    Emitter<DatabaseInitState> emit,
  ) {
    emit(DatabaseDecompressingState(event.progressPercentage));
  }
}
