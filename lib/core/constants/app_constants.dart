abstract final class AppConstants {
  // Spacing – 8px baseline grid
  static const double spaceXs  = 4.0;
  static const double spaceSm  = 8.0;
  static const double spaceMd  = 16.0;
  static const double spaceLg  = 24.0;
  static const double spaceXl  = 32.0;
  static const double spaceXxl = 48.0;

  static const double containerMargin = 24.0;

  // Border radii
  static const double radiusSm   = 8.0;
  static const double radiusMd   = 12.0;
  static const double radiusLg   = 16.0;
  static const double radiusXl   = 24.0;
  static const double radiusFull = 999.0;

  // Animation durations (ms)
  static const int durationFast   = 150;
  static const int durationNormal = 300;
  static const int durationSlow   = 600;
  static const int durationPulse  = 1500;

  // Location / alarm
  static const double defaultWakeRadiusMetres = 500.0;
  static const double minWakeRadiusMetres     = 100.0;
  static const double maxWakeRadiusMetres     = 1000.0;
  static const int    locationIntervalMs      = 5000;
  static const int    wifiScanIntervalMs      = 8000;

  // Slide-to-dismiss threshold (0.0–1.0)
  static const double dismissThreshold = 0.9;

  // Search
  static const int    searchMaxResults  = 50;
  static const double searchRadiusKm   = 2.0;
  static const int    searchDebounceMs = 300;
}
