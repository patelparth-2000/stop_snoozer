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
    this.showIndicator = false,
  });

  final StopPoint stop;
  final VoidCallback onTap;
  /// When true the indicator badge is shown to disambiguate duplicate names.
  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
    final indicator = stop.indicator?.trim();
    final hasIndicator = showIndicator &&
        indicator != null &&
        indicator.isNotEmpty;

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
                  // Name row with optional indicator badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          stop.name,
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ColorConstants.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasIndicator) ...[
                        const SizedBox(width: AppConstants.spaceSm),
                        _IndicatorBadge(label: indicator),
                      ],
                    ],
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
            if (stop.distanceKm != null) ...[
              const SizedBox(width: AppConstants.spaceSm),
              Text(
                '${NumberFormatters.miles(stop.distanceKm!)} ${StringConstants.searchMiles}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: ColorConstants.textDisabled,
                ),
              ),
            ],
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

class _IndicatorBadge extends StatelessWidget {
  const _IndicatorBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ColorConstants.primarySubtle,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: ColorConstants.primaryGlow, width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ColorConstants.primary,
        ),
      ),
    );
  }
}
