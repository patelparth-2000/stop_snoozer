import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class LocationDetectionCard extends StatelessWidget {
  const LocationDetectionCard({
    super.key,
    required this.isLocating,
    this.detectedStopName,
  });

  final bool isLocating;
  final String? detectedStopName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceSm,
      ),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: ColorConstants.surfaceElevated, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLocating ? ColorConstants.textDisabled : ColorConstants.success,
              boxShadow: isLocating
                  ? null
                  : [BoxShadow(color: ColorConstants.successGlow, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: AppConstants.spaceSm),
          Text(
            isLocating
                ? StringConstants.dashboardNoLocation
                : StringConstants.dashboardDetectedNear,
            style: GoogleFonts.sora(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textSecondary,
              letterSpacing: 0.15,
            ),
          ),
          if (!isLocating && detectedStopName != null) ...[
            const SizedBox(width: AppConstants.spaceSm),
            Expanded(
              child: Text(
                detectedStopName!,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
