import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'splash_viewmodel.dart';
import 'components/splash_logo_widget.dart';
import 'components/splash_progress_bar.dart';
import 'components/splash_permission_sheet.dart';
import '../shared/widgets/prominent_disclosure_dialog.dart';
import '../../core/constants/color_constants.dart';
import '../../data/blocs/database_init_handler.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocListener<DatabaseInitHandler, DatabaseInitState>(
        listener: (context, dbState) {
          if (dbState is DatabaseReadyState) {
            context.read<SplashCubit>().checkPermissions();
          }
        },
        child: BlocConsumer<SplashCubit, SplashState>(
          listener: (context, state) {
            if (state.phase == SplashPhase.ready) {
              context.go('/dashboard');
            }
          },
          builder: (context, splashState) => Stack(
            children: [
              const _Background(),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    const SplashLogoWidget(),
                    const SizedBox(height: 48),
                    BlocBuilder<DatabaseInitHandler, DatabaseInitState>(
                      builder: (context, dbState) {
                        if (dbState is DatabaseDecompressingState) {
                          return SplashProgressBar(
                            progress: dbState.progressPercentage,
                            error: null,
                          );
                        }
                        if (dbState is DatabaseErrorState) {
                          return SplashProgressBar(
                            progress: 0.0,
                            error: dbState.errorMessage,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              if (splashState.phase == SplashPhase.permissions)
                SplashPermissionSheet(
                  locationGranted: splashState.locationGranted,
                  bgLocationGranted: splashState.bgLocationGranted,
                  notificationGranted: splashState.notifGranted,
                  batteryGranted: splashState.batteryGranted,
                  fullScreenIntentGranted: splashState.fullScreenIntentGranted,
                  bgDisclosureDeclined: splashState.bgDisclosureDeclined,
                  onRequestPermissions: () =>
                      context.read<SplashCubit>().requestPermissions(
                            // The disclosure is shown from here, immediately
                            // before the OS background-location prompt, which
                            // is where Play requires it to appear.
                            onDiscloseBackgroundLocation: () =>
                                ProminentDisclosureDialog
                                    .showBackgroundLocation(context),
                          ),
                  onSkip: () => context.read<SplashCubit>().skipPermissions(),
                ),
            ],
          ),
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
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [ColorConstants.surfaceTertiary, ColorConstants.surfaceBase],
        ),
      ),
    );
  }
}
