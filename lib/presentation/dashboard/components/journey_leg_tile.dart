import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/trip_leg.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class JourneyLegTile extends StatelessWidget {
  const JourneyLegTile({
    super.key,
    required this.leg,
    required this.index,
    this.isLast = false,
  });

  final TripLeg leg;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isActive   = leg.status == LegStatus.active;
    final isComplete = leg.status == LegStatus.complete;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimelineColumn(
            isActive: isActive, isComplete: isComplete, isLast: isLast),
        const SizedBox(width: AppConstants.spaceMd),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.only(bottom: AppConstants.spaceLg),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isActive
                    ? ColorConstants.primarySubtle
                    : ColorConstants.surfaceSecondary,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                border: Border(
                  left: isActive
                      ? BorderSide(
                          color: ColorConstants.primary, width: 3)
                      : BorderSide(
                          color: ColorConstants.surfaceElevated),
                  top:    BorderSide(
                      color: ColorConstants.surfaceElevated),
                  right:  BorderSide(
                      color: ColorConstants.surfaceElevated),
                  bottom: BorderSide(
                      color: ColorConstants.surfaceElevated),
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: ColorConstants.primaryGlow,
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                child: Row(
                  children: [
                    TransportModeIcon(
                        mode: leg.stop.mode,
                        size: 36),
                    const SizedBox(width: AppConstants.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            leg.stop.name,
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? ColorConstants.primary
                                  : isComplete
                                      ? ColorConstants.textDisabled
                                      : ColorConstants.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${leg.wakeRadiusMetres.round()} ${StringConstants.tripConfigMetres} wake radius',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: ColorConstants.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: leg.status),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineColumn extends StatelessWidget {
  const _TimelineColumn({
    required this.isActive,
    required this.isComplete,
    required this.isLast,
  });
  final bool isActive;
  final bool isComplete;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dotColor = isActive
        ? ColorConstants.primary
        : isComplete
            ? ColorConstants.success
            : ColorConstants.surfaceElevated;

    return SizedBox(
      width: 20,
      child: Column(
        children: [
          const SizedBox(height: AppConstants.spaceMd),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              border: !isActive && !isComplete
                  ? Border.all(color: ColorConstants.divider, width: 1)
                  : null,
              boxShadow: isActive
                  ? [BoxShadow(color: ColorConstants.primaryGlow, blurRadius: 10)]
                  : isComplete
                      ? [BoxShadow(color: ColorConstants.successGlow, blurRadius: 6)]
                      : null,
            ),
          ),
          if (!isLast) ...[
            const SizedBox(height: 4),
            Container(
              width: 1,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isActive || isComplete
                        ? ColorConstants.divider
                        : ColorConstants.surfaceElevated,
                    ColorConstants.surfaceElevated,
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final LegStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      LegStatus.active   => (StringConstants.dashboardLegActive,   ColorConstants.primary),
      LegStatus.queued   => (StringConstants.dashboardLegQueued,   ColorConstants.textDisabled),
      LegStatus.complete => (StringConstants.dashboardLegComplete, ColorConstants.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceSm, vertical: AppConstants.spaceXs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.sora(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
