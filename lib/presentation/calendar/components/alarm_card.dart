import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/commute_alarm.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/color_constants.dart';

class AlarmCard extends StatelessWidget {
  const AlarmCard({
    super.key,
    required this.alarm,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  final CommuteAlarm alarm;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final active = alarm.isActive;
    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spaceLg),
        decoration: BoxDecoration(
          color: const Color(0xFF7F1D1D),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ColorConstants.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border(
            left: active
                ? BorderSide(color: ColorConstants.primary, width: 3)
                : BorderSide(color: ColorConstants.surfaceElevated),
            top:    BorderSide(color: ColorConstants.surfaceElevated),
            right:  BorderSide(color: ColorConstants.surfaceElevated),
            bottom: BorderSide(color: ColorConstants.surfaceElevated),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Time + edit + toggle ───────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    alarm.timeLabel,
                    style: GoogleFonts.sora(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? ColorConstants.textPrimary
                          : ColorConstants.textDisabled,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: ColorConstants.surfaceElevated,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusSm),
                      ),
                      child: Icon(
                        Icons.edit_rounded,
                        color: ColorConstants.textDisabled,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
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

              const SizedBox(height: 4),

              // ── Row 2: Route label ─────────────────────────────────────
              Row(
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: active
                        ? ColorConstants.textSecondary
                        : ColorConstants.textDisabled,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${alarm.modeEmoji}  ${alarm.routeLabel}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: active
                            ? ColorConstants.textSecondary
                            : ColorConstants.textDisabled,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.spaceSm),

              // ── Row 3: Day chips or one-off ────────────────────────────
              if (alarm.specificDate != null)
                _OneOffChip(
                    label: alarm.specificDateLabel, active: active)
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: alarm.dayChips
                      .map((c) => _DayPill(chip: c, alarmActive: active))
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _DayPill extends StatelessWidget {
  const _DayPill({required this.chip, required this.alarmActive});
  final DayChip chip;
  final bool alarmActive;

  @override
  Widget build(BuildContext context) {
    final active = chip.active && alarmActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? ColorConstants.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: active
              ? ColorConstants.primary.withValues(alpha: 0.6)
              : ColorConstants.surfaceElevated,
          width: 1,
        ),
      ),
      child: Text(
        chip.label,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          color:
              active ? ColorConstants.primary : ColorConstants.textDisabled,
        ),
      ),
    );
  }
}

class _OneOffChip extends StatelessWidget {
  const _OneOffChip({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? ColorConstants.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: active
              ? ColorConstants.primary.withValues(alpha: 0.5)
              : ColorConstants.surfaceElevated,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: active
              ? ColorConstants.primary
              : ColorConstants.textDisabled,
        ),
      ),
    );
  }
}
