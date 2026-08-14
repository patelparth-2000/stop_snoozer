import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';

/// A12 — data attribution and licensing.
///
/// This is a legal requirement, not a nicety. NaPTAN is published under the Open
/// Government Licence v3.0, which obliges us to acknowledge the source with the
/// specified attribution statement. TfL's terms additionally require crediting
/// TfL as the source while not implying TfL endorses the app.
///
/// Text is selectable so users can copy the licence URLs — the app has no
/// browser dependency and we would rather not add one just for two links.
class AttributionCard extends StatelessWidget {
  const AttributionCard({super.key});

  static const String oglAttribution =
      'Contains public sector information licensed under the '
      'Open Government Licence v3.0.';

  static const String oglUrl =
      'https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/';

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
          _Source(
            title: 'NaPTAN — National Public Transport Access Nodes',
            body: 'Stop locations and identifiers are derived from NaPTAN, '
                'published by the UK Department for Transport.\n\n'
                '$oglAttribution',
            url: oglUrl,
          ),
          const SizedBox(height: AppConstants.spaceMd),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: AppConstants.spaceMd),
          const _Source(
            title: 'Transport for London',
            body: 'Line, route and station data powered by TfL Open Data. '
                'Platform depths and inter-station running times are derived '
                'from TfL Freedom of Information releases FOI-0493-2223 and '
                'FOI-2748-2223.\n\n'
                'Contains OS data © Crown copyright and database rights. '
                'Contains Geomni UK Map data © and database rights.\n\n'
                'StopSnoozer is an independent app. It is not affiliated with, '
                'endorsed by, or operated by Transport for London.',
            url: 'https://tfl.gov.uk/info-for/open-data-users/',
          ),
          const SizedBox(height: AppConstants.spaceMd),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: AppConstants.spaceMd),
          _Source(
            title: 'Ordnance Survey — OS Terrain 50',
            body: 'Station ground elevations are sampled from OS Terrain 50, '
                'Ordnance Survey OpenData.\n\n'
                'Contains OS data © Crown copyright and database right 2026.\n\n'
                '$oglAttribution',
            url: oglUrl,
          ),
          const SizedBox(height: AppConstants.spaceMd),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: AppConstants.spaceMd),
          const _Source(
            title: 'On-device data & privacy',
            body: 'All stop data, journeys and alarms are stored only on this '
                'device. Nothing is uploaded and there is no account.\n\n'
                'To improve underground detection the app may record nearby '
                'Wi-Fi and mobile-cell identifiers alongside confirmed '
                'stations. These stay on this device and are never transmitted.',
          ),
        ],
      ),
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.title, required this.body, this.url});

  final String title;
  final String body;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ColorConstants.textPrimary,
          ),
        ),
        const SizedBox(height: AppConstants.spaceXs),
        SelectableText(
          body,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: ColorConstants.textSecondary,
            height: 1.5,
          ),
        ),
        if (url != null) ...[
          const SizedBox(height: AppConstants.spaceXs),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  url!,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: ColorConstants.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded,
                    size: 14, color: ColorConstants.textSecondary),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                tooltip: 'Copy link',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url!));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}
