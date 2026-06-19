import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/color_constants.dart';
import '../../core/theme/theme_scope.dart';
import '../../presentation/search/search_viewmodel.dart';

/// Persistent shell that wraps the four main tabs.
/// Splash (/splash) and Alarm (/alarm) live outside this shell
/// and never show the bottom navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_rounded,          label: 'Home'),
    (icon: Icons.search_rounded,        label: 'Search'),
    (icon: Icons.playlist_play_rounded, label: 'Queue'),
    (icon: Icons.alarm_rounded,         label: 'Alarms'),
    (icon: Icons.settings_rounded,      label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: navigationShell,
      bottomNavigationBar: _SnoozerNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (i) {
          // Clear search state whenever the user leaves the Search tab
          if (navigationShell.currentIndex == 1 && i != 1) {
            context.read<SearchCubit>().clear();
          }
          navigationShell.goBranch(
            i,
            // Re-tap active tab → jump back to initial route in that branch
            initialLocation: i == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

// ── Custom bottom navigation bar ──────────────────────────────────────────

class _SnoozerNavBar extends StatelessWidget {
  const _SnoozerNavBar({
    required this.currentIndex,
    required this.onTap,
  });
  final int currentIndex;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: ColorConstants.surfaceSecondary,
        border: Border(
          top: BorderSide(color: ColorConstants.divider, width: 1),
        ),
      ),
      child: SizedBox(
        height: 60 + bottomPad,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPad),
          child: Row(
            children: List.generate(
              AppShell._tabs.length,
              (i) => Expanded(
                child: _NavItem(
                  icon: AppShell._tabs[i].icon,
                  label: AppShell._tabs[i].label,
                  isActive: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? ColorConstants.primary : ColorConstants.textDisabled;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Spec: "under-slung 2dp neon horizontal indicator bar pill"
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 2,
            width: isActive ? 28 : 0,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: ColorConstants.primary,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
