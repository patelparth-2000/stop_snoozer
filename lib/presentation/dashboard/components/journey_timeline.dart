import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/trip_leg.dart';
import 'journey_leg_tile.dart';

class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({
    super.key,
    required this.legs,
  });

  final List<TripLeg> legs;

  @override
  Widget build(BuildContext context) {
    if (legs.isEmpty) return const _EmptyTrip();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
          child: Text(
            StringConstants.dashboardActiveJourney,
            style: GoogleFonts.sora(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textSecondary,
              letterSpacing: 0.15,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceMd),
        Padding(
          padding: const EdgeInsets.only(left: AppConstants.containerMargin),
          child: Column(
            children: [
              for (int i = 0; i < legs.length; i++)
                JourneyLegTile(
                  leg: legs[i],
                  index: i,
                  isLast: i == legs.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyTrip extends StatelessWidget {
  const _EmptyTrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            color: ColorConstants.textDisabled,
            size: 40,
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            StringConstants.dashboardNoTrip,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ColorConstants.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            StringConstants.dashboardNoTripSub,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}
