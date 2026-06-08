import 'dart:math' as math;

abstract final class DistanceUtils {
  static const double _earthKm = 6371.0;

  static double haversineKm(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return _earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double haversineMetres(
    double lat1, double lon1,
    double lat2, double lon2,
  ) =>
      haversineKm(lat1, lon1, lat2, lon2) * 1000;

  static double toMiles(double km) => km * 0.621371;

  static ({double minLat, double maxLat, double minLon, double maxLon}) boundingBox({
    required double lat,
    required double lon,
    required double radiusKm,
  }) {
    final dLat = radiusKm / _earthKm * (180 / math.pi);
    final dLon = radiusKm /
        (_earthKm * math.cos(lat * math.pi / 180)) *
        (180 / math.pi);
    return (
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLon: lon - dLon,
      maxLon: lon + dLon,
    );
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
