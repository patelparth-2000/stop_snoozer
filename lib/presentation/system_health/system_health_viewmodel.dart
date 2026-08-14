import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/services/platform_channel_service.dart';

export '../../data/services/platform_channel_service.dart'
    show AlarmDiagnostics;

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
    this.diagnostics = AlarmDiagnostics.empty,
    this.oemName,
    this.oemSettingsAvailable = false,
    this.selfTestState = SelfTestState.idle,
    this.selfTestWasExact = true,
  });

  final int selectedTab;
  final SensorStatus gpsStatus;
  final SensorStatus wifiStatus;
  /// Reflects whether underground (subterranean) detection is available.
  final SensorStatus undergroundStatus;
  final bool batteryOptimizationGranted;
  final bool dndBypassEnabled;
  final bool isRequestingBattery;

  /// Full alarm-reliability snapshot from the native layer (A10).
  final AlarmDiagnostics diagnostics;

  /// Manufacturer label when this device runs an extra background killer (A9).
  final String? oemName;
  final bool oemSettingsAvailable;

  final SelfTestState selfTestState;
  /// False when the self-test could only be scheduled inexactly.
  final bool selfTestWasExact;

  SystemHealthState copyWith({
    int? selectedTab,
    SensorStatus? gpsStatus,
    SensorStatus? wifiStatus,
    SensorStatus? undergroundStatus,
    bool? batteryOptimizationGranted,
    bool? dndBypassEnabled,
    bool? isRequestingBattery,
    AlarmDiagnostics? diagnostics,
    String? oemName,
    bool? oemSettingsAvailable,
    SelfTestState? selfTestState,
    bool? selfTestWasExact,
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
        diagnostics:               diagnostics               ?? this.diagnostics,
        oemName:                   oemName                   ?? this.oemName,
        oemSettingsAvailable:      oemSettingsAvailable      ?? this.oemSettingsAvailable,
        selfTestState:             selfTestState             ?? this.selfTestState,
        selfTestWasExact:          selfTestWasExact          ?? this.selfTestWasExact,
      );

  @override
  List<Object?> get props => [
        selectedTab, gpsStatus, wifiStatus, undergroundStatus,
        batteryOptimizationGranted, dndBypassEnabled, isRequestingBattery,
        diagnostics, oemName, oemSettingsAvailable,
        selfTestState, selfTestWasExact,
      ];
}

/// Lifecycle of the "test your alarm" flow.
enum SelfTestState {
  idle,

  /// Alarm scheduled; waiting for the OS to wake us. The user should background
  /// the app during this window, since that is the failure mode being tested.
  armed,

  /// The alarm fired — the full pipeline works on this device.
  passed,

  /// The scheduled window elapsed with no alarm. Almost always an OEM killer.
  failed,
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
    final diags          = await _platform.getAlarmDiagnostics();
    final oem            = await _platform.getOemBatteryInfo();

    // If a test was armed and has since fired, resolve it now — the alarm may
    // have fired while this screen was backgrounded, which is the whole point.
    var testState = state.selfTestState;
    if (testState == SelfTestState.armed && diags.lastTestPassed) {
      testState = SelfTestState.passed;
    }

    emit(state.copyWith(
      batteryOptimizationGranted: batteryGranted,
      wifiStatus:        wifiOn ? SensorStatus.online : SensorStatus.standby,
      undergroundStatus: wifiOn ? SensorStatus.online : SensorStatus.standby,
      diagnostics:          diags,
      oemName:              oem.oemName,
      oemSettingsAvailable: oem.available,
      selfTestState:        testState,
    ));
  }

  // ── A9: OEM background restrictions ─────────────────────────────────────

  Future<void> openOemBatterySettings() =>
      _platform.openOemBatterySettings();

  // ── A10: "Test your alarm" ──────────────────────────────────────────────

  /// Schedules a real alarm [delaySeconds] out and waits for it.
  ///
  /// Resolution is driven by the native fired-timestamp, not by a local timer
  /// alone: if the OS killed our process the timer would never run, and a
  /// timer-only implementation would wrongly report a pass on relaunch.
  Future<void> runSelfTest({int delaySeconds = 10}) async {
    final exact = await _platform.runAlarmSelfTest(delaySeconds: delaySeconds);
    emit(state.copyWith(
      selfTestState: SelfTestState.armed,
      selfTestWasExact: exact,
    ));

    // Grace period beyond the scheduled delay: inexact alarms and Doze can
    // legitimately add latency, and calling that a failure would be wrong.
    final graceSeconds = exact ? 8 : 60;
    await Future<void>.delayed(Duration(seconds: delaySeconds + graceSeconds));
    if (isClosed) return;

    final diags = await _platform.getAlarmDiagnostics();
    if (isClosed) return;
    emit(state.copyWith(
      diagnostics: diags,
      selfTestState:
          diags.lastTestPassed ? SelfTestState.passed : SelfTestState.failed,
    ));
  }

  Future<void> resetSelfTest() async {
    await _platform.cancelAlarmSelfTest();
    if (isClosed) return;
    emit(state.copyWith(selfTestState: SelfTestState.idle));
  }

  Future<void> requestBatteryOptimization() async {
    emit(state.copyWith(isRequestingBattery: true));
    final granted = await _platform.requestBatteryOptimizationExemption();
    emit(state.copyWith(
      isRequestingBattery: false,
      batteryOptimizationGranted: granted,
    ));
  }

  // toggleDndBypass() was removed deliberately. It only flipped local state and
  // never requested notification-policy access, so it advertised DND bypass the
  // app did not have. It is also unnecessary: the alarm is played with
  // AudioAttributes.USAGE_ALARM, which Android's default Do Not Disturb lets
  // through without any permission. See _DndInfoCard in the screen.
}
