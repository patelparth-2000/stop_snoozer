import 'package:flutter/material.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';

class SnoozerCard extends StatelessWidget {
  const SnoozerCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.borderColor,
    this.glowColor,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final Color? glowColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: color ?? ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: borderColor ?? ColorConstants.surfaceElevated,
          ),
          boxShadow: glowColor != null
              ? [BoxShadow(color: glowColor!, blurRadius: 20)]
              : null,
        ),
        child: child,
      ),
    );
  }
}
