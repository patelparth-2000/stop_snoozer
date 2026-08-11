import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/color_constants.dart';
import '../../data/models/stop_point.dart';
import '../../data/repositories/route_topology_repository.dart';
import '../shared/widgets/prominent_disclosure_dialog.dart';
import '../shared/widgets/snoozer_button.dart';
import 'components/field_test_panel.dart';
import 'route_select_viewmodel.dart';

/// U4 — mandatory route pre-selection for underground journeys.
///
/// Resolves line → direction → branch into one unambiguous station sequence
/// before the journey starts. Direction is inferred rather than asked, and the
/// branch question is only shown when the topology says the line genuinely
/// splits between these two stops.
class RouteSelectScreen extends StatelessWidget {
  const RouteSelectScreen({
    super.key,
    required this.origin,
    required this.destination,
  });

  final StopPoint origin;
  final StopPoint destination;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RouteSelectCubit()
        ..begin(origin: origin, destination: destination),
      child: const _RouteSelectBody(),
    );
  }
}

class _RouteSelectBody extends StatelessWidget {
  const _RouteSelectBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      appBar: AppBar(
        backgroundColor: ColorConstants.surfaceBase,
        title: Text(
          'Choose Your Route',
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ColorConstants.textPrimary,
          ),
        ),
      ),
      body: BlocBuilder<RouteSelectCubit, RouteSelectState>(
        builder: (context, state) {
          if (state.loading && state.lines.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: ColorConstants.primary),
            );
          }
          if (state.blocker != RouteSelectBlocker.none) {
            return _Blocked(state: state);
          }
          return _Resolver(state: state);
        },
      ),
    );
  }
}

/// Explains precisely why underground tracking is unavailable, and what still
/// works. A vague failure here would leave users trusting an alarm that cannot
/// fire.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.state});
  final RouteSelectState state;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (state.blocker) {
      RouteSelectBlocker.noTopologyData => (
          'Route data not installed',
          'This build has no Underground line map, so stop-by-stop tracking '
              'is unavailable.\n\nGPS tracking still works for above-ground '
              'stops.\n\nTo enable it, rebuild the database with:\n'
              'python tools/build_naptan_db.py --with-topology',
        ),
      RouteSelectBlocker.notConnected => (
          'No direct route',
          'No single line connects these two stops, so the app cannot count '
              'stops for you.\n\nYou can still set a GPS alarm at the '
              'destination — it will fire once you are back above ground.',
        ),
      RouteSelectBlocker.noSensors => (
          'Sensors unavailable',
          'This device has no motion sensor, which underground tracking needs '
              'to detect stops.\n\nGPS alarms work normally above ground.',
        ),
      RouteSelectBlocker.none => ('', ''),
    };

    return Padding(
      padding: const EdgeInsets.all(AppConstants.containerMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: ColorConstants.primary, size: 28),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textPrimary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textSecondary,
              height: 1.5,
            ),
          ),
          const Spacer(),
          SnoozerButton(
            label: 'Use GPS Alarm Instead',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppConstants.spaceMd),
        ],
      ),
    );
  }
}

class _Resolver extends StatelessWidget {
  const _Resolver({required this.state});
  final RouteSelectState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RouteSelectCubit>();

