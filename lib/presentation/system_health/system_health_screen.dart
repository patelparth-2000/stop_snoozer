import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'system_health_viewmodel.dart';
import 'components/sensor_status_card.dart';
import 'components/alarm_self_test_card.dart';
import 'components/attribution_card.dart';
import 'components/learned_data_card.dart';
import 'components/oem_battery_card.dart';
import '../../core/constants/color_constants.dart';
import '../../core/theme/theme_scope.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/platform_channel_service.dart';
import '../../data/services/stop_points_db.dart';
import '../shared/widgets/snoozer_button.dart';

class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<SystemHealthCubit, SystemHealthState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              // Header — no back button since this is a persistent tab
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.containerMargin,
                  vertical: AppConstants.spaceMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'System Permissions & Background Compliance',
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ColorConstants.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _SettingsContent(state: state),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppConstants.containerMargin,
                  0,
                  AppConstants.containerMargin,
                  AppConstants.spaceMd + MediaQuery.of(context).padding.bottom,
                ),
                child: Text(
                  StringConstants.healthVersion,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: ColorConstants.textDisabled,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatefulWidget {
  const _SettingsContent({required this.state});
  final SystemHealthState state;

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SystemHealthCubit>().init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed && mounted) {
      context.read<SystemHealthCubit>().init();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SystemHealthCubit>();
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      children: [

        // ── OS Bypass Authorization ─────────────────────────────────────
        _SectionLabel('OS Bypass Authorization'),
        const SizedBox(height: AppConstants.spaceSm),

        // Battery optimization card
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          decoration: BoxDecoration(
            color: ColorConstants.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusDot(granted: state.batteryOptimizationGranted),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(
                    child: Text(
                      StringConstants.healthBatteryTitle,
                      style: GoogleFonts.sora(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ColorConstants.textPrimary,
                      ),
                    ),
                  ),
                  _StatusBadge(granted: state.batteryOptimizationGranted),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                'Custom manufacturer software can kill background tracking. '
                'Whitelist StopSnoozer to guarantee alarms fire while asleep.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ColorConstants.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              SnoozerButton(
                label: state.batteryOptimizationGranted
                    ? 'Whitelist Active'
                    : StringConstants.healthBatteryGrant,
                onTap: state.batteryOptimizationGranted
                    ? null
                    : cubit.requestBatteryOptimization,
                isLoading: state.isRequestingBattery,
                variant: state.batteryOptimizationGranted
                    ? SnoozerButtonVariant.secondary
                    : SnoozerButtonVariant.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceSm),

        // A9 — manufacturer killer, shown only where one is known to exist
        OemBatteryCard(state: state),
        if (state.oemName != null && state.oemSettingsAvailable)
          const SizedBox(height: AppConstants.spaceSm),

        // NOTE: the former "DND bypass" toggle was removed, not fixed.
        //
        // It only flipped local state — no notification-policy access was ever
        // requested — so it advertised a guarantee the app did not have. That is
        // the worst class of bug in an alarm app: a promise relied on while
        // asleep.
        //
        // It is also unnecessary. The alarm is played with
        // AudioAttributes.USAGE_ALARM, and Android's default Do Not Disturb
        // configuration permits alarms through. Combined with the full-screen
        // intent, the user is woken without needing ACCESS_NOTIFICATION_POLICY
        // at all. Only the *visual* notification would need channel DND bypass,
        // which is not worth a sensitive permission and a consent flow.
        const _DndInfoCard(),
        const SizedBox(height: AppConstants.spaceLg),

        // ── A10 — will an alarm actually fire here? ─────────────────────
        _SectionLabel('Alarm Delivery Verification'),
        const SizedBox(height: AppConstants.spaceSm),
        AlarmSelfTestCard(state: state),
        const SizedBox(height: AppConstants.spaceLg),

        // ── Hardware Sensor Diagnostics ─────────────────────────────────
        _SectionLabel('Hardware Sensor Diagnostics'),
        const SizedBox(height: AppConstants.spaceSm),

        _PermissionStatusCard(
          label: 'Background Location Lifecycle (Always Allow)',
          granted: state.gpsStatus == SensorStatus.online,
        ),
        const SizedBox(height: AppConstants.spaceSm),

        SensorStatusCard(
          label: StringConstants.healthGpsLabel,
          status: state.gpsStatus,
          icon: Icons.gps_fixed_rounded,
        ),
        const SizedBox(height: AppConstants.spaceSm),
        SensorStatusCard(
          label: StringConstants.healthWifiLabel,
          status: state.wifiStatus,
          icon: Icons.wifi_rounded,
        ),
        const SizedBox(height: AppConstants.spaceSm),
        SensorStatusCard(
          label: 'Underground Detection (Wi-Fi SSID Scanning)',
          status: state.undergroundStatus,
          icon: Icons.explore_rounded,
        ),
        const SizedBox(height: AppConstants.spaceLg),

        // ── Alarm Preferences ──────────────────────────────────────────
        _SectionLabel('Alarm Preferences'),
        const SizedBox(height: AppConstants.spaceSm),
        const _AlarmPreferencesCard(),
        const SizedBox(height: AppConstants.spaceLg),

        // ── Offline Storage Status ──────────────────────────────────────
        _SectionLabel('Offline Storage Status'),
        const SizedBox(height: AppConstants.spaceSm),

        // Real values queried from the database.
        //
        // These were previously hardcoded strings ('16.5 MB', '353,363 nodes'),
        // which would have gone stale the moment the asset was regenerated.
        //
        // The old "Verify 16 KB Page Size Alignment" button is also gone: it
        // waited 1.2 s and then unconditionally reported success, checking
        // nothing. Alignment is a property of the *built artifact*, not the
        // running device, so a runtime check is meaningless by construction. It
        // now lives in tools/check_16kb_alignment.sh for the release pipeline.
        const _StorageStatsCard(),
        const SizedBox(height: AppConstants.spaceLg),

        // ── Privacy controls ────────────────────────────────────────────
        // Consent given at first journey setup is revocable here, and
        // revoking erases what was learned under it.
        _SectionLabel('Privacy & Learned Data'),
        const SizedBox(height: AppConstants.spaceSm),
        const LearnedDataCard(),
        const SizedBox(height: AppConstants.spaceLg),

        // ── A12 — data attribution (OGL v3.0 / TfL: legally required) ────
        _SectionLabel('Data Sources & Licences'),
        const SizedBox(height: AppConstants.spaceSm),
        const AttributionCard(),
        const SizedBox(height: AppConstants.spaceLg),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Live database statistics, queried rather than hardcoded.
///
/// Also surfaces whether route topology is present at all — without it
/// underground tracking silently degrades to GPS, which is otherwise invisible
/// to the user.
class _StorageStatsCard extends StatefulWidget {
  const _StorageStatsCard();

  @override
  State<_StorageStatsCard> createState() => _StorageStatsCardState();
}

class _StorageStatsCardState extends State<_StorageStatsCard> {
  DbStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StopPointsDb.instance.stats();
    if (mounted) setState(() => _stats = s);
  }

  static String _fmtInt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _fmtBytes(int b) => b <= 0
      ? '—'
      : b >= 1000000
          ? '${(b / 1000000).toStringAsFixed(1)} MB'
          : '${(b / 1000).toStringAsFixed(0)} kB';

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: s == null
          ? SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: ColorConstants.primary),
                ),
              ),
            )
          : !s.available
              ? Text(
                  'Database not yet initialised.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: ColorConstants.textSecondary),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StorageRow(
                        label: 'Stops indexed',
                        value: _fmtInt(s.stopCount)),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Database size',
                        value: _fmtBytes(s.fileSizeBytes)),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Page size',
                        value: '${_fmtInt(s.pageSizeBytes)} B'),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Schema version',
                        value: 'v${s.schemaVersion}'),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Fast search index',
                        value: s.hasFtsIndex ? 'FTS5 active' : 'not built'),
                    const SizedBox(height: AppConstants.spaceSm),
                    const Divider(color: Color(0xFF1E293B), height: 1),
                    const SizedBox(height: AppConstants.spaceSm),
                    _StorageRow(
                        label: 'Route sequences',
                        value: s.hasTopology
                            ? _fmtInt(s.routeSequenceCount)
                            : 'none'),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Inter-station times',
                        value: _fmtInt(s.runTimeCount)),
                    const SizedBox(height: AppConstants.spaceXs),
                    _StorageRow(
                        label: 'Platform depths',
                        value: _fmtInt(s.stationDepthCount)),
                    if (!s.hasTopology) ...[
                      const SizedBox(height: AppConstants.spaceSm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: ColorConstants.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'No Underground route map installed — stop-by-stop '
                              'tracking is unavailable. GPS alarms work normally.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: ColorConstants.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
    );
  }
}

