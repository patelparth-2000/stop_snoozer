import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'alarm_viewmodel.dart';
import 'components/alarm_header.dart';
import 'components/alarm_destination_info.dart';
import 'components/slide_to_dismiss_bar.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/app_constants.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final Animation<Color?> _bgColor;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppConstants.durationPulse),
    )..repeat(reverse: true);
    _bgColor = ColorTween(
      begin: ColorConstants.surfaceBase,
      end: const Color(0xFF1A0A00),
    ).animate(CurveTween(curve: Curves.easeInOut).animate(_bgCtrl));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AlarmCubit, AlarmState>(
      listenWhen: (prev, curr) =>
          (curr.isDismissed && !prev.isDismissed) ||
          (curr.isSnoozed && !prev.isSnoozed),
      listener: (context, state) {
        if (state.isDismissed || state.isSnoozed) {
          if (state.isSnoozed) {
            context.go('/dashboard');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Snoozed ${state.snoozeMinutes} min — alarm will re-check your location',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            context.go('/dashboard');
          }
        }
      },
      builder: (context, state) {
        if (!state.isRinging) {
          return _CountdownScreen(
            stop: state.stop.name,
            seconds: state.countdownSeconds,
            onDismiss: context.read<AlarmCubit>().dismiss,
          );
        }

        return AnimatedBuilder(
          animation: _bgColor,
          builder: (_, child) => Scaffold(
            backgroundColor: _bgColor.value,
            body: child,
          ),
          child: _RingingScreen(state: state, cubit: context.read<AlarmCubit>()),
        );
      },
    );
  }
}

// ── Countdown phase ────────────────────────────────────────────────────────

class _CountdownScreen extends StatelessWidget {
  const _CountdownScreen({
    required this.stop,
    required this.seconds,
    required this.onDismiss,
  });

  final String stop;
  final int seconds;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.containerMargin),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    padding: const EdgeInsets.all(AppConstants.spaceSm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: ColorConstants.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Approaching',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: ColorConstants.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                stop,
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: ColorConstants.textPrimary,
                ),
              ),
              const SizedBox(height: AppConstants.spaceXxl),
              // Large countdown circle
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ColorConstants.primary.withValues(alpha: 0.5),
                    width: 3,
                  ),
                  color: ColorConstants.primarySubtle,
                ),
                child: Center(
                  child: Text(
                    '$seconds',
                    style: GoogleFonts.sora(
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                      color: ColorConstants.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
              Text(
                'Alarm starting in $seconds second${seconds == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: ColorConstants.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                'Dismiss now to cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ColorConstants.textDisabled,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ringing phase ──────────────────────────────────────────────────────────

class _RingingScreen extends StatelessWidget {
  const _RingingScreen({required this.state, required this.cubit});

  final AlarmState state;
  final AlarmCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.containerMargin),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: cubit.dismiss,
                child: Container(
                  padding: const EdgeInsets.all(AppConstants.spaceSm),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: ColorConstants.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const Spacer(),
            const AlarmHeader(),
            const SizedBox(height: AppConstants.spaceXxl),
            AlarmDestinationInfo(
              stop: state.stop,
              distanceMetres: state.distanceMetres,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SnoozeChip(minutes: 5,  cubit: cubit),
                const SizedBox(width: 12),
                _SnoozeChip(minutes: 10, cubit: cubit),
              ],
            ),
            const SizedBox(height: AppConstants.spaceLg),
            SlideToDismissBar(
              progress: state.slideProgress,
              onProgressChanged: cubit.updateSlideProgress,
              onDismissed: cubit.dismiss,
            ),
            const SizedBox(height: AppConstants.spaceLg),
          ],
        ),
      ),
    );
  }
}

// ── Snooze chip ────────────────────────────────────────────────────────────

class _SnoozeChip extends StatelessWidget {
  const _SnoozeChip({required this.minutes, required this.cubit});
  final int minutes;
  final AlarmCubit cubit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => cubit.snooze(minutes: minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.snooze_rounded,
                color: ColorConstants.textSecondary, size: 16),
            const SizedBox(width: 6),
            Text(
              'Snooze $minutes min',
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ColorConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
