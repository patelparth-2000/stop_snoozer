import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'trip_config_viewmodel.dart';
import 'components/trip_leg_config_card.dart';
import 'components/trip_config_footer.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../dashboard/dashboard_viewmodel.dart';

class TripConfigScreen extends StatelessWidget {
  const TripConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<TripConfigCubit, TripConfigState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => context.pop()),
              Expanded(
                child: state.hasLegs
                    ? _LegList(state: state)
                    : const _EmptyState(),
              ),
              TripConfigFooter(
                canArm: state.hasLegs,
                onArm: () => _arm(context, state),
                onClear: () {
                  context.read<TripConfigCubit>().clear();
                  context.go('/dashboard');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _arm(BuildContext context, TripConfigState state) {
    final legs = context.read<TripConfigCubit>().buildArmedLegs();
    context.read<DashboardCubit>().loadTrip(legs);
    context.go('/dashboard');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceMd,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: ColorConstants.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            child: Text(
              StringConstants.tripConfigTitle,
              style: GoogleFonts.sora(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: ColorConstants.textPrimary, letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegList extends StatelessWidget {
  const _LegList({required this.state});
  final TripConfigState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripConfigCubit>();
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(top: AppConstants.spaceSm),
            itemCount: state.legs.length,
            onReorder: cubit.reorderLegs,
            itemBuilder: (_, i) => TripLegConfigCard(
              key: ValueKey(state.legs[i].stop.id),
              leg: state.legs[i],
              index: i,
              onRadiusChanged: (v) => cubit.updateRadius(i, v),
              onStyleChanged: (s) => cubit.updateAlarmStyle(i, s),
              onRemove: () => cubit.removeLeg(i),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.containerMargin,
            vertical: AppConstants.spaceSm,
          ),
          child: GestureDetector(
            onTap: () => context.push('/search'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMd),
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: ColorConstants.surfaceElevated),
              ),
              child: Center(
                child: Text(
                  StringConstants.tripConfigAddLeg,
                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: ColorConstants.primary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.playlist_add_rounded, color: ColorConstants.textDisabled, size: 48),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            'No stops added yet',
            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: ColorConstants.textSecondary),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          GestureDetector(
            onTap: () => context.push('/search'),
            child: Text(
              StringConstants.tripConfigAddLeg,
              style: GoogleFonts.inter(fontSize: 13, color: ColorConstants.primary),
            ),
          ),
        ],
      ),
    );
  }
}
