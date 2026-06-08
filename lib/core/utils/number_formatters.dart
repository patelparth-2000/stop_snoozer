abstract final class NumberFormatters {
  static String metres(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  static String miles(double km) {
    final mi = km * 0.621371;
    if (mi < 0.1) return '< 0.1 mi';
    return '${mi.toStringAsFixed(1)} mi';
  }

  static String percentage(double value) => '${(value * 100).round()}%';
}
