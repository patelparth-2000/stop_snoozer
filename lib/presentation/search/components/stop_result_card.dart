import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/number_formatters.dart';
import '../../../data/models/stop_point.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class StopResultCard extends StatelessWidget {
  const StopResultCard({
    super.key,
    required this.stop,
    required this.onTap,
  });

  final StopPoint stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin,
          vertical: AppConstants.spaceXs,
        ),
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          children: [
            TransportModeIcon(mode: stop.mode, size: 40),
            const SizedBox(width: AppConstants.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TransportModeIcon.label(stop.mode),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: ColorConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (stop.distanceKm != null)
              Text(
                '${NumberFormatters.miles(stop.distanceKm!)} ${StringConstants.searchMiles}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: ColorConstants.textDisabled,
                ),
              ),
            const SizedBox(width: AppConstants.spaceSm),
            const Icon(
              Icons.add_circle_outline_rounded,
              color: ColorConstants.primary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
