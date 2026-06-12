import '../models/stop_point.dart';
import '../services/stop_points_db.dart';
import '../services/postcode_geocoder.dart';

class StopPointsRepository {
  StopPointsRepository({StopPointsDb? db})
      : _db = db ?? StopPointsDb.instance;

  final StopPointsDb _db;

  Future<List<StopPoint>> search(
    String query, {
    List<String>? transitTypes,
  }) =>
      _db.searchStops(query, transitTypes: transitTypes);

  Future<List<StopPoint>> nearby({
    required double lat,
    required double lon,
    double radiusKm = 2.0,
    int limit = 10,
    List<String>? transitTypes,
  }) =>
      _db.getClosestStops(lat, lon,
          radiusKm: radiusKm, limit: limit, transitTypes: transitTypes);

  Future<StopPoint?> findByWifi(String ssid) => _db.findByWifiSsid(ssid);

  /// Geocodes [postcode] then returns nearby stops, filtered by [transitTypes].
  /// Returns null when the postcode cannot be geocoded.
  Future<List<StopPoint>?> postcodeSearch(
    String postcode, {
    List<String>? transitTypes,
    double radiusKm = 1.5,
    int limit = 50,
  }) async {
    final coords = await PostcodeGeocoder.geocode(postcode);
    if (coords == null) return null;
    return _db.getClosestStops(
      coords.lat,
      coords.lon,
      radiusKm: radiusKm,
      limit: limit,
      transitTypes: transitTypes,
    );
  }
}
