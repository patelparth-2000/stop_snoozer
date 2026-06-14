import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/number_formatters.dart';
import '../../../data/models/stop_point.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class StopResultCard extends StatelessWidget {
  const StopResultCard({
    super.key,
    required this.stop,
    required this.onTap,
    this.showIndicator = false,
    this.query = '',
  });

  final StopPoint stop;
  final VoidCallback onTap;
  final bool showIndicator;
  final String query;

  Color _modeAccent(TransitMode m) => switch (m) {
        TransitMode.tube ||
        TransitMode.dlr ||
        TransitMode.tram =>
          ColorConstants.transportTube,
        TransitMode.bus      => ColorConstants.transportBus,
        _                    => ColorConstants.transportRail,
      };

  @override
  Widget build(BuildContext context) {
    final indicator    = stop.indicator?.trim();
    final hasIndicator = showIndicator && indicator != null && indicator.isNotEmpty;
    final accent       = _modeAccent(stop.mode);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.containerMargin,
          vertical: 3,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border(
            left:   BorderSide(color: accent, width: 3),
            top:    BorderSide(color: ColorConstants.surfaceElevated),
            right:  BorderSide(color: ColorConstants.surfaceElevated),
            bottom: BorderSide(color: ColorConstants.surfaceElevated),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMd,
            vertical: AppConstants.spaceMd,
          ),
          child: Row(
            children: [
              TransportModeIcon(mode: stop.mode, size: 40),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: _HighlightedText(
                            text: stop.name,
                            query: query,
                            baseStyle: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ColorConstants.textPrimary,
                            ),
                            highlightStyle: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ColorConstants.primary,
                            ),
                          ),
                        ),
                        if (hasIndicator) ...[
                          const SizedBox(width: AppConstants.spaceSm),
                          _IndicatorBadge(label: indicator),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TransportModeIcon.label(stop.mode),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: ColorConstants.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              if (stop.distanceKm != null) ...[
                const SizedBox(width: AppConstants.spaceSm),
                Text(
                  '${NumberFormatters.miles(stop.distanceKm!)} ${StringConstants.searchMiles}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: ColorConstants.textDisabled,
                  ),
                ),
              ],
              const SizedBox(width: AppConstants.spaceSm),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: ColorConstants.textDisabled,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Amber character highlighter ────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);
    }

    final lower      = text.toLowerCase();
    final queryLower = query.toLowerCase();
    final spans      = <TextSpan>[];
    int start        = 0;

    while (true) {
      final idx = lower.indexOf(queryLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + queryLower.length),
        style: highlightStyle,
      ));
      start = idx + queryLower.length;
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Indicator badge ────────────────────────────────────────────────────────

class _IndicatorBadge extends StatelessWidget {
  const _IndicatorBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ColorConstants.primarySubtle,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: ColorConstants.primaryGlow, width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ColorConstants.primary,
        ),
      ),
    );
  }
}
