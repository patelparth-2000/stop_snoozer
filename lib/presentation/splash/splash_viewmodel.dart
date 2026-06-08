import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/database_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

enum SplashPhase { decompressing, permissions, ready, error }

class SplashState extends Equatable {
  const SplashState({
    this.phase = SplashPhase.decompressing,
    this.progress = 0.0,
    this.locationGranted = false,
    this.notifGranted = false,
    this.batteryGranted = false,
    this.errorMessage,
  });

  final SplashPhase phase;
  final double progress;
  final bool locationGranted;
  final bool notifGranted;
  final bool batteryGranted;
  final String? errorMessage;

  SplashState copyWith({
    SplashPhase? phase,
    double? progress,
    bool? locationGranted,
    bool? notifGranted,
    bool? batteryGranted,
    String? errorMessage,
  }) =>
      SplashState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        locationGranted: locationGranted ?? this.locationGranted,
        notifGranted: notifGranted ?? this.notifGranted,
        batteryGranted: batteryGranted ?? this.batteryGranted,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  @override
  List<Object?> get props =>
      [phase, progress, locationGranted, notifGranted, batteryGranted, errorMessage];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class SplashCubit extends Cubit<SplashState> {
  SplashCubit({DatabaseService? db})
      : _db = db ?? DatabaseService.instance,
        super(const SplashState());

  final DatabaseService _db;

  Future<void> initialize() async {
    emit(state.copyWith(phase: SplashPhase.decompressing, progress: 0.0));
    try {
      await _db.initialize(onProgress: (p) {
        emit(state.copyWith(progress: p));
      });
      await _checkPermissions();
      emit(state.copyWith(phase: SplashPhase.permissions));
    } catch (e) {
      emit(state.copyWith(phase: SplashPhase.error, errorMessage: e.toString()));
    }
  }

  Future<void> _checkPermissions() async {
    final loc  = await Permission.locationWhenInUse.isGranted ||
        await Permission.locationAlways.isGranted;
    final notif = await Permission.notification.isGranted;
    final bat  = await Permission.ignoreBatteryOptimizations.isGranted;
    emit(state.copyWith(
      locationGranted: loc,
      notifGranted: notif,
      batteryGranted: bat,
    ));
  }

  Future<void> requestPermissions() async {
    final loc   = (await Permission.locationWhenInUse.request()).isGranted;
    final notif = (await Permission.notification.request()).isGranted;
    final bat   = (await Permission.ignoreBatteryOptimizations.request()).isGranted;
    emit(state.copyWith(
      locationGranted: loc,
      notifGranted: notif,
      batteryGranted: bat,
    ));
    if (loc && notif) emit(state.copyWith(phase: SplashPhase.ready));
  }

  void skipPermissions() => emit(state.copyWith(phase: SplashPhase.ready));
}
