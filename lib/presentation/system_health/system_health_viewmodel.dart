import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

enum SensorStatus { online, standby, unavailable }

class SystemHealthState extends Equatable {
  const SystemHealthState({
    this.selectedTab = 2,
    this.gpsStatus = SensorStatus.online,
    this.wifiStatus = SensorStatus.standby,
    this.deadRecStatus = SensorStatus.online,
    this.batteryOptimizationGranted = false,
    this.dndBypassEnabled = true,
    this.isRequestingBattery = false,
  });

  final int selectedTab;
  final SensorStatus gpsStatus;
  final SensorStatus wifiStatus;
  final SensorStatus deadRecStatus;
  final bool batteryOptimizationGranted;
  final bool dndBypassEnabled;
  final bool isRequestingBattery;

  SystemHealthState copyWith({
    int? selectedTab,
    SensorStatus? gpsStatus,
    SensorStatus? wifiStatus,
    SensorStatus? deadRecStatus,
    bool? batteryOptimizationGranted,
    bool? dndBypassEnabled,
    bool? isRequestingBattery,
  }) =>
      SystemHealthState(
        selectedTab: selectedTab ?? this.selectedTab,
        gpsStatus: gpsStatus ?? this.gpsStatus,
        wifiStatus: wifiStatus ?? this.wifiStatus,
        deadRecStatus: deadRecStatus ?? this.deadRecStatus,
        batteryOptimizationGranted:
            batteryOptimizationGranted ?? this.batteryOptimizationGranted,
        dndBypassEnabled: dndBypassEnabled ?? this.dndBypassEnabled,
        isRequestingBattery: isRequestingBattery ?? this.isRequestingBattery,
      );

  @override
  List<Object?> get props => [
        selectedTab, gpsStatus, wifiStatus, deadRecStatus,
        batteryOptimizationGranted, dndBypassEnabled, isRequestingBattery,
      ];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class SystemHealthCubit extends Cubit<SystemHealthState> {
  SystemHealthCubit({PlatformChannelService? platform})
      : _platform = platform ?? PlatformChannelService.instance,
        super(const SystemHealthState());

  final PlatformChannelService _platform;

  void selectTab(int index) => emit(state.copyWith(selectedTab: index));

  Future<void> requestBatteryOptimization() async {
    emit(state.copyWith(isRequestingBattery: true));
    final granted = await _platform.requestBatteryOptimizationExemption();
    emit(state.copyWith(
      isRequestingBattery: false,
      batteryOptimizationGranted: granted,
    ));
  }

  void toggleDndBypass() =>
      emit(state.copyWith(dndBypassEnabled: !state.dndBypassEnabled));

  void refreshSensors() {
    emit(state.copyWith(
      gpsStatus: SensorStatus.online,
      wifiStatus: SensorStatus.standby,
      deadRecStatus: SensorStatus.online,
    ));
  }
}
