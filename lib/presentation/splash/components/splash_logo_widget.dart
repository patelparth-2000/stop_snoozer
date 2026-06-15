import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class SplashLogoWidget extends StatefulWidget {
  const SplashLogoWidget({super.key});

  @override
  State<SplashLogoWidget> createState() => _SplashLogoWidgetState();
}

class _SplashLogoWidgetState extends State<SplashLogoWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppConstants.durationPulse),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (_, _) => Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ColorConstants.primarySubtle,
              boxShadow: [
                BoxShadow(
                  color: ColorConstants.primaryGlow,
                  blurRadius: _glow.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: ColorConstants.primary,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceLg),
        Text(
          StringConstants.appName,
          style: GoogleFonts.sora(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: ColorConstants.textPrimary,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: AppConstants.spaceXs),
        Text(
          StringConstants.appTagline,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: ColorConstants.textSecondary,
          ),
        ),
      ],
    );
  }
}
