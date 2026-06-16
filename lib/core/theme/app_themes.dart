import 'package:flutter/material.dart';

@immutable
class AppColorTheme {
  const AppColorTheme({
    required this.name,
    required this.surfaceBase,
    required this.surfaceSecondary,
    required this.surfaceElevated,
    required this.surfaceModal,
    required this.primary,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  final String name;
  final Color surfaceBase;
  final Color surfaceSecondary;
  final Color surfaceElevated;
  final Color surfaceModal;
  final Color primary;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  Color get primarySubtle => primary.withValues(alpha: 0.08);
  Color get primaryGlow   => primary.withValues(alpha: 0.30);

  static const List<AppColorTheme> all = [
    _solarEclipse,
    _deepNavy,
    _forestNight,
    _volcanic,
    _galactic,
  ];

  // Neutral near-black + amber — the original iconic look
  static const AppColorTheme _solarEclipse = AppColorTheme(
    name: 'Solar Eclipse',
    surfaceBase:      Color(0xFF0F1115),
    surfaceSecondary: Color(0xFF171B22),
    surfaceElevated:  Color(0xFF1F2430),
    surfaceModal:     Color(0xFF171B22),
    primary:          Color(0xFFFFB000),
    divider:          Color(0xFF2A3040),
    textPrimary:      Color(0xFFEEF0F5),
    textSecondary:    Color(0xFF8A93A6),
    textDisabled:     Color(0xFF4A5568),
  );

  // Deep navy blue background + electric sky blue
  static const AppColorTheme _deepNavy = AppColorTheme(
    name: 'Deep Navy',
    surfaceBase:      Color(0xFF070E1C),
    surfaceSecondary: Color(0xFF0C1628),
    surfaceElevated:  Color(0xFF121F38),
    surfaceModal:     Color(0xFF0C1628),
    primary:          Color(0xFF38BDF8),
    divider:          Color(0xFF1A2E4A),
    textPrimary:      Color(0xFFE2F4FF),
    textSecondary:    Color(0xFF5A8FAA),
    textDisabled:     Color(0xFF2A4A68),
  );

  // Dark forest green background + vivid emerald
  static const AppColorTheme _forestNight = AppColorTheme(
    name: 'Forest Night',
    surfaceBase:      Color(0xFF071A0A),
    surfaceSecondary: Color(0xFF0D2812),
    surfaceElevated:  Color(0xFF13361A),
    surfaceModal:     Color(0xFF0D2812),
    primary:          Color(0xFF4ADE80),
    divider:          Color(0xFF1C4228),
    textPrimary:      Color(0xFFE8FFE8),
    textSecondary:    Color(0xFF52A070),
    textDisabled:     Color(0xFF2A5038),
  );

  // Dark crimson-red background + coral rose
  static const AppColorTheme _volcanic = AppColorTheme(
    name: 'Volcanic',
    surfaceBase:      Color(0xFF1C0A08),
    surfaceSecondary: Color(0xFF2A1210),
    surfaceElevated:  Color(0xFF3A1A18),
    surfaceModal:     Color(0xFF2A1210),
    primary:          Color(0xFFFB7185),
    divider:          Color(0xFF3E1C1A),
    textPrimary:      Color(0xFFFFE8E8),
    textSecondary:    Color(0xFFA06070),
    textDisabled:     Color(0xFF5A3038),
  );

  // Deep indigo-violet background + bright amethyst
  static const AppColorTheme _galactic = AppColorTheme(
    name: 'Galactic',
    surfaceBase:      Color(0xFF0D0B1F),
    surfaceSecondary: Color(0xFF15122E),
    surfaceElevated:  Color(0xFF1D1A40),
    surfaceModal:     Color(0xFF15122E),
    primary:          Color(0xFFC084FC),
    divider:          Color(0xFF2C244A),
    textPrimary:      Color(0xFFEDE8FF),
    textSecondary:    Color(0xFF7868AA),
    textDisabled:     Color(0xFF3C3268),
  );
}
