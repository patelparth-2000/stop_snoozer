import 'package:flutter/material.dart';

abstract final class ColorConstants {
  // Primary – Amber (Luminous Noir signature)
  static const Color primary          = Color(0xFFFFB000);
  static const Color primaryLight     = Color(0xFFFFD597);
  static const Color primaryGlow      = Color(0x4DFFB000);
  static const Color primarySubtle    = Color(0x1AFFB000);

  // Surfaces – deep indigo family
  static const Color surfaceBase      = Color(0xFF0F131D);
  static const Color surfaceTertiary  = Color(0xFF171B26);
  static const Color surfaceSecondary = Color(0xFF1C1F2A);
  static const Color surfaceElevated  = Color(0xFF262A35);
  static const Color surfaceModal     = Color(0xFF1C1F2A);

  // Text
  static const Color textPrimary      = Color(0xFFDFE2F1);
  static const Color textSecondary    = Color(0xFFC1C7CF);
  static const Color textAccent       = Color(0xFFD1DCF4);
  static const Color textDisabled     = Color(0xFF5A5F6E);

  // Semantic
  static const Color success          = Color(0xFF4CAF50);
  static const Color successGlow      = Color(0x334CAF50);
  static const Color error            = Color(0xFFFFB4AB);
  static const Color errorGlow        = Color(0x33FFB4AB);

  // Scrim / Divider
  static const Color scrim            = Color(0xCC0F131D);
  static const Color divider          = Color(0xFF262A35);

  // Transport mode icon tints
  static const Color transportTube       = Color(0xFF4DD0E1);
  static const Color transportBus        = Color(0xFFEF9A9A);
  static const Color transportRail       = Color(0xFF90CAF9);
  static const Color transportDlr        = Color(0xFFA5D6A7);
  static const Color transportOverground = Color(0xFFFFCC80);
}
