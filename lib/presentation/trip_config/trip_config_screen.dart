import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'trip_config_viewmodel.dart';
import 'components/trip_leg_config_card.dart';
import 'components/trip_config_footer.dart';
import '../../core/constants/color_constants.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/trip_group.dart';
import '../dashboard/dashboard_viewmodel.dart';

class TripConfigScreen extends StatelessWidget {
  const TripConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final cubit = context.read<TripConfigCubit>();
        final confirmed = cubit.state.hasLegs
            ? await _confirmLeave(context)
            : true;
        if (confirmed && context.mounted) context.go('/dashboard');
      },
      child: Scaffold(
        backgroundColor: ColorConstants.surfaceBase,
        body: BlocBuilder<TripConfigCubit, TripConfigState>(
          builder: (context, state) => SafeArea(
            child: Column(
              children: [
                _Header(state: state),
                _ModeToggle(mode: state.queueMode),
                Expanded(
                  child: state.queueMode == QueueMode.singleStop
                      ? _SingleStopPane(state: state)
                      : _TripGroupPane(groups: state.savedGroups),
                ),
                TripConfigFooter(
                  canArm: state.hasLegs && state.queueMode == QueueMode.singleStop,
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
      ),
    );
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: ColorConstants.surfaceSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            title: Text(
              'Leave queue?',
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textPrimary,
              ),
            ),
            content: Text(
              'Your current stops will be cleared.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ColorConstants.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Stay',
                    style: GoogleFonts.inter(color: ColorConstants.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Leave',
                    style: GoogleFonts.inter(
                        color: Colors.redAccent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _arm(BuildContext context, TripConfigState state) {
    final legs = context.read<TripConfigCubit>().buildArmedLegs();
    context.read<DashboardCubit>().loadTrip(legs);
    context.go('/dashboard');
  }

  static void showAddLegPicker(BuildContext context, List<TripGroup> groups) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => BlocProvider.value(
        value: context.read<TripConfigCubit>(),
        child: _AddLegSheet(groups: groups),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final TripConfigState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceMd,
      ),
      child: Row(
        children: [
          Text(
            StringConstants.tripConfigTitle,
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ColorConstants.textPrimary,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          if (state.hasLegs && state.queueMode == QueueMode.singleStop)
            GestureDetector(
              onTap: () => _showSaveGroupDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ColorConstants.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_add_outlined,
                        color: ColorConstants.primary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Save Group',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ColorConstants.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSaveGroupDialog(BuildContext context) {
    final ctrl  = TextEditingController();
    // Capture cubit before the dialog's async gap so context stays valid.
    final cubit = context.read<TripConfigCubit>();
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: ColorConstants.surfaceSecondary,
        title: Text('Save as Trip Group',
            style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 14, color: ColorConstants.textPrimary),
          decoration: InputDecoration(
            hintText: 'Group name…',
            hintStyle: GoogleFonts.inter(
                fontSize: 13, color: ColorConstants.textDisabled),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ColorConstants.surfaceElevated)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: ColorConstants.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: ColorConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              cubit.saveCurrentAsGroup(ctrl.text);
              Navigator.pop(dlgCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trip group saved')),
              );
            },
            child: Text('Save',
                style: GoogleFonts.inter(
                    color: ColorConstants.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Mode toggle ────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode});
  final QueueMode mode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        0,
        AppConstants.containerMargin,
        AppConstants.spaceSm,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: ColorConstants.surfaceElevated),
        ),
        child: Row(
          children: [
            _tab(context, 'Single Stop', QueueMode.singleStop,
                Icons.pin_drop_outlined),
            _tab(context, 'Trip Group', QueueMode.tripGroup,
                Icons.route_rounded),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    QueueMode tabMode,
    IconData icon,
  ) {
    final active = mode == tabMode;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.read<TripConfigCubit>().setQueueMode(tabMode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? ColorConstants.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd - 2),
            border: active
                ? Border.all(
                    color: ColorConstants.primary.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active
                      ? ColorConstants.primary
                      : ColorConstants.textDisabled),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? ColorConstants.primary
                        : ColorConstants.textDisabled),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Single-stop pane ───────────────────────────────────────────────────────

class _SingleStopPane extends StatelessWidget {
  const _SingleStopPane({required this.state});
  final TripConfigState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripConfigCubit>();
    if (!state.hasLegs) {
      return _EmptyState(groups: state.savedGroups);
    }
    return Column(
      children: [
        Expanded(
          // ReorderableListView directly inside Expanded — no shrinkWrap, no
          // NeverScrollableScrollPhysics, no SliverChildListDelegate wrapper.
          // This is the fix for the blank-screen bug on state rebuild.
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(top: AppConstants.spaceSm),
            onReorder: cubit.reorderLegs,
            itemCount: state.legs.length,
            itemBuilder: (_, i) => TripLegConfigCard(
              key: ValueKey(state.legs[i].stop.id),
              leg: state.legs[i],
              index: i,
              onRadiusChanged: (v) => cubit.updateRadius(i, v),
              onRemove: () => cubit.removeLeg(i),
            ),
          ),
        ),
        _AddLegButton(groups: state.savedGroups),
      ],
    );
  }
}

class _AddLegButton extends StatelessWidget {
  const _AddLegButton({required this.groups});
  final List<TripGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin,
          vertical: AppConstants.spaceSm),
      child: GestureDetector(
        onTap: () => TripConfigScreen.showAddLegPicker(context, groups),
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
              style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.primary),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Trip-group pane ────────────────────────────────────────────────────────

class _TripGroupPane extends StatelessWidget {
  const _TripGroupPane({required this.groups});
  final List<TripGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.containerMargin),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmarks_outlined,
                  color: ColorConstants.textDisabled, size: 48),
              const SizedBox(height: AppConstants.spaceMd),
              Text(
                'No saved groups yet',
                style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textSecondary),
              ),
              const SizedBox(height: AppConstants.spaceXs),
              Text(
                'Switch to Single Stop, add stops,\nthen tap "Save Group" to create one.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 12, color: ColorConstants.textDisabled),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.containerMargin),
      itemCount: groups.length,
      itemBuilder: (_, i) => _GroupCard(group: groups[i]),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final TripGroup group;

  static const _border = Color(0xFF334155);
  static const _card   = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripConfigCubit>();
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: _border),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(Icons.route_rounded,
            color: ColorConstants.primary, size: 20),
        title: Text(group.name,
            style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ColorConstants.textPrimary)),
        subtitle: Text(
          '${group.legs.length} stop${group.legs.length == 1 ? '' : 's'}',
          style: GoogleFonts.inter(
              fontSize: 11, color: ColorConstants.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                cubit.loadGroup(group);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Loaded "${group.name}"')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ColorConstants.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Text('Load',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ColorConstants.primary)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => cubit.deleteGroup(group.id),
              child: Icon(Icons.delete_outline_rounded,
                  color: ColorConstants.textDisabled, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add-leg picker sheet ───────────────────────────────────────────────────

class _AddLegSheet extends StatelessWidget {
  const _AddLegSheet({required this.groups});
  final List<TripGroup> groups;

  static const _card   = Color(0xFF0F172A);
  static const _amber  = Color(0xFFFFB000);
  static const _slate  = Color(0xFFE2E8F0);
  static const _muted  = Color(0xFF64748B);
  static const _border = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripConfigCubit>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Add a Leg',
                style: GoogleFonts.sora(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _slate)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                context.go('/search');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: _amber.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: _amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Search a Stop',
                              style: GoogleFonts.sora(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _amber)),
                          Text('Find by name or postcode',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: _muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: _amber, size: 14),
                  ],
                ),
              ),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('OR LOAD A SAVED GROUP',
                  style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _muted,
                      letterSpacing: 0.15)),
              const SizedBox(height: 8),
              ...groups.map(
                (g) => GestureDetector(
                  onTap: () {
                    cubit.loadGroup(g);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Loaded "${g.name}"'),
                        backgroundColor: const Color(0xFF1E293B),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route_rounded,
                            color: _amber, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.name,
                                  style: GoogleFonts.sora(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _slate)),
                              Text(
                                  '${g.legs.length} stop${g.legs.length == 1 ? '' : 's'}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: _muted)),
                            ],
                          ),
                        ),
                        const Icon(Icons.download_rounded,
                            color: _muted, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.groups});
  final List<TripGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_add_rounded,
              color: ColorConstants.textDisabled, size: 48),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            'No stops added yet',
            style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ColorConstants.textSecondary),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          GestureDetector(
            onTap: () => TripConfigScreen.showAddLegPicker(context, groups),
            child: Text(
              StringConstants.tripConfigAddLeg,
              style: GoogleFonts.inter(
                  fontSize: 13, color: ColorConstants.primary),
            ),
          ),
        ],
      ),
    );
  }
}
