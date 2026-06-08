import 'package:flutter/material.dart';
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
    final bg = switch (variant) {
      SnoozerButtonVariant.primary   => ColorConstants.primary,
      SnoozerButtonVariant.secondary => ColorConstants.surfaceElevated,
      SnoozerButtonVariant.ghost     => Colors.transparent,
      SnoozerButtonVariant.danger    => ColorConstants.error,
    };
    final fg = switch (variant) {
      SnoozerButtonVariant.primary   => ColorConstants.surfaceBase,
      SnoozerButtonVariant.secondary => ColorConstants.textPrimary,
      SnoozerButtonVariant.ghost     => ColorConstants.textSecondary,
      SnoozerButtonVariant.danger    => ColorConstants.surfaceBase,
    };
    final glow = variant == SnoozerButtonVariant.primary
        ? [BoxShadow(color: ColorConstants.primaryGlow, blurRadius: 16)]
        : <BoxShadow>[];

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
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
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
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.05,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
