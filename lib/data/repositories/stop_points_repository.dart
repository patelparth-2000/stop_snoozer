import '../models/stop_point.dart';
import '../services/database_service.dart';

class StopPointsRepository {
  StopPointsRepository({DatabaseService? db})
      : _db = db ?? DatabaseService.instance;

  final DatabaseService _db;

  Future<List<StopPoint>> search(String query) => _db.searchStops(query);

  Future<List<StopPoint>> nearby({
    required double lat,
    required double lon,
    double radiusKm = 2.0,
    int limit = 10,
  }) =>
      _db.getClosestStops(lat, lon, radiusKm: radiusKm, limit: limit);

  Future<StopPoint?> findByWifi(String ssid) => _db.findByWifiSsid(ssid);
}
