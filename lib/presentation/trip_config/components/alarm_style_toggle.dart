import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/trip_leg.dart';

class AlarmStyleToggle extends StatelessWidget {
  const AlarmStyleToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AlarmStyle value;
  final void Function(AlarmStyle) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StringConstants.tripConfigStyle,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ColorConstants.textSecondary,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: AppConstants.spaceSm),
        Row(
          children: [
            Expanded(
              child: _StyleOption(
                label: StringConstants.tripConfigSubtle,
                icon: Icons.vibration_rounded,
                selected: value == AlarmStyle.subtlePulse,
                onTap: () => onChanged(AlarmStyle.subtlePulse),
              ),
            ),
            const SizedBox(width: AppConstants.spaceSm),
            Expanded(
              child: _StyleOption(
                label: StringConstants.tripConfigDefcon,
                icon: Icons.warning_amber_rounded,
                selected: value == AlarmStyle.defconDrill,
                onTap: () => onChanged(AlarmStyle.defconDrill),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppConstants.durationFast),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceSm,
          vertical: AppConstants.spaceMd,
        ),
        decoration: BoxDecoration(
          color: selected ? ColorConstants.primarySubtle : ColorConstants.surfaceElevated,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: selected
              ? Border.all(color: ColorConstants.primary, width: 1)
              : Border.all(color: ColorConstants.surfaceElevated, width: 1),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? ColorConstants.primary : ColorConstants.textSecondary,
              size: 20,
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? ColorConstants.primary : ColorConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
