import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app/app.dart';
import 'core/theme/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // StopSnoozer is offline-first and is used UNDERGROUND, where there is no
  // network by definition. google_fonts defaults to fetching font files from
  // fonts.gstatic.com on first launch and caching them to device storage.
  //
  // With 41 files calling GoogleFonts.inter/.sora and nothing bundled, a first
  // run with no connectivity meant falling back to the platform font — and it
  // put an undeclared network call in an app whose Play Data Safety answers list
  // only api.postcodes.io.
  //
  // Inter and Sora are now bundled under assets/google_fonts/, so this switch
  // makes the package use them instead of the network. Both halves are required:
  // without the assets this would silently fall back to the system font, and
  // without this flag the package would still reach for the network first.
  GoogleFonts.config.allowRuntimeFetching = false;

  await ThemeService.instance.load();
  runApp(const StopSnoozerApp());
}
