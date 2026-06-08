import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class AlarmHeader extends StatefulWidget {
  const AlarmHeader({super.key});

  @override
  State<AlarmHeader> createState() => _AlarmHeaderState();
}

class _AlarmHeaderState extends State<AlarmHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppConstants.durationPulse),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
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
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ColorConstants.errorGlow,
              boxShadow: [
                BoxShadow(
                  color: ColorConstants.error.withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: ColorConstants.error,
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceLg),
        Text(
          StringConstants.alarmWakeUp,
          style: GoogleFonts.sora(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: ColorConstants.primary,
            letterSpacing: 0.05,
            shadows: [
              Shadow(
                color: ColorConstants.primaryGlow,
                blurRadius: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
