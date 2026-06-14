import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/theme/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService.instance.load();
  runApp(const StopSnoozerApp());
}
