import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class LocationDetectionCard extends StatelessWidget {
  const LocationDetectionCard({
    super.key,
    required this.isLocating,
    this.detectedStopName,
  });

  final bool isLocating;
  final String? detectedStopName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: ColorConstants.surfaceElevated),
      ),
      child: Row(
        children: [
          _PulseDot(active: !isLocating),
          const SizedBox(width: AppConstants.spaceSm),
          Text(
            isLocating
                ? StringConstants.dashboardNoLocation
                : StringConstants.dashboardDetectedNear,
            style: GoogleFonts.sora(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textDisabled,
              letterSpacing: 0.5,
            ),
          ),
          if (!isLocating && detectedStopName != null) ...[
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: ColorConstants.surfaceElevated,
            ),
            Expanded(
              child: Text(
                detectedStopName!,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.textPrimary,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (isLocating)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: ColorConstants.textDisabled,
              ),
            ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.active});
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppConstants.durationPulse),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    if (!widget.active) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColorConstants.textDisabled,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColorConstants.success,
          boxShadow: [
            BoxShadow(
              color: ColorConstants.successGlow.withValues(alpha: _anim.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
