import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../shared/widgets/theme_picker_sheet.dart';

class DashboardAppBar extends StatelessWidget {
  const DashboardAppBar({
    super.key,
    required this.greeting,
    this.onHealthTap,
    this.onCalendarTap,
  });

  final String greeting;
  final VoidCallback? onHealthTap;
  final VoidCallback? onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'StopSnoozer',
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.primary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  greeting,
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          _IconButton(
            icon: Icons.alarm_rounded,
            color: ColorConstants.primary,
            onTap: onCalendarTap,
          ),
          const SizedBox(width: AppConstants.spaceXs),
          _IconButton(
            icon: Icons.palette_outlined,
            color: ColorConstants.textSecondary,
            onTap: () => ThemePickerSheet.show(context),
          ),
          const SizedBox(width: AppConstants.spaceXs),
          _IconButton(
            icon: Icons.settings_outlined,
            color: ColorConstants.textSecondary,
            onTap: onHealthTap,
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: ColorConstants.surfaceElevated),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
