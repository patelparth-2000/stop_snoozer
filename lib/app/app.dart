import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/color_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_scope.dart';
import '../core/theme/theme_service.dart';
import 'router/app_router.dart';

class StopSnoozerApp extends StatelessWidget {
  const StopSnoozerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (_, _) {
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: ColorConstants.surfaceBase,
          systemNavigationBarIconBrightness: Brightness.light,
        ));
        return MaterialApp.router(
          title: 'StopSnoozer',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: appRouter,
          builder: (context, child) => ThemeScope(child: child!),
        );
      },
    );
  }
}
