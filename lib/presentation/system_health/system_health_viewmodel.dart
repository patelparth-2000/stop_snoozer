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
    this.undergroundStatus = SensorStatus.standby,
    this.batteryOptimizationGranted = false,
    this.dndBypassEnabled = true,
    this.isRequestingBattery = false,
  });

  final int selectedTab;
  final SensorStatus gpsStatus;
  final SensorStatus wifiStatus;
  /// Reflects whether Wi-Fi scanning for underground stop detection is available.
  final SensorStatus undergroundStatus;
  final bool batteryOptimizationGranted;
  final bool dndBypassEnabled;
  final bool isRequestingBattery;

  SystemHealthState copyWith({
    int? selectedTab,
    SensorStatus? gpsStatus,
    SensorStatus? wifiStatus,
    SensorStatus? undergroundStatus,
    bool? batteryOptimizationGranted,
    bool? dndBypassEnabled,
    bool? isRequestingBattery,
  }) =>
      SystemHealthState(
        selectedTab:               selectedTab               ?? this.selectedTab,
        gpsStatus:                 gpsStatus                 ?? this.gpsStatus,
        wifiStatus:                wifiStatus                ?? this.wifiStatus,
        undergroundStatus:         undergroundStatus         ?? this.undergroundStatus,
        batteryOptimizationGranted:
            batteryOptimizationGranted ?? this.batteryOptimizationGranted,
        dndBypassEnabled:          dndBypassEnabled          ?? this.dndBypassEnabled,
        isRequestingBattery:       isRequestingBattery       ?? this.isRequestingBattery,
      );

  @override
  List<Object?> get props => [
        selectedTab, gpsStatus, wifiStatus, undergroundStatus,
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

  Future<void> init() async {
    final batteryGranted = await _platform.checkBatteryOptimizationStatus();
    final wifiOn         = await _platform.checkWifiEnabled();
    emit(state.copyWith(
      batteryOptimizationGranted: batteryGranted,
      wifiStatus:       wifiOn ? SensorStatus.online   : SensorStatus.standby,
      undergroundStatus: wifiOn ? SensorStatus.online  : SensorStatus.standby,
    ));
  }

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
}
