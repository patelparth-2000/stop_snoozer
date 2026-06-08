import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../system_health_viewmodel.dart';

class SensorStatusCard extends StatelessWidget {
  const SensorStatusCard({
    super.key,
    required this.label,
    required this.status,
    required this.icon,
  });

  final String label;
  final SensorStatus status;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (status) {
      SensorStatus.online      => ('Online / Active', ColorConstants.success),
      SensorStatus.standby     => ('Standby / Idle',  ColorConstants.textSecondary),
      SensorStatus.unavailable => ('Unavailable',     ColorConstants.error),
    };

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, color: statusColor, size: 20),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: status == SensorStatus.online
                            ? [BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 4)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceXs),
                    Text(
                      statusLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
