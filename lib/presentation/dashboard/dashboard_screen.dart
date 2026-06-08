import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'dashboard_viewmodel.dart';
import 'components/dashboard_app_bar.dart';
import 'components/location_detection_card.dart';
import 'components/transport_chips_row.dart';
import 'components/journey_timeline.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../shared/widgets/snoozer_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardCubit>().load();
    });
  }

  String _timeString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              DashboardAppBar(
                greeting: context.read<DashboardCubit>().greeting,
                timeString: _timeString(),
                onHealthTap: () => context.push('/system-health'),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              LocationDetectionCard(
                isLocating: state.isLocating,
                detectedStopName: state.detectedStopName,
              ),
              const SizedBox(height: AppConstants.spaceMd),
              TransportChipsRow(stops: state.nearbyStops),
              const SizedBox(height: AppConstants.spaceLg),
              Expanded(
                child: SingleChildScrollView(
                  child: JourneyTimeline(legs: state.legs),
                ),
              ),
              _BottomBar(onSearchTap: () => context.push('/search')),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSearchTap});
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceMd + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: ColorConstants.surfaceBase,
        border: Border(top: BorderSide(color: ColorConstants.divider, width: 1)),
      ),
      child: SnoozerButton(
        label: StringConstants.dashboardSearchCta,
        onTap: onSearchTap,
        icon: Icons.search_rounded,
      ),
    );
  }
}
