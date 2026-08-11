import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../shared/widgets/snoozer_button.dart';
import '../system_health_viewmodel.dart';

/// A9 — manufacturer-specific background restrictions.
///
/// Xiaomi/MIUI, Huawei, Oppo, Vivo and others run a proprietary process killer
/// *in addition to* AOSP battery optimisation. Granting the standard exemption
/// does not stop them, so the generic card above this one is not enough.
///
/// Renders nothing on manufacturers with no known extra killer, and nothing when
/// the specific settings Activity does not resolve — sending users to hunt for a
/// screen their phone does not have is worse than staying quiet.
class OemBatteryCard extends StatelessWidget {
  const OemBatteryCard({super.key, required this.state});

  final SystemHealthState state;

  @override
  Widget build(BuildContext context) {
    final oem = state.oemName;
    if (oem == null || !state.oemSettingsAvailable) {
      return const SizedBox.shrink();
    }
    final cubit = context.read<SystemHealthCubit>();

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: ColorConstants.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phonelink_setup_rounded,
                  color: ColorConstants.primary, size: 18),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Text(
                  '$oem Background Restrictions',
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
            '$oem devices run their own app killer on top of Android\'s. Even '
            'with the battery whitelist above, StopSnoozer can be stopped while '
            'your screen is off.\n\n'
            'Open the settings below and allow StopSnoozer to auto-start / run '
            'in the background, then confirm with the alarm test.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          SnoozerButton(
            label: 'Open $oem Settings',
            onTap: cubit.openOemBatterySettings,
            variant: SnoozerButtonVariant.secondary,
          ),
        ],
      ),
    );
  }
}
