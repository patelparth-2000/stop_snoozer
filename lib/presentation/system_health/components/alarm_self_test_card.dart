import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../shared/widgets/snoozer_button.dart';
import '../system_health_viewmodel.dart';

/// A10 — "Test your alarm".
///
/// Answers the one question the rest of this screen only implies: *will an alarm
/// actually fire on this phone?* Permission checkmarks cannot answer it, because
/// OEM background killers ignore the AOSP battery exemption entirely. So this
/// schedules a real alarm and reports whether the OS delivered it.
class AlarmSelfTestCard extends StatelessWidget {
  const AlarmSelfTestCard({super.key, required this.state});

  final SystemHealthState state;

  static const int _delaySeconds = 10;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SystemHealthCubit>();
    final d = state.diagnostics;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: state.selfTestState == SelfTestState.failed
            ? Border.all(color: ColorConstants.error.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm_on_rounded,
                  color: ColorConstants.primary, size: 18),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Text(
                  'Test Your Alarm',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            _body(state),
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textSecondary,
              height: 1.45,
            ),
          ),

          // ── Blocking conditions, named specifically ──────────────────
          if (!d.canScheduleExactAlarms) ...[
            const SizedBox(height: AppConstants.spaceSm),
            const _Warning(
              'Exact alarms are turned off for StopSnoozer. Alarms will still '
              'fire, but may be several minutes late — enough to miss a stop.',
            ),
          ],
          if (!d.notificationsEnabled) ...[
            const SizedBox(height: AppConstants.spaceSm),
            const _Warning(
              'Notifications are blocked. You will not see or hear the alarm.',
            ),
          ],
          if (!d.batteryOptimizationExempt) ...[
            const SizedBox(height: AppConstants.spaceSm),
            const _Warning(
              'Battery optimisation is still active. Android may stop tracking '
              'while your screen is off.',
            ),
          ],

          const SizedBox(height: AppConstants.spaceMd),
          _action(context, cubit, state),
        ],
      ),
    );
  }

  static String _body(SystemHealthState s) => switch (s.selfTestState) {
        SelfTestState.idle =>
          'Schedules a real alarm $_delaySeconds seconds from now, through the '
              'same path a commute alarm uses. Leave the app or lock your '
              'screen after starting — that is exactly what this checks.',
        SelfTestState.armed => s.selfTestWasExact
            ? 'Armed. Lock your screen and wait — the alarm should sound in '
                'about $_delaySeconds seconds.'
            : 'Armed, but only as an inexact alarm because exact-alarm '
                'permission is unavailable. It may take up to a minute.',
        SelfTestState.passed =>
          'Passed — the alarm fired while the app was in the background. '
              'Your stop alarms will work on this device.',
        SelfTestState.failed =>
          'No alarm fired within the expected window. On this device something '
              'is stopping StopSnoozer in the background — the most common '
              'cause is a manufacturer battery manager.',
      };

  Widget _action(
    BuildContext context,
    SystemHealthCubit cubit,
    SystemHealthState s,
  ) {
    switch (s.selfTestState) {
      case SelfTestState.idle:
        return SnoozerButton(
          label: 'Run Alarm Test',
          onTap: () => cubit.runSelfTest(delaySeconds: _delaySeconds),
        );
      case SelfTestState.armed:
        return SnoozerButton(
          label: 'Waiting for alarm…',
          isLoading: true,
          onTap: null,
        );
      case SelfTestState.passed:
        return Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Alarm delivery verified',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF10B981),
                ),
              ),
            ),
            TextButton(
              onPressed: cubit.resetSelfTest,
              child: Text(
                'Test again',
                style: GoogleFonts.sora(
                  fontSize: 11,
                  color: ColorConstants.textSecondary,
                ),
              ),
            ),
          ],
        );
      case SelfTestState.failed:
        return Column(
          children: [
            SnoozerButton(
              label: 'Try Again',
              onTap: () => cubit.runSelfTest(delaySeconds: _delaySeconds),
              variant: SnoozerButtonVariant.secondary,
            ),
            if (s.oemSettingsAvailable) ...[
              const SizedBox(height: AppConstants.spaceSm),
              SnoozerButton(
                label: 'Fix in ${s.oemName ?? 'Phone'} Settings',
                onTap: cubit.openOemBatterySettings,
              ),
            ],
          ],
        );
    }
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded,
            color: ColorConstants.error, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: ColorConstants.error,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
