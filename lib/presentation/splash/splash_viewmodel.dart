import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

enum SplashPhase { waiting, permissions, ready }

class SplashState extends Equatable {
  const SplashState({
    this.phase = SplashPhase.waiting,
    this.locationGranted = false,
    this.bgLocationGranted = false,
    this.notifGranted = false,
    this.batteryGranted = false,
    this.fullScreenIntentGranted = true,
  });

  final SplashPhase phase;
  final bool locationGranted;
  final bool bgLocationGranted;
  final bool notifGranted;
  final bool batteryGranted;
  final bool fullScreenIntentGranted;

  SplashState copyWith({
    SplashPhase? phase,
    bool? locationGranted,
    bool? bgLocationGranted,
    bool? notifGranted,
    bool? batteryGranted,
    bool? fullScreenIntentGranted,
  }) =>
      SplashState(
        phase:                   phase                   ?? this.phase,
        locationGranted:         locationGranted         ?? this.locationGranted,
        bgLocationGranted:       bgLocationGranted       ?? this.bgLocationGranted,
        notifGranted:            notifGranted            ?? this.notifGranted,
        batteryGranted:          batteryGranted          ?? this.batteryGranted,
        fullScreenIntentGranted: fullScreenIntentGranted ?? this.fullScreenIntentGranted,
      );

  @override
  List<Object?> get props => [
        phase,
        locationGranted,
        bgLocationGranted,
        notifGranted,
        batteryGranted,
        fullScreenIntentGranted,
      ];
}

// ── Cubit ─────────────────────────────────────────────────────────────────

class SplashCubit extends Cubit<SplashState> {
  SplashCubit() : super(const SplashState());

  final _platform = PlatformChannelService.instance;

  Future<void> checkPermissions() async {
    final locWhenInUse     = await Permission.locationWhenInUse.isGranted;
    final locAlways        = await Permission.locationAlways.isGranted;
    final notif            = await Permission.notification.isGranted;
    final bat              = await Permission.ignoreBatteryOptimizations.isGranted;
    final fullScreenIntent = await _platform.checkFullScreenIntentPermission();

    emit(state.copyWith(
      locationGranted:         locWhenInUse || locAlways,
      bgLocationGranted:       locAlways,
      notifGranted:            notif,
      batteryGranted:          bat,
      fullScreenIntentGranted: fullScreenIntent,
    ));

    if (locAlways && notif && fullScreenIntent) {
      emit(state.copyWith(phase: SplashPhase.ready));
    } else {
      emit(state.copyWith(phase: SplashPhase.permissions));
    }
  }

  Future<void> requestPermissions() async {
    final locWhenInUse = await Permission.locationWhenInUse.request();

    bool locAlways = await Permission.locationAlways.isGranted;
    if (locWhenInUse.isGranted && !locAlways) {
      await Permission.locationAlways.request();
      locAlways = await Permission.locationAlways.isGranted;
    }

    final notif = (await Permission.notification.request()).isGranted;
    final bat   = (await Permission.ignoreBatteryOptimizations.request()).isGranted;

    bool fullScreen = await _platform.checkFullScreenIntentPermission();
    if (!fullScreen) {
      await _platform.requestFullScreenIntentPermission();
      fullScreen = await _platform.checkFullScreenIntentPermission();
    }

    emit(state.copyWith(
      locationGranted:         locWhenInUse.isGranted || locAlways,
      bgLocationGranted:       locAlways,
      notifGranted:            notif,
      batteryGranted:          bat,
      fullScreenIntentGranted: fullScreen,
    ));

    if ((locWhenInUse.isGranted || locAlways) && notif) {
      emit(state.copyWith(phase: SplashPhase.ready));
    }
  }

  void skipPermissions() => emit(state.copyWith(phase: SplashPhase.ready));
}
