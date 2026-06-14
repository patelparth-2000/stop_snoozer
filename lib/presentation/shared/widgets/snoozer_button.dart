import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';

enum SnoozerButtonVariant { primary, secondary, ghost, danger }

class SnoozerButton extends StatelessWidget {
  const SnoozerButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = SnoozerButtonVariant.primary,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final SnoozerButtonVariant variant;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    final bg = switch (variant) {
      SnoozerButtonVariant.primary   => disabled
          ? ColorConstants.surfaceElevated
          : ColorConstants.primary,
      SnoozerButtonVariant.secondary => ColorConstants.surfaceElevated,
      SnoozerButtonVariant.ghost     => Colors.transparent,
      SnoozerButtonVariant.danger    => ColorConstants.error.withValues(alpha: 0.15),
    };

    final fg = switch (variant) {
      SnoozerButtonVariant.primary   => disabled
          ? ColorConstants.textDisabled
          : ColorConstants.surfaceBase,
      SnoozerButtonVariant.secondary => ColorConstants.textPrimary,
      SnoozerButtonVariant.ghost     => ColorConstants.textSecondary,
      SnoozerButtonVariant.danger    => ColorConstants.error,
    };

    final border = switch (variant) {
      SnoozerButtonVariant.primary   => disabled
          ? Border.all(color: ColorConstants.surfaceElevated)
          : Border.all(color: ColorConstants.primary.withValues(alpha: 0.4)),
      SnoozerButtonVariant.secondary => Border.all(color: ColorConstants.surfaceElevated),
      SnoozerButtonVariant.ghost     => null,
      SnoozerButtonVariant.danger    => Border.all(
            color: ColorConstants.error.withValues(alpha: 0.3)),
    };

    final glow = (variant == SnoozerButtonVariant.primary && !disabled)
        ? [
            BoxShadow(
              color: ColorConstants.primary.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ]
        : <BoxShadow>[];

    final radius = variant == SnoozerButtonVariant.primary
        ? AppConstants.radiusLg
        : AppConstants.radiusMd;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppConstants.durationFast),
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceLg,
          vertical: AppConstants.spaceMd,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: glow,
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
              )
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: 18),
                    const SizedBox(width: AppConstants.spaceSm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
