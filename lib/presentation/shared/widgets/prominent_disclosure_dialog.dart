import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import 'snoozer_button.dart';

/// A consent dialog that must be accepted before a sensitive OS prompt is shown.
///
/// Two rules govern every use of this widget, and both come from policy rather
/// than taste:
///
/// * The OS permission request must be made **only** on a `true` result. Play's
///   most common background-location rejection is literally "BACKGROUND_LOCATION
///   permission user consent/runtime requested before Prominent Disclosure".
/// * Dismissal must not read as consent. [barrierDismissible] is false and a
///   back gesture resolves to `false`, so navigating away denies.
class ProminentDisclosureDialog extends StatelessWidget {
  const ProminentDisclosureDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
    required this.allowLabel,
    required this.denyLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final String footer;
  final String allowLabel;
  final String denyLabel;

  /// Background-location disclosure, worded to Play's prescribed form.
  ///
  /// Returns `true` only on an affirmative tap. Call
  /// `Permission.locationAlways.request()` if and only if this returned `true`.
  static Future<bool> showBackgroundLocation(BuildContext context) =>
      _show(
        context,
        const ProminentDisclosureDialog(
          icon: Icons.my_location_rounded,
          title: StringConstants.discloseBgTitle,
          body: StringConstants.discloseBgBody,
          footer: StringConstants.discloseBgFooter,
          allowLabel: StringConstants.discloseBgAllow,
          denyLabel: StringConstants.discloseBgDeny,
        ),
      );

  /// Consent to read nearby Wi-Fi/cell identifiers.
  ///
  /// Separate from the location disclosure because it answers a different
  /// question: PECR reg. 6 governs *accessing* information held in terminal
  /// equipment, so device-local-only processing does not exempt it. Denying
  /// leaves the app fully functional, which is what makes the consent freely
  /// given.
  static Future<bool> showRadioScanConsent(BuildContext context) =>
      _show(
        context,
        const ProminentDisclosureDialog(
          icon: Icons.wifi_find_rounded,
          title: StringConstants.consentRadioTitle,
          body: StringConstants.consentRadioBody,
          footer: StringConstants.consentRadioFooter,
          allowLabel: StringConstants.consentRadioAllow,
          denyLabel: StringConstants.consentRadioDeny,
        ),
      );

  static Future<bool> _show(BuildContext context, Widget dialog) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: dialog),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ColorConstants.surfaceModal,
      insetPadding: const EdgeInsets.all(AppConstants.containerMargin),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ColorConstants.primarySubtle,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Icon(icon, color: ColorConstants.primary, size: 24),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: ColorConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: ColorConstants.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Container(
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              decoration: BoxDecoration(
                color: ColorConstants.surfaceElevated,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Text(
                footer,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ColorConstants.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            SnoozerButton(
              label: allowLabel,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            SnoozerButton(
              label: denyLabel,
              variant: SnoozerButtonVariant.ghost,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
