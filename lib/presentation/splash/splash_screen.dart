import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'splash_viewmodel.dart';
import 'components/splash_logo_widget.dart';
import 'components/splash_progress_bar.dart';
import 'components/splash_permission_sheet.dart';
import '../../core/constants/color_constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SplashCubit>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocConsumer<SplashCubit, SplashState>(
        listener: (context, state) {
          if (state.phase == SplashPhase.ready) {
            context.go('/dashboard');
          }
        },
        builder: (context, state) => Stack(
          children: [
            const _Background(),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  const SplashLogoWidget(),
                  const SizedBox(height: 48),
                  if (state.phase == SplashPhase.decompressing ||
                      state.phase == SplashPhase.error)
                    SplashProgressBar(
                      progress: state.progress,
                      error: state.errorMessage,
                    ),
                  const Spacer(),
                ],
              ),
            ),
            if (state.phase == SplashPhase.permissions)
              SplashPermissionSheet(
                locationGranted: state.locationGranted,
                notificationGranted: state.notifGranted,
                batteryGranted: state.batteryGranted,
                onRequestPermissions: () =>
                    context.read<SplashCubit>().requestPermissions(),
                onSkip: () => context.read<SplashCubit>().skipPermissions(),
              ),
          ],
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [ColorConstants.surfaceTertiary, ColorConstants.surfaceBase],
        ),
      ),
    );
  }
}
