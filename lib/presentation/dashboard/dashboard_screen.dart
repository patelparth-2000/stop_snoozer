import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_viewmodel.dart';
import 'components/dashboard_app_bar.dart';
import 'components/location_detection_card.dart';
import 'components/saved_location_card.dart';
import 'components/transport_chips_row.dart';
import 'components/journey_timeline.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/stop_point.dart';
import '../onboarding/onboarding_overlay.dart';
import '../shared/widgets/snoozer_button.dart';
import '../shared/widgets/transport_mode_icon.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardCubit>().load();
      _checkOnboarding();
    });
  }

  Future<void> _checkOnboarding() async {
    final show = await shouldShowOnboarding();
    if (mounted && show) setState(() => _showOnboarding = true);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<DashboardCubit, DashboardState>(
          listenWhen: (prev, curr) =>
              curr.alarmStop != null && curr.alarmStop != prev.alarmStop,
          listener: (context, state) {
            context.read<DashboardCubit>().clearAlarm();
          },
        ),
        BlocListener<DashboardCubit, DashboardState>(
          listenWhen: (prev, curr) =>
              curr.warningMessage != null &&
              curr.warningMessage != prev.warningMessage,
          listener: (context, state) {
            context.read<DashboardCubit>().clearWarning();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.warningMessage!,
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                backgroundColor: const Color(0xFF1E293B),
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: ColorConstants.primary,
                  onPressed: () => context
                      .read<DashboardCubit>()
                      .openWifiSettings(),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          },
        ),
      ],
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: ColorConstants.surfaceBase,
            body: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) => SafeArea(
            child: Column(
              children: [
                DashboardAppBar(
                  greeting: context.read<DashboardCubit>().greeting,
                  onCalendarTap: () => context.go('/calendar'),
                  onHealthTap: () => context.go('/settings'),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                LocationDetectionCard(
                  isLocating: state.isLocating,
                  detectedStopName: state.detectedStopName,
                ),
                // Proximity suggestion card — shown when location is known
                // and there are nearby stops but no active trip
                if (!state.isLocating &&
                    state.nearbyStops.isNotEmpty &&
                    !state.hasActiveTrip)
                  _ProximitySuggestionCard(
                    nearestStop: state.nearbyStops.first,
                    onTap: () => context.go('/search'),
                  ),
                const SizedBox(height: AppConstants.spaceMd),
                TransportChipsRow(stops: state.nearbyStops),
                if (state.savedLocations.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spaceMd),
                  _SavedStopsSection(
                    locations: state.savedLocations,
                    onToggle: (id) =>
                        context.read<DashboardCubit>().toggleSavedLocation(id),
                    onDelete: (id) =>
                        context.read<DashboardCubit>().deleteSavedLocation(id),
                  ),
                ],
                const SizedBox(height: AppConstants.spaceLg),
                Expanded(
                  child: SingleChildScrollView(
                    child: JourneyTimeline(legs: state.legs),
                  ),
                ),
                _BottomBar(onSearchTap: () => context.go('/search')),
              ],
            ),
          ),
        ),
            // Floating Action Button
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.go('/search'),
              backgroundColor: ColorConstants.primary,
              foregroundColor: ColorConstants.surfaceBase,
              elevation: 4,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
          if (_showOnboarding)
            OnboardingOverlay(
              onDone: () => setState(() => _showOnboarding = false),
            ),
        ],
      ),
    );
  }
}

// ── Saved Stops Section ────────────────────────────────────────────────────

class _SavedStopsSection extends StatelessWidget {
  const _SavedStopsSection({
    required this.locations,
    required this.onToggle,
    required this.onDelete,
  });

  final List<dynamic> locations;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAVED STOPS',
            style: GoogleFonts.sora(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textSecondary,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 8),
          ...locations.map((loc) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SavedLocationCard(
                  location: loc,
                  onToggle: () => onToggle(loc.id),
                  onDelete: () => onDelete(loc.id),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Proximity Suggestion Card ──────────────────────────────────────────────

class _ProximitySuggestionCard extends StatelessWidget {
  const _ProximitySuggestionCard({
    required this.nearestStop,
    required this.onTap,
  });
  final StopPoint nearestStop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppConstants.containerMargin,
          AppConstants.spaceSm,
          AppConstants.containerMargin,
          0,
        ),
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: ColorConstants.transportTube.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            TransportModeIcon(mode: nearestStop.mode, size: 36),
            const SizedBox(width: AppConstants.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you near ${nearestStop.name}?',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to prime your destination stop',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: ColorConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: ColorConstants.primary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom search bar ──────────────────────────────────────────────────────

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
