import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
    ).animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgColor,
      builder: (_, child) => Scaffold(
        backgroundColor: _bgColor.value,
        body: child,
      ),
      child: BlocConsumer<AlarmCubit, AlarmState>(
        listener: (context, state) {
          if (state.isDismissed) context.go('/dashboard');
        },
        builder: (context, state) {
          final cubit = context.read<AlarmCubit>();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.containerMargin),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const AlarmHeader(),
                  const SizedBox(height: AppConstants.spaceXxl),
                  AlarmDestinationInfo(
                    stop: state.stop,
                    distanceMetres: state.distanceMetres,
                  ),
                  const Spacer(),
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
        },
      ),
    );
  }
}
