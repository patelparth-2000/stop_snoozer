import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../../data/services/platform_channel_service.dart';

/// F1 — field-test controls.
///
/// Sensor logs are only useful if something in them says *when the train
/// actually arrived*. Without ground-truth markers a log is a trace with no
/// reference points, and no threshold can be calibrated from it — so this
/// panel is not a debug nicety, it is what makes the field test work.
///
/// Deliberately large and single-tap: it is used one-handed, standing, on a
/// moving train, often without looking.
class FieldTestPanel extends StatefulWidget {
  const FieldTestPanel({super.key, required this.enabled});

  /// Whether sensor logging was switched on for this journey.
  final bool enabled;

  @override
  State<FieldTestPanel> createState() => _FieldTestPanelState();
}

class _FieldTestPanelState extends State<FieldTestPanel> {
  int _markers = 0;
  String? _logDir;
  DateTime? _lastMark;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _loadDir();
  }

  Future<void> _loadDir() async {
    final d = await PlatformChannelService.instance.getSensorLogDir();
    if (mounted) setState(() => _logDir = d);
  }

  Future<void> _mark(String label) async {
    await PlatformChannelService.instance.markGroundTruth(label: label);
    await HapticFeedback.heavyImpact();   // confirmation without looking
    if (!mounted) return;
    setState(() {
      _markers++;
      _lastMark = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: ColorConstants.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.science_rounded,
                  size: 18, color: ColorConstants.primary),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Text(
                  'Field Test Logging',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.textPrimary,
                  ),
                ),
              ),
              Text(
                '$_markers marked',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: ColorConstants.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            'Tap the moment the train stops at each platform. These markers are '
            'what the recorded sensor data gets scored against.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: ColorConstants.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),

          // Big primary target — used without looking.
          SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: () => _mark('arrival'),
              style: FilledButton.styleFrom(
                backgroundColor: ColorConstants.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text(
                'ARRIVED AT PLATFORM',
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),

          // The negative case: a hold is what the fusion test must reject, and
          // it is the hardest event to tune without labelled examples.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _mark('tunnel_hold_start'),
                  child: Text('Tunnel hold',
                      style: GoogleFonts.sora(fontSize: 11)),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _mark('doors_open'),
                  child: Text('Doors open',
                      style: GoogleFonts.sora(fontSize: 11)),
                ),
              ),
            ],
          ),

          if (_lastMark != null) ...[
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              'Last marker: ${_lastMark!.hour.toString().padLeft(2, '0')}:'
              '${_lastMark!.minute.toString().padLeft(2, '0')}:'
              '${_lastMark!.second.toString().padLeft(2, '0')}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: ColorConstants.success,
              ),
            ),
          ],
          if (_logDir != null) ...[
            const SizedBox(height: AppConstants.spaceSm),
            const Divider(color: Color(0xFF1E293B), height: 1),
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              'Logs are written to:',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: ColorConstants.textSecondary,
              ),
            ),
            SelectableText(
              _logDir!,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: ColorConstants.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
