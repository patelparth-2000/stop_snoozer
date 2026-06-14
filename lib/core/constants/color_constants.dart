import 'package:flutter/material.dart';

abstract final class ColorConstants {
  // Primary – mutable so ThemeService can hot-swap the colour palette
  static Color primary          = const Color(0xFFFFB000);
  static Color primaryLight     = const Color(0xFFFFD597);
  static Color primaryGlow      = const Color(0x4DFFB000);
  static Color primarySubtle    = const Color(0x1AFFB000);

  // Surfaces – deep indigo family (default: Solar Eclipse)
  static Color surfaceBase      = const Color(0xFF0F1115);
  static Color surfaceTertiary  = const Color(0xFF171B22);
  static Color surfaceSecondary = const Color(0xFF171B22);
  static Color surfaceElevated  = const Color(0xFF1F2430);
  static Color surfaceModal     = const Color(0xFF171B22);

  // Text
  static Color textPrimary      = const Color(0xFFEEF0F5);
  static Color textSecondary    = const Color(0xFF8A93A6);
  static Color textAccent       = const Color(0xFFD1DCF4);
  static Color textDisabled     = const Color(0xFF4A5568);

  // Semantic – intentionally const (never theme-changed)
  static const Color success    = Color(0xFF4CAF50);
  static const Color successGlow = Color(0x334CAF50);
  static const Color error      = Color(0xFFFFB4AB);
  static const Color errorGlow  = Color(0x33FFB4AB);

  // Scrim / Divider
  static Color scrim            = const Color(0xCC0F1115);
  static Color divider          = const Color(0xFF2A3040);

  // Transport mode icon tints — spec-mandated, never theme-changed
  static const Color transportTube       = Color(0xFF10B981);
  static const Color transportBus        = Color(0xFFFF6B6B);
  static const Color transportRail       = Color(0xFF38BDF8);
  static const Color transportDlr        = Color(0xFF10B981);
  static const Color transportOverground = Color(0xFF38BDF8);
  static const Color transportTram       = Color(0xFF10B981);
}