/// States plainly how the alarm behaves under Do Not Disturb.
///
/// Replaces a toggle that did nothing. Informational rather than interactive
/// because there is genuinely nothing for the user to configure: alarm-attributed
/// audio already plays through DND by default.
class _DndInfoCard extends StatelessWidget {
  const _DndInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.do_not_disturb_on_outlined,
              size: 18, color: ColorConstants.success),
          const SizedBox(width: AppConstants.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Works with Do Not Disturb',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your stop alarm plays as an alarm, so Android lets it '
                  'through Do Not Disturb without any extra permission — the '
                  'same way your clock alarm does. Nothing to configure.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: ColorConstants.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.sora(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: ColorConstants.textSecondary,
        letterSpacing: 0.15,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.granted});
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: granted
            ? const Color(0xFF10B981) // Mint Green = authorized
            : const Color(0xFFFF6B6B), // Coral Red = restricted
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.granted});
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (granted
                ? const Color(0xFF10B981)
                : const Color(0xFFFF6B6B))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        granted ? 'AUTHORIZED' : 'RESTRICTED',
        style: GoogleFonts.sora(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: granted
              ? const Color(0xFF10B981)
              : const Color(0xFFFF6B6B),
        ),
      ),
    );
  }
}

class _PermissionStatusCard extends StatelessWidget {
  const _PermissionStatusCard({
    required this.label,
    required this.granted,
  });
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          _StatusDot(granted: granted),
          const SizedBox(width: AppConstants.spaceSm),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ColorConstants.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSm),
          _StatusBadge(granted: granted),
        ],
      ),
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: ColorConstants.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ColorConstants.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Alarm Preferences Card ─────────────────────────────────────────────────

