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
import '../../presentation/calendar/calendar_screen.dart';
import '../../presentation/calendar/calendar_viewmodel.dart';
import '../../presentation/route_select/route_select_screen.dart';
import '../shell/app_shell.dart';

// Long-lived Cubits shared across the entire shell
final _dashboardCubit  = DashboardCubit();
final _tripConfigCubit = TripConfigCubit();
final _calendarCubit   = CommuteAlarmsCubit();
final _searchCubit     = SearchCubit();

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    // ── Full-screen takeovers (no bottom nav) ─────────────────────────────
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => _fade(
        state,
        MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) =>
                  DatabaseInitHandler()..add(const CheckDatabaseOnBootEvent()),
            ),
            BlocProvider(create: (_) => SplashCubit()),
          ],
          child: const SplashScreen(),
        ),
      ),
    ),

    GoRoute(
      path: '/alarm',
      pageBuilder: (context, state) {
        final extra         = state.extra as Map<String, dynamic>?;
        final stop          = extra?['stop']          as StopPoint? ?? _fallbackStop();
        final distance      = (extra?['distance']     as num?)?.toDouble() ?? 400.0;
        final firedAt       = (extra?['firedAt']      as num?)?.toInt() ?? 0;
        final countdownSecs = (extra?['countdownSecs'] as num?)?.toInt() ?? 5;

        int initialCountdown = 0;
        if (firedAt > 0) {
          final elapsed = (DateTime.now().millisecondsSinceEpoch - firedAt) ~/ 1000;
          initialCountdown = (countdownSecs - elapsed).clamp(0, countdownSecs);
        }

        return _fade(
          state,
          BlocProvider(
            create: (_) => AlarmCubit(
              stop: stop,
              distanceMetres: distance,
              initialCountdown: initialCountdown,
              onDismissed: _dashboardCubit.advanceLeg,
            ),
            child: const AlarmScreen(),
          ),
        );
      },
    ),

    // ── Underground route pre-selection (U4) ──────────────────────────────
    // Full-screen rather than a shell tab: it is a modal decision the user must
    // finish before an underground journey can be tracked at all.
    GoRoute(
      path: '/route-select',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final origin = extra?['origin'] as StopPoint?;
        final destination = extra?['destination'] as StopPoint?;
        if (origin == null || destination == null) {
          return _fade(state, const _RouteSelectMisuse());
        }
        return _fade(
          state,
          RouteSelectScreen(origin: origin, destination: destination),
        );
      },
    ),

    // ── Shell with persistent BottomNavigationBar ─────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _dashboardCubit),
          BlocProvider.value(value: _tripConfigCubit),
          BlocProvider.value(value: _calendarCubit),
          BlocProvider.value(value: _searchCubit),
        ],
        child: AppShell(navigationShell: navigationShell),
      ),
      branches: [
        // Tab 1 – Dashboard
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (context, state) =>
                  _fade(state, const DashboardScreen()),
            ),
          ],
        ),

        // Tab 2 – Search
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => _fade(state, const SearchScreen()),
            ),
          ],
        ),

        // Tab 3 – Trip Queue (formerly /trip-config)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/queue',
              pageBuilder: (context, state) =>
                  _fade(state, const TripConfigScreen()),
            ),
          ],
        ),

        // Tab 4 – Alarms / Commute Schedule
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calendar',
              pageBuilder: (context, state) =>
                  _fade(state, const CalendarScreen()),
            ),
          ],
        ),

        // Tab 5 – Settings (formerly /system-health)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => _fade(
                state,
                BlocProvider(
                  create: (_) => SystemHealthCubit(),
                  child: const SystemHealthScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

// ── Helpers ───────────────────────────────────────────────────────────────

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurveTween(curve: Curves.easeIn).animate(animation),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 200),
    );

/// Shown when /route-select is reached without both endpoints.
///
/// There is no sensible fallback stop here: guessing a route would be worse
/// than saying nothing, because the whole point of pre-selection is that the
/// sequence is known exactly.
class _RouteSelectMisuse extends StatelessWidget {
  const _RouteSelectMisuse();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Pick a start and destination first.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

StopPoint _fallbackStop() => const StopPoint(
      id: 'DEEP_LINK',
      name: 'Your Stop',
      latitude: 51.5,
      longitude: -0.1,
      mode: TransitMode.tube,
    );