    return ListView(
      padding: const EdgeInsets.all(AppConstants.containerMargin),
      children: [
        _JourneyHeader(state: state),
        const SizedBox(height: AppConstants.spaceLg),

        // ── Line ───────────────────────────────────────────────────────
        if (state.lines.length > 1) ...[
          _Label('Which line?'),
          const SizedBox(height: AppConstants.spaceSm),
          ...state.lines.map((l) => _OptionTile(
                title: l.name,
                subtitle: l.mode,
                selected: state.selectedLineId == l.id,
                onTap: () => cubit.selectLine(l.id),
              )),
          const SizedBox(height: AppConstants.spaceLg),
        ],

        // ── Branch (the Kennington question) ───────────────────────────
        if (state.branchOptions.isNotEmpty) ...[
          _Label('This line splits — which way?'),
          const SizedBox(height: 4),
          Text(
            'Both branches serve your line, so the app cannot tell them apart '
            'from sensors alone until it is too late. Pick one now.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: ColorConstants.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          ...state.branchOptions.map((b) => _OptionTile(
                title: b.label,
                subtitle: b.nextStopName.isEmpty
                    ? null
                    : 'next: ${b.nextStopName}',
                selected: state.selectedBranchId == b.branchId,
                onTap: () => cubit.selectRoute(
                  state.selectedDirection ?? 'inbound',
                  b.branchId,
                ),
              )),
          const SizedBox(height: AppConstants.spaceLg),
        ],

        // ── Resolved plan ──────────────────────────────────────────────
        if (state.isResolved) ...[
          _Label('${state.stopCount} stops'),
          const SizedBox(height: AppConstants.spaceSm),
          _PlanPreview(state: state),
          const SizedBox(height: AppConstants.spaceMd),
          if (!state.hasBarometer) const _NoBarometerNotice(),
          const SizedBox(height: AppConstants.spaceMd),

          if (!state.started) ...[
            _LoggingToggle(
              value: state.sensorLoggingEnabled,
              onChanged: cubit.setSensorLogging,
            ),
            const SizedBox(height: AppConstants.spaceMd),
          ],

          SnoozerButton(
            label: state.started ? 'Tracking Active' : 'Start Tracking',
            onTap: state.started
                ? null
                : () => _startTracking(context, cubit, state),
          ),
          const SizedBox(height: AppConstants.spaceMd),

          // Only meaningful once tracking is running with logging on.
          if (state.started)
            FieldTestPanel(enabled: state.sensorLoggingEnabled),
          const SizedBox(height: AppConstants.spaceLg),
        ] else if (state.loading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: CircularProgressIndicator(color: ColorConstants.primary),
            ),
          ),
      ],
    );
  }

  /// Asks for radio-scan consent once, at first journey setup, then starts.
  ///
  /// The consent is for *reading* nearby Wi-Fi/cell identifiers, which engages
  /// PECR reg. 6 regardless of the fact that nothing is transmitted — the
  /// regulation governs access to information in terminal equipment, not its
  /// onward transmission. Declining is not a blocker: tracking starts either
  /// way, using the pressure and motion sensors and journey timing, which is
  /// what keeps the consent freely given.
  Future<void> _startTracking(
    BuildContext context,
    RouteSelectCubit cubit,
    RouteSelectState state,
  ) async {
    if (!await RouteTopologyRepository.consentAsked()) {
      if (!context.mounted) return;
      final granted =
          await ProminentDisclosureDialog.showRadioScanConsent(context);
      await RouteTopologyRepository.setFingerprintConsent(granted);
    }
    await cubit.startTracking(
      enableSensorLogging: state.sensorLoggingEnabled,
    );
  }
}

class _JourneyHeader extends StatelessWidget {
  const _JourneyHeader({required this.state});
  final RouteSelectState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Endpoint(
            icon: Icons.trip_origin_rounded,
            label: state.origin?.name ?? '—',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            child: Container(
              width: 2,
              height: 14,
              color: ColorConstants.primary.withValues(alpha: 0.4),
            ),
          ),
          _Endpoint(
            icon: Icons.place_rounded,
            label: state.destination?.name ?? '—',
          ),
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ColorConstants.primary),
        const SizedBox(width: AppConstants.spaceSm),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ColorConstants.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.state});
  final RouteSelectState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < state.plan.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.plan[i].isTarget
                          ? ColorConstants.primary
                          : ColorConstants.textDisabled,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(
                    child: Text(
                      state.plan[i].stopName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: state.plan[i].isTarget
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: state.plan[i].isTarget
                            ? ColorConstants.primary
                            : ColorConstants.textSecondary,
                      ),
                    ),
                  ),
                  // Surfacing which legs lack a timing prior matters: those are
                  // the legs where the fusion test runs weaker.
                  if (i > 0 && state.plan[i].runTimeSeconds == null)
                    Tooltip(
                      message: 'No timing data for this leg',
                      child: Icon(Icons.schedule_rounded,
                          size: 12, color: ColorConstants.textDisabled),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NoBarometerNotice extends StatelessWidget {
  const _NoBarometerNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: ColorConstants.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16, color: ColorConstants.error),
          const SizedBox(width: AppConstants.spaceSm),
          Expanded(
            child: Text(
              'This phone has no pressure sensor, so the app cannot confirm '
              'station depth. Tracking will rely on timing alone and will wake '
              'you one stop early rather than risk overshooting.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: ColorConstants.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opt-in for per-journey sensor logging (F1).
///
/// Off by default and honest about the cost: this is a calibration tool, not a
/// user feature, and it writes a file for every journey it runs on.
class _LoggingToggle extends StatelessWidget {
  const _LoggingToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record sensor data for this journey',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Writes a CSV to this device to help tune underground '
                    'accuracy. Nothing is uploaded.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: ColorConstants.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: ColorConstants.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.sora(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: ColorConstants.textSecondary,
          letterSpacing: 0.15,
        ),
      );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXs),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          decoration: BoxDecoration(
            color: selected
                ? ColorConstants.primarySubtle
                : ColorConstants.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: selected
                  ? ColorConstants.primary
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? ColorConstants.primary
                            : ColorConstants.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: ColorConstants.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    size: 18, color: ColorConstants.primary),
            ],
          ),
        ),
      ),
    );
  }
}
