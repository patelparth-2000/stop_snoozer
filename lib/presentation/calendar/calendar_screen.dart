import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/alarm_event.dart';
import '../../data/models/commute_alarm.dart';
import 'calendar_viewmodel.dart';
import 'components/alarm_card.dart';
import 'components/create_alarm_sheet.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/color_constants.dart';
import '../../core/theme/theme_scope.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommuteAlarmsCubit>().load();
    });
  }

  void _openCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<CommuteAlarmsCubit>(),
        child: const CreateAlarmSheet(),
      ),
    );
  }

  void _openEditSheet(CommuteAlarm alarm) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<CommuteAlarmsCubit>(),
        child: CreateAlarmSheet(initialAlarm: alarm),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<CommuteAlarmsCubit, CommuteAlarmsState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              _Header(onAdd: _openCreateSheet),
              Expanded(
                child: state.isLoading
                    ? const _LoadingView()
                    : _ContentView(state: state, onEdit: _openEditSheet),
              ),
              const _InfoBanner(),
              _Footer(onDashboard: () => context.go('/dashboard')),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'COMMUTE ALARMS',
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.primary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Scheduled Windows',
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: ColorConstants.primary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: ColorConstants.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded,
                      color: ColorConstants.surfaceBase, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColorConstants.surfaceBase,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Combined content view (alarms + history) ───────────────────────────────

class _ContentView extends StatelessWidget {
  const _ContentView({required this.state, required this.onEdit});
  final CommuteAlarmsState state;
  final void Function(CommuteAlarm) onEdit;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CommuteAlarmsCubit>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceSm,
        AppConstants.containerMargin,
        AppConstants.spaceLg,
      ),
      children: [
        if (state.alarms.isEmpty)
          _EmptyAlarms()
        else
          ...state.alarms.map((alarm) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AlarmCard(
                  alarm: alarm,
                  onToggle: () => cubit.toggle(alarm.id),
                  onDelete: () => cubit.delete(alarm.id),
                  onEdit: () => onEdit(alarm),
                ),
              )),

        if (state.history.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spaceLg),
          _HistorySection(
            history: state.history,
            onClear: cubit.clearHistory,
          ),
        ],
      ],
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.alarm_off_rounded,
              color: ColorConstants.textDisabled, size: 44),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            'No scheduled commutes',
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ColorConstants.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            "Tap 'Add' to automate your tracking windows.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textDisabled,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── History section ─────────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history, required this.onClear});
  final List<AlarmEvent> history;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RECENT ACTIVITY',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textDisabled,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onClear,
              child: Text(
                'Clear all',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: ColorConstants.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSm),
        ...history.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _HistoryTile(event: e),
            )),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.event});
  final AlarmEvent event;

  String _formatTime(DateTime dt) {
    final h    = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min  = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[dt.weekday - 1]} ${dt.day}/${dt.month}  $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final dist = event.distanceMetres;
    final distLabel = dist < 10 ? 'at stop' : '${dist.round()} m away';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: ColorConstants.surfaceElevated),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ColorConstants.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.stopName,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatTime(event.firedAt),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: ColorConstants.textDisabled,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            distLabel,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ColorConstants.success,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading ─────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ColorConstants.primary,
        ),
      ),
    );
  }
}

// ── Info banner ─────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceSm,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border(
          left:   BorderSide(color: ColorConstants.primary, width: 3),
          top:    BorderSide(color: ColorConstants.surfaceElevated),
          right:  BorderSide(color: ColorConstants.surfaceElevated),
          bottom: BorderSide(color: ColorConstants.surfaceElevated),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                color: ColorConstants.primary, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tracking starts precisely at your configured departure times. '
                'StopSnoozer stays dormant outside these windows, '
                'drawing zero background battery.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ColorConstants.textDisabled,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ──────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onDashboard});
  final VoidCallback onDashboard;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceXs,
        AppConstants.containerMargin,
        AppConstants.spaceMd + bottomPad,
      ),
      child: GestureDetector(
        onTap: onDashboard,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_back_ios_new_rounded,
                size: 11, color: ColorConstants.textDisabled),
            const SizedBox(width: 4),
            Text(
              'Back to Dashboard',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: ColorConstants.textDisabled,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
