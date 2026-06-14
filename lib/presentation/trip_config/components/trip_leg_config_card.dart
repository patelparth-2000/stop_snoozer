import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/trip_leg.dart';
import '../../shared/widgets/transport_mode_icon.dart';
import 'wake_radius_slider.dart';

class TripLegConfigCard extends StatefulWidget {
  const TripLegConfigCard({
    super.key,
    required this.leg,
    required this.index,
    required this.onRadiusChanged,
    required this.onRemove,
  });

  final TripLeg leg;
  final int index;
  final void Function(double) onRadiusChanged;
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(
          left:   BorderSide(color: ColorConstants.primary, width: 3),
          top:    BorderSide(color: ColorConstants.surfaceElevated),
          right:  BorderSide(color: ColorConstants.surfaceElevated),
          bottom: BorderSide(color: ColorConstants.surfaceElevated),
        ),
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
            child: _expanded
                ? _Body(
                    leg: widget.leg,
                    onRadiusChanged: widget.onRadiusChanged,
                  )
                : const SizedBox.shrink(),
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
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd,
          AppConstants.spaceMd,
          AppConstants.spaceSm,
          AppConstants.spaceMd,
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_indicator_rounded,
              color: ColorConstants.textDisabled,
              size: 20,
            ),
            const SizedBox(width: AppConstants.spaceXs),
            TransportModeIcon(mode: leg.stop.mode, size: 36),
            const SizedBox(width: AppConstants.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LEG ${index + 1}',
                    style: GoogleFonts.sora(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: ColorConstants.primary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    leg.stop.name,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceXs),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ColorConstants.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: ColorConstants.error,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceXs),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: ColorConstants.textDisabled,
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
  });
  final TripLeg leg;
  final void Function(double) onRadiusChanged;

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
          Divider(height: 1, color: ColorConstants.surfaceElevated),
          const SizedBox(height: AppConstants.spaceMd),
          WakeRadiusSlider(value: leg.wakeRadiusMetres, onChanged: onRadiusChanged),
        ],
      ),
    );
  }
}
