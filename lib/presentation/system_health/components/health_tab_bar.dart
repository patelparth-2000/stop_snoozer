import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class HealthTabBar extends StatelessWidget {
  const HealthTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final int selectedIndex;
  final void Function(int) onTabSelected;

  static const _tabs = [
    StringConstants.healthTabDashboard,
    StringConstants.healthTabDiagnostics,
    StringConstants.healthTabOptimizers,
    StringConstants.healthTabAlerts,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: AppConstants.durationFast),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected ? ColorConstants.surfaceElevated : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabs[i],
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? ColorConstants.textPrimary : ColorConstants.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
