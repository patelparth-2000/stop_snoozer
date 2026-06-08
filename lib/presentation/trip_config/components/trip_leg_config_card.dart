import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/trip_leg.dart';
import '../../shared/widgets/transport_mode_icon.dart';
import 'wake_radius_slider.dart';
import 'alarm_style_toggle.dart';

class TripLegConfigCard extends StatefulWidget {
  const TripLegConfigCard({
    super.key,
    required this.leg,
    required this.index,
    required this.onRadiusChanged,
    required this.onStyleChanged,
    required this.onRemove,
  });

  final TripLeg leg;
  final int index;
  final void Function(double) onRadiusChanged;
  final void Function(AlarmStyle) onStyleChanged;
  final VoidCallback onRemove;

  @override
  State<TripLegConfigCard> createState() => _TripLegConfigCardState();
}

class _TripLegConfigCardState extends State<TripLegConfigCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceXs,
      ),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        children: [
          _Header(
            leg: widget.leg,
            index: widget.index,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            onRemove: widget.onRemove,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: AppConstants.durationNormal),
            curve: Curves.easeInOut,
            child: _expanded ? _Body(leg: widget.leg, onRadiusChanged: widget.onRadiusChanged, onStyleChanged: widget.onStyleChanged) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.leg,
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.onRemove,
  });
  final TripLeg leg;
  final int index;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Row(
          children: [
            const Icon(Icons.drag_handle_rounded, color: ColorConstants.textDisabled, size: 20),
            const SizedBox(width: AppConstants.spaceSm),
            TransportModeIcon(mode: leg.stop.mode, size: 36),
            const SizedBox(width: AppConstants.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Leg ${index + 1}',
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ColorConstants.primary,
                      letterSpacing: 0.15,
                    ),
                  ),
                  Text(
                    leg.stop.name,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.remove_circle_outline_rounded, color: ColorConstants.error, size: 20),
            ),
            const SizedBox(width: AppConstants.spaceSm),
            Icon(
              expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: ColorConstants.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.leg,
    required this.onRadiusChanged,
    required this.onStyleChanged,
  });
  final TripLeg leg;
  final void Function(double) onRadiusChanged;
  final void Function(AlarmStyle) onStyleChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        0,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
      ),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: AppConstants.spaceMd),
          WakeRadiusSlider(value: leg.wakeRadiusMetres, onChanged: onRadiusChanged),
          const SizedBox(height: AppConstants.spaceMd),
          AlarmStyleToggle(value: leg.alarmStyle, onChanged: onStyleChanged),
        ],
      ),
    );
  }
}
