import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/color_constants.dart';
import '../constants/app_constants.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ColorConstants.surfaceBase,
      colorScheme: ColorScheme.dark(
        primary:    ColorConstants.primary,
        onPrimary:  ColorConstants.surfaceBase,
        surface:    ColorConstants.surfaceSecondary,
        onSurface:  ColorConstants.textPrimary,
        secondary:  ColorConstants.textAccent,
        onSecondary: ColorConstants.surfaceBase,
        error:      ColorConstants.error,
        onError:    ColorConstants.surfaceBase,
        outline:    ColorConstants.surfaceElevated,
      ),
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: ColorConstants.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.sora(
          color: ColorConstants.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
        iconTheme: IconThemeData(color: ColorConstants.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: ColorConstants.surfaceSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: ColorConstants.divider,
        thickness: 1,
        space: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ColorConstants.primary,
        inactiveTrackColor: ColorConstants.surfaceElevated,
        thumbColor: ColorConstants.primary,
        overlayColor: ColorConstants.primarySubtle,
        valueIndicatorColor: ColorConstants.primary,
        showValueIndicator: ShowValueIndicator.onDrag,
        valueIndicatorTextStyle: GoogleFonts.sora(
          color: ColorConstants.surfaceBase,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? ColorConstants.surfaceBase
                : ColorConstants.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? ColorConstants.primary
                : ColorConstants.surfaceElevated),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ColorConstants.surfaceModal,
        modalBackgroundColor: ColorConstants.surfaceModal,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ColorConstants.surfaceSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.inter(
          color: ColorConstants.textSecondary,
          fontSize: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ColorConstants.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(color: ColorConstants.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
        displayLarge: GoogleFonts.sora(
          fontSize: 48, fontWeight: FontWeight.w700, color: ColorConstants.textPrimary,
        ),
        headlineLarge: GoogleFonts.sora(
          fontSize: 32, fontWeight: FontWeight.w700, color: ColorConstants.textPrimary,
        ),
        headlineMedium: GoogleFonts.sora(
          fontSize: 28, fontWeight: FontWeight.w600, color: ColorConstants.textPrimary,
        ),
        headlineSmall: GoogleFonts.sora(
          fontSize: 20, fontWeight: FontWeight.w600, color: ColorConstants.textPrimary,
          letterSpacing: 0.15,
        ),
        titleLarge: GoogleFonts.sora(
          fontSize: 16, fontWeight: FontWeight.w600, color: ColorConstants.textPrimary,
          letterSpacing: 0.15,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w500, color: ColorConstants.textPrimary,
        ),
        titleSmall: GoogleFonts.sora(
          fontSize: 12, fontWeight: FontWeight.w700, color: ColorConstants.textPrimary,
          letterSpacing: 0.15,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: ColorConstants.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: ColorConstants.textPrimary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w400, color: ColorConstants.textSecondary,
        ),
        labelLarge: GoogleFonts.sora(
          fontSize: 14, fontWeight: FontWeight.w600, color: ColorConstants.textPrimary,
          letterSpacing: 0.05,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500, color: ColorConstants.textSecondary,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w500, color: ColorConstants.textSecondary,
          letterSpacing: 0.05,
        ),
      );
}
