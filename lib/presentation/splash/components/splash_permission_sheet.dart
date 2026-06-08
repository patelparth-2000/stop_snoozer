import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../shared/widgets/snoozer_button.dart';

class SplashPermissionSheet extends StatelessWidget {
  const SplashPermissionSheet({
    super.key,
    required this.locationGranted,
    required this.notificationGranted,
    required this.batteryGranted,
    required this.onRequestPermissions,
    required this.onSkip,
  });

  final bool locationGranted;
  final bool notificationGranted;
  final bool batteryGranted;
  final VoidCallback onRequestPermissions;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: ColorConstants.surfaceModal,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppConstants.containerMargin,
          AppConstants.spaceLg,
          AppConstants.containerMargin,
          AppConstants.spaceLg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ColorConstants.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            Text(
              StringConstants.splashPermTitle,
              style: GoogleFonts.sora(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              StringConstants.splashPermSubtitle,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ColorConstants.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            _PermissionRow(
              icon: Icons.location_on_rounded,
              label: StringConstants.splashPermLocation,
              description: StringConstants.splashPermLocationDesc,
              granted: locationGranted,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _PermissionRow(
              icon: Icons.notifications_rounded,
              label: StringConstants.splashPermNotification,
              description: StringConstants.splashPermNotifDesc,
              granted: notificationGranted,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _PermissionRow(
              icon: Icons.battery_charging_full_rounded,
              label: StringConstants.splashPermBattery,
              description: StringConstants.splashPermBatteryDesc,
              granted: batteryGranted,
            ),
            const SizedBox(height: AppConstants.spaceXl),
            SnoozerButton(
              label: StringConstants.splashPermContinue,
              onTap: onRequestPermissions,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            SnoozerButton(
              label: StringConstants.splashPermSkip,
              onTap: onSkip,
              variant: SnoozerButtonVariant.ghost,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.granted,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: granted ? ColorConstants.successGlow : ColorConstants.primarySubtle,
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          child: Icon(
            icon,
            color: granted ? ColorConstants.success : ColorConstants.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: AppConstants.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ColorConstants.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (granted)
          const Icon(Icons.check_circle_rounded, color: ColorConstants.success, size: 20),
      ],
    );
  }
}
