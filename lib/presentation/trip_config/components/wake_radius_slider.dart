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
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ColorConstants.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceSm,
                vertical: AppConstants.spaceXs,
              ),
              decoration: BoxDecoration(
                color: ColorConstants.primarySubtle,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
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
        SliderTheme(
          data: SliderTheme.of(context),
          child: Slider(
            value: value,
            min: AppConstants.minWakeRadiusMetres,
            max: AppConstants.maxWakeRadiusMetres,
            divisions: 18,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${AppConstants.minWakeRadiusMetres.round()} m',
              style: GoogleFonts.inter(fontSize: 10, color: ColorConstants.textDisabled),
            ),
            Text(
              '${AppConstants.maxWakeRadiusMetres.round()} m',
              style: GoogleFonts.inter(fontSize: 10, color: ColorConstants.textDisabled),
            ),
          ],
        ),
      ],
    );
  }
}
