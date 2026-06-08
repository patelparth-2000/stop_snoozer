import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';

class DashboardAppBar extends StatelessWidget {
  const DashboardAppBar({
    super.key,
    required this.greeting,
    required this.timeString,
    this.onHealthTap,
  });

  final String greeting;
  final String timeString;
  final VoidCallback? onHealthTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeString,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.primary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  greeting,
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onHealthTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: const Icon(
                Icons.monitor_heart_outlined,
                color: ColorConstants.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
