import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/stop_point.dart';
import '../../presentation/splash/splash_screen.dart';
import '../../presentation/splash/splash_viewmodel.dart';
import '../../data/blocs/database_init_handler.dart';
import '../../presentation/dashboard/dashboard_screen.dart';
import '../../presentation/dashboard/dashboard_viewmodel.dart';
import '../../presentation/search/search_screen.dart';
import '../../presentation/search/search_viewmodel.dart';
import '../../presentation/trip_config/trip_config_screen.dart';
import '../../presentation/trip_config/trip_config_viewmodel.dart';
import '../../presentation/alarm/alarm_screen.dart';
import '../../presentation/alarm/alarm_viewmodel.dart';
import '../../presentation/system_health/system_health_screen.dart';
import '../../presentation/system_health/system_health_viewmodel.dart';

// Long-lived Cubits shared across navigation events
final _dashboardCubit  = DashboardCubit();
final _tripConfigCubit = TripConfigCubit();

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    // ── Splash ────────────────────────────────────────────────────────────
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => _page(
        state,
        MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => DatabaseInitHandler()
                ..add(const CheckDatabaseOnBootEvent()),
            ),
            BlocProvider(create: (_) => SplashCubit()),
          ],
          child: const SplashScreen(),
        ),
      ),
    ),

    // ── Dashboard ─────────────────────────────────────────────────────────
    GoRoute(
      path: '/dashboard',
      pageBuilder: (context, state) => _page(
        state,
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: _dashboardCubit),
            BlocProvider.value(value: _tripConfigCubit),
          ],
          child: const DashboardScreen(),
        ),
      ),
    ),

    // ── Search ────────────────────────────────────────────────────────────
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => _page(
        state,
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => SearchCubit()),
            BlocProvider.value(value: _tripConfigCubit),
          ],
          child: const SearchScreen(),
        ),
      ),
    ),

    // ── Trip Config ───────────────────────────────────────────────────────
    GoRoute(
      path: '/trip-config',
      pageBuilder: (context, state) => _page(
        state,
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: _tripConfigCubit),
            BlocProvider.value(value: _dashboardCubit),
          ],
          child: const TripConfigScreen(),
        ),
      ),
    ),

    // ── Active Alarm ──────────────────────────────────────────────────────
    GoRoute(
      path: '/alarm',
      pageBuilder: (context, state) {
        final extra    = state.extra as Map<String, dynamic>?;
        final stop     = extra?['stop']     as StopPoint? ?? _fallbackStop();
        final distance = (extra?['distance'] as num?)?.toDouble() ?? 400.0;
        return _page(
          state,
          BlocProvider(
            create: (_) => AlarmCubit(stop: stop, distanceMetres: distance),
            child: const AlarmScreen(),
          ),
        );
      },
    ),

    // ── System Health ─────────────────────────────────────────────────────
    GoRoute(
      path: '/system-health',
      pageBuilder: (context, state) => _page(
        state,
        BlocProvider(
          create: (_) => SystemHealthCubit(),
          child: const SystemHealthScreen(),
        ),
      ),
    ),
  ],
);

// ── Helpers ───────────────────────────────────────────────────────────────

CustomTransitionPage<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurveTween(curve: Curves.easeIn).animate(animation),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 200),
    );

StopPoint _fallbackStop() => const StopPoint(
      id: 'DEEP_LINK',
      name: 'Your Stop',
      latitude: 51.5,
      longitude: -0.1,
      mode: TransitMode.tube,
    );
