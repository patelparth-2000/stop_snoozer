import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../core/utils/distance_utils.dart';

class LocationUpdate {
  const LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
}

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _sub;
  final _controller = StreamController<LocationUpdate>.broadcast();

  Stream<LocationUpdate> get stream => _controller.stream;

  Future<bool> requestPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<LocationUpdate?> getCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return LocationUpdate(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  void startTracking({
    required double targetLat,
    required double targetLon,
    required double radiusMetres,
    required void Function() onTrigger,
  }) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final update = LocationUpdate(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      );
      _controller.add(update);
      final distM = DistanceUtils.haversineMetres(
        pos.latitude, pos.longitude, targetLat, targetLon,
      );
      if (distM <= radiusMetres) onTrigger();
    });
  }

  void stopTracking() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stopTracking();
    _controller.close();
  }
}
