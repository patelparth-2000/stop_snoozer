import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/number_formatters.dart';
import '../../../data/models/stop_point.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class AlarmDestinationInfo extends StatelessWidget {
  const AlarmDestinationInfo({
    super.key,
    required this.stop,
    required this.distanceMetres,
  });

  final StopPoint stop;
  final double distanceMetres;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: ColorConstants.primaryGlow, width: 1),
      ),
      child: Column(
        children: [
          Text(
            StringConstants.alarmApproaching,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textSecondary,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TransportModeIcon(mode: stop.mode, size: 28),
              const SizedBox(width: AppConstants.spaceSm),
              Flexible(
                child: Text(
                  stop.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceLg,
              vertical: AppConstants.spaceSm,
            ),
            decoration: BoxDecoration(
              color: ColorConstants.primarySubtle,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              'Approx ${NumberFormatters.metres(distanceMetres)} ${StringConstants.alarmAway}',
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ColorConstants.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
