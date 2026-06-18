import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../search_viewmodel.dart';

class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final TransitFilter activeFilter;
  final void Function(TransitFilter) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin,
        ),
        itemCount: TransitFilter.values.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: AppConstants.spaceSm),
        itemBuilder: (_, i) {
          final filter = TransitFilter.values[i];
          return _FilterChip(
            label: filter.label,
            isActive: filter == activeFilter,
            onTap: () => onFilterChanged(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppConstants.durationFast),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? ColorConstants.primary
              : ColorConstants.surfaceElevated,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isActive
                ? ColorConstants.primary
                : ColorConstants.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive
                ? ColorConstants.surfaceBase
                : ColorConstants.textSecondary,
          ),
        ),
      ),
    );
  }
}
