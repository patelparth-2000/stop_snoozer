import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';
import '../../../data/models/saved_location.dart';
import '../../shared/widgets/transport_mode_icon.dart';

class SavedLocationCard extends StatelessWidget {
  const SavedLocationCard({
    super.key,
    required this.location,
    required this.onToggle,
    required this.onDelete,
  });

  final SavedLocation location;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final active = location.isActive;
    return Dismissible(
      key: ValueKey(location.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spaceLg),
        decoration: BoxDecoration(
          color: const Color(0xFF7F1D1D),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 20),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border(
            left: active
                ? BorderSide(color: ColorConstants.primary, width: 3)
                : BorderSide(color: ColorConstants.surfaceElevated),
            top: BorderSide(color: ColorConstants.surfaceElevated),
            right: BorderSide(color: ColorConstants.surfaceElevated),
            bottom: BorderSide(color: ColorConstants.surfaceElevated),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              TransportModeIcon(
                mode: location.toStopPoint().mode,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.stopName,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? ColorConstants.textPrimary
                            : ColorConstants.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (active) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: ColorConstants.success,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tracking active',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: ColorConstants.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: active,
                onChanged: (_) => onToggle(),
                activeThumbColor: ColorConstants.primary,
                activeTrackColor:
                    ColorConstants.primary.withValues(alpha: 0.2),
                inactiveThumbColor: ColorConstants.textDisabled,
                inactiveTrackColor: ColorConstants.surfaceElevated,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
