import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class WakeRadiusSlider extends StatelessWidget {
  const WakeRadiusSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              StringConstants.tripConfigRadius,
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textDisabled,
                letterSpacing: 0.3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceSm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: ColorConstants.primarySubtle,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(
                    color: ColorConstants.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${value.round()} ${StringConstants.tripConfigMetres}',
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ColorConstants.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceXs),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: ColorConstants.primary,
            inactiveTrackColor: ColorConstants.surfaceElevated,
            thumbColor: ColorConstants.primary,
            overlayColor: ColorConstants.primarySubtle,
            trackHeight: 3,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 14),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value,
            min: AppConstants.minWakeRadiusMetres,
            max: AppConstants.maxWakeRadiusMetres,
            divisions: 18,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppConstants.minWakeRadiusMetres.round()} m',
                style: GoogleFonts.inter(
                    fontSize: 10, color: ColorConstants.textDisabled),
              ),
              Text(
                '${AppConstants.maxWakeRadiusMetres.round()} m',
                style: GoogleFonts.inter(
                    fontSize: 10, color: ColorConstants.textDisabled),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
