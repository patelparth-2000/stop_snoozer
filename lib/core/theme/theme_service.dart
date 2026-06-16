import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/color_constants.dart';
import '../../data/services/platform_channel_service.dart';
import 'app_themes.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const String _themeKey     = 'theme_index';
  static const String _logoColorKey = 'logo_color_index';

  int _themeIndex     = 0;
  int _logoColorIndex = 0;

  int get themeIndex     => _themeIndex;
  int get logoColorIndex => _logoColorIndex;

  Color get logoColor => AppColorTheme.all[_logoColorIndex].primary;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeIndex     = prefs.getInt(_themeKey)     ?? 0;
    _logoColorIndex = prefs.getInt(_logoColorKey) ?? 0;
    _apply();
  }

  Future<void> setTheme(int index) async {
    if (index < 0 || index >= AppColorTheme.all.length) return;
    _themeIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, index);
    _apply();
    notifyListeners();
    PlatformChannelService.instance.switchLauncherIcon(index);
  }

  Future<void> setLogoColor(int index) async {
    if (index < 0 || index >= AppColorTheme.all.length) return;
    _logoColorIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_logoColorKey, index);
    notifyListeners();
  }

  void _apply() {
    final t = AppColorTheme.all[_themeIndex];
    ColorConstants.surfaceBase      = t.surfaceBase;
    ColorConstants.surfaceSecondary = t.surfaceSecondary;
    ColorConstants.surfaceElevated  = t.surfaceElevated;
    ColorConstants.surfaceModal     = t.surfaceModal;
    ColorConstants.primary          = t.primary;
    ColorConstants.primarySubtle    = t.primarySubtle;
    ColorConstants.primaryGlow      = t.primaryGlow;
    ColorConstants.divider          = t.divider;
    ColorConstants.textPrimary      = t.textPrimary;
    ColorConstants.textSecondary    = t.textSecondary;
    ColorConstants.textDisabled     = t.textDisabled;
  }
}
