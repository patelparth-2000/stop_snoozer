import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'system_health_viewmodel.dart';
import 'components/health_tab_bar.dart';
import 'components/sensor_status_card.dart';
import 'components/permission_toggle_row.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../shared/widgets/snoozer_button.dart';

class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<SystemHealthCubit, SystemHealthState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => context.pop()),
              const SizedBox(height: AppConstants.spaceMd),
              HealthTabBar(
                selectedIndex: state.selectedTab,
                onTabSelected: context.read<SystemHealthCubit>().selectTab,
              ),
              const SizedBox(height: AppConstants.spaceLg),
              Expanded(
                child: _OptimizersTab(state: state),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppConstants.containerMargin, 0,
                  AppConstants.containerMargin,
                  AppConstants.spaceMd + MediaQuery.of(context).padding.bottom,
                ),
                child: Text(
                  StringConstants.healthVersion,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: ColorConstants.textDisabled,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceMd,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: ColorConstants.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Text(
            StringConstants.healthTitle,
            style: GoogleFonts.sora(
              fontSize: 18, fontWeight: FontWeight.w700, color: ColorConstants.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptimizersTab extends StatelessWidget {
  const _OptimizersTab({required this.state});
  final SystemHealthState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SystemHealthCubit>();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      children: [
        _SectionLabel('OS Bypass Authorization'),
        const SizedBox(height: AppConstants.spaceSm),
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          decoration: BoxDecoration(
            color: ColorConstants.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                StringConstants.healthBatteryTitle,
                style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: ColorConstants.textPrimary),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              SnoozerButton(
                label: state.batteryOptimizationGranted
                    ? 'Whitelist Active'
                    : StringConstants.healthBatteryGrant,
                onTap: state.batteryOptimizationGranted ? null : cubit.requestBatteryOptimization,
                isLoading: state.isRequestingBattery,
                variant: state.batteryOptimizationGranted
                    ? SnoozerButtonVariant.secondary
                    : SnoozerButtonVariant.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceSm),
        PermissionToggleRow(
          label: StringConstants.healthDndTitle,
          description: StringConstants.healthDndDesc,
          value: state.dndBypassEnabled,
          onToggle: (_) => cubit.toggleDndBypass(),
        ),
        const SizedBox(height: AppConstants.spaceLg),
        _SectionLabel('Hardware Sensor Diagnostics'),
        const SizedBox(height: AppConstants.spaceSm),
        SensorStatusCard(
          label: StringConstants.healthGpsLabel,
          status: state.gpsStatus,
          icon: Icons.gps_fixed_rounded,
        ),
        const SizedBox(height: AppConstants.spaceSm),
        SensorStatusCard(
          label: StringConstants.healthWifiLabel,
          status: state.wifiStatus,
          icon: Icons.wifi_rounded,
        ),
        const SizedBox(height: AppConstants.spaceSm),
        SensorStatusCard(
          label: StringConstants.healthDeadRecLabel,
          status: state.deadRecStatus,
          icon: Icons.explore_rounded,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.sora(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: ColorConstants.textSecondary,
        letterSpacing: 0.15,
      ),
    );
  }
}
