import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../../data/repositories/route_topology_repository.dart';
import '../../shared/widgets/prominent_disclosure_dialog.dart';
import '../../shared/widgets/snoozer_button.dart';

/// Consent control and erasure for on-device radio fingerprints.
///
/// Two obligations meet here. PECR reg. 6 requires consent before the app reads
/// Wi-Fi/cell identifiers from the device, and it must be as easy to withdraw as
/// to give — hence a live toggle rather than a one-time prompt. UK GDPR erasure
/// expectations require a delete control even for data that never leaves the
/// phone, which is why withdrawing also wipes what was already learned.
class LearnedDataCard extends StatefulWidget {
  const LearnedDataCard({super.key});

  @override
  State<LearnedDataCard> createState() => _LearnedDataCardState();
}

class _LearnedDataCardState extends State<LearnedDataCard> {
  bool _granted = RouteTopologyRepository.hasFingerprintConsent;
  int _count = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final count = await RouteTopologyRepository().fingerprintCount();
    if (!mounted) return;
    setState(() {
      _count = count;
      _granted = RouteTopologyRepository.hasFingerprintConsent;
    });
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    if (_granted) {
      // Withdrawal is immediate and destructive by design — see class doc.
      await RouteTopologyRepository.setFingerprintConsent(false);
    } else {
      final ok = await ProminentDisclosureDialog.showRadioScanConsent(context);
      if (ok) await RouteTopologyRepository.setFingerprintConsent(true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _erase() async {
    setState(() => _busy = true);
    await RouteTopologyRepository().deleteAllFingerprints();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

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
          Row(
            children: [
              Icon(
                Icons.wifi_find_rounded,
                size: 18,
                color: _granted
                    ? ColorConstants.success
                    : ColorConstants.textSecondary,
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Text(
                  'On-device station learning',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _granted,
                onChanged: _busy ? null : (_) => _toggle(),
                activeThumbColor: ColorConstants.primary,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            _granted
                ? 'StopSnoozer is learning which Wi-Fi and mobile-cell '
                    'identifiers are visible at each station, to recognise them '
                    'faster next time. Stored on this device only, never sent '
                    'anywhere.'
                : 'Off. Arrival detection uses only the pressure and motion '
                    'sensors and journey timing. No radio identifiers are read '
                    'or stored.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            '$_count identifier${_count == 1 ? '' : 's'} learned',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ColorConstants.textPrimary,
            ),
          ),
          if (_count > 0) ...[
            const SizedBox(height: AppConstants.spaceMd),
            SnoozerButton(
              label: 'Erase learned data',
              variant: SnoozerButtonVariant.danger,
              onTap: _busy ? null : _erase,
            ),
          ],
        ],
      ),
    );
  }
}
