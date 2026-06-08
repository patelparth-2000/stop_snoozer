import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/stop_point.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class TransportChipsRow extends StatelessWidget {
  const TransportChipsRow({
    super.key,
    required this.stops,
    this.onStopTap,
  });

  final List<StopPoint> stops;
  final void Function(StopPoint)? onStopTap;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
        itemCount: stops.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppConstants.spaceSm),
        itemBuilder: (_, i) => _TransportChip(
          stop: stops[i],
          onTap: () => onStopTap?.call(stops[i]),
        ),
      ),
    );
  }
}

class _TransportChip extends StatelessWidget {
  const _TransportChip({required this.stop, required this.onTap});
  final StopPoint stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceXs,
        ),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(color: ColorConstants.surfaceElevated, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TransportModeIcon(mode: stop.mode, size: 16),
            const SizedBox(width: AppConstants.spaceXs),
            Text(
              TransportModeIcon.label(stop.mode),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: ColorConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
