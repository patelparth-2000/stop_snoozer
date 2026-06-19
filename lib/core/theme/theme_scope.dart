import 'package:flutter/material.dart';
import 'theme_service.dart';

/// InheritedNotifier that propagates ThemeService notifications down the tree.
/// Any widget that calls [watch] in its build() method will rebuild automatically
/// when the theme changes — without kill/restart.
class ThemeScope extends InheritedNotifier<ThemeService> {
  ThemeScope({super.key, required super.child})
      : super(notifier: ThemeService.instance);

  /// Call once at the top of a build() method to subscribe this widget
  /// to theme changes. Works for both StatelessWidget and StatefulWidget.
  static void watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>();
}
