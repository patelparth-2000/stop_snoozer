import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_themes.dart';
import '../../../core/theme/theme_service.dart';

class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        20,
        AppConstants.containerMargin,
        20 + bottomPad,
      ),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceModal,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: ColorConstants.surfaceElevated, width: 1),
        ),
      ),
      child: ListenableBuilder(
        listenable: ThemeService.instance,
        builder: (_, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ColorConstants.surfaceElevated,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('APP THEME'),
            const SizedBox(height: AppConstants.spaceMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(AppColorTheme.all.length, (i) {
                return _ThemeSwatch(
                  theme: AppColorTheme.all[i],
                  selected: ThemeService.instance.themeIndex == i,
                  onTap: () => ThemeService.instance.setTheme(i),
                );
              }),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            _sectionLabel('LOGO COLOUR'),
            const SizedBox(height: AppConstants.spaceMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(AppColorTheme.all.length, (i) {
                return _LogoColorDot(
                  color: AppColorTheme.all[i].primary,
                  selected: ThemeService.instance.logoColorIndex == i,
                  onTap: () => ThemeService.instance.setLogoColor(i),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.sora(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: ColorConstants.textDisabled,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  final AppColorTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.surfaceBase,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: selected
                    ? theme.primary
                    : theme.surfaceElevated,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: theme.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: theme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 56,
            child: Text(
              theme.name.split(' ').first,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: selected
                    ? ColorConstants.textPrimary
                    : ColorConstants.textDisabled,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoColorDot extends StatelessWidget {
  const _LogoColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: selected ? 0.2 : 0.08),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10)]
              : null,
        ),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