class _AlarmPreferencesCard extends StatefulWidget {
  const _AlarmPreferencesCard();

  @override
  State<_AlarmPreferencesCard> createState() => _AlarmPreferencesCardState();
}

class _AlarmPreferencesCardState extends State<_AlarmPreferencesCard> {
  String _alarmType    = 'both';
  String _ringtoneName = 'Default Alarm';
  bool   _loading      = true;
  bool   _picking      = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await PlatformChannelService.instance.getAlarmSettings();
    if (!mounted) return;
    setState(() {
      _alarmType    = s['alarmType']    ?? 'both';
      _ringtoneName = s['ringtoneName'] ?? 'Default Alarm';
      _loading      = false;
    });
  }

  Future<void> _setType(String type) async {
    setState(() => _alarmType = type);
    await PlatformChannelService.instance.setAlarmSettings(alarmType: type);
  }

  Future<void> _pickTone() async {
    setState(() => _picking = true);
    final result = await PlatformChannelService.instance.openRingtonePicker();
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (result != null) _ringtoneName = result['name'] ?? _ringtoneName;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Center(
          child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2,
              color: ColorConstants.primary)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Alert style ──────────────────────────────────
          Text('Alert Style',
            style: GoogleFonts.sora(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: ColorConstants.textPrimary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Row(children: [
            _TypeChip(label: 'Screen',       value: 'screen',       selected: _alarmType, onTap: _setType),
            const SizedBox(width: 8),
            _TypeChip(label: 'Notification', value: 'notification', selected: _alarmType, onTap: _setType),
            const SizedBox(width: 8),
            _TypeChip(label: 'Both',         value: 'both',         selected: _alarmType, onTap: _setType),
          ]),
          const SizedBox(height: 4),
          Text(
            _alarmType == 'screen'
                ? 'Alarm screen opens — no notification banner.'
                : _alarmType == 'notification'
                    ? 'Notification with Stop button — no full-screen takeover.'
                    : 'Alarm screen + notification banner with Stop button.',
            style: GoogleFonts.inter(fontSize: 11, color: ColorConstants.textSecondary),
          ),

          const SizedBox(height: AppConstants.spaceMd),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: AppConstants.spaceMd),

          // ── Alarm tone ───────────────────────────────────
          Row(
            children: [
              Icon(Icons.music_note_rounded,
                  color: ColorConstants.primary, size: 18),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alarm Tone',
                      style: GoogleFonts.sora(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: ColorConstants.textPrimary,
                      ),
                    ),
                    Text(_ringtoneName,
                      style: GoogleFonts.inter(
                        fontSize: 11, color: ColorConstants.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              GestureDetector(
                onTap: _picking ? null : _pickTone,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ColorConstants.primarySubtle,
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(color: ColorConstants.primaryGlow),
                  ),
                  child: _picking
                      ? SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ColorConstants.primary))
                      : Text('Change',
                          style: GoogleFonts.sora(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: ColorConstants.primary,
                          )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String value;
  final String selected;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ColorConstants.primarySubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: active ? ColorConstants.primary : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? ColorConstants.primary : ColorConstants.textSecondary,
          ),
        ),
      ),
    );
  }
}
