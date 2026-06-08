import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';
import '../../data/models/trip_leg.dart';
import '../../data/repositories/stop_points_repository.dart';
import '../../data/services/location_service.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

enum TrackingMode { idle, aboveGround, subterranean }

class DashboardState extends Equatable {
  const DashboardState({
    this.legs = const [],
    this.nearbyStops = const [],
    this.detectedStopName,
    this.trackingMode = TrackingMode.idle,
    this.activeIndex = 0,
    this.isLocating = true,
    this.currentLat,
    this.currentLon,
  });

  final List<TripLeg> legs;
  final List<StopPoint> nearbyStops;
  final String? detectedStopName;
  final TrackingMode trackingMode;
  final int activeIndex;
  final bool isLocating;
  final double? currentLat;
  final double? currentLon;

  bool get hasActiveTrip => legs.isNotEmpty;
  TripLeg? get activeLeg =>
      legs.isNotEmpty && activeIndex < legs.length ? legs[activeIndex] : null;

  DashboardState copyWith({
    List<TripLeg>? legs,
    List<StopPoint>? nearbyStops,
    String? detectedStopName,
    TrackingMode? trackingMode,
    int? activeIndex,
    bool? isLocating,
    double? currentLat,
    double? currentLon,
  }) =>
      DashboardState(
        legs: legs ?? this.legs,
        nearbyStops: nearbyStops ?? this.nearbyStops,
        detectedStopName: detectedStopName ?? this.detectedStopName,
        trackingMode: trackingMode ?? this.trackingMode,
        activeIndex: activeIndex ?? this.activeIndex,
        isLocating: isLocating ?? this.isLocating,
        currentLat: currentLat ?? this.currentLat,
        currentLon: currentLon ?? this.currentLon,
      );

  @override
  List<Object?> get props => [
        legs, nearbyStops, detectedStopName, trackingMode,
        activeIndex, isLocating, currentLat, currentLon,
      ];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    StopPointsRepository? repo,
    LocationService? location,
    PlatformChannelService? platform,
  })  : _repo     = repo     ?? StopPointsRepository(),
        _location = location ?? LocationService.instance,
        _platform = platform ?? PlatformChannelService.instance,
        super(const DashboardState());

  final StopPointsRepository _repo;
  final LocationService _location;
  final PlatformChannelService _platform;

  Future<void> load() async {
    final loc = await _location.getCurrentLocation();
    if (loc == null) {
      emit(state.copyWith(isLocating: false));
      return;
    }
    final nearby = await _repo.nearby(
      lat: loc.latitude,
      lon: loc.longitude,
      limit: 8,
    );
    emit(state.copyWith(
      isLocating: false,
      currentLat: loc.latitude,
      currentLon: loc.longitude,
      nearbyStops: nearby,
      detectedStopName: nearby.isNotEmpty ? nearby.first.name : null,
    ));
  }

  void loadTrip(List<TripLeg> legs) {
    final armed = [
      if (legs.isNotEmpty) legs.first.copyWith(status: LegStatus.active),
      ...legs.skip(1).map((l) => l.copyWith(status: LegStatus.queued)),
    ];
    emit(state.copyWith(legs: armed, activeIndex: 0));
    _startTrackingActive(armed);
  }

  void _startTrackingActive(List<TripLeg> legs) {
    if (legs.isEmpty) return;
    final leg  = legs.first;
    final stop = leg.stop;
    final mode = stop.wifiSsid != null
        ? TrackingMode.subterranean
        : TrackingMode.aboveGround;
    emit(state.copyWith(trackingMode: mode));
    if (stop.wifiSsid != null) {
      _platform.startWifiSensing(
        targetSsid: stop.wifiSsid!,
        stopId: stop.id,
        stopName: stop.name,
      );
    } else {
      _platform.startGeofence(
        stopId: stop.id,
        stopName: stop.name,
        lat: stop.latitude,
        lon: stop.longitude,
        radiusMetres: leg.wakeRadiusMetres,
      );
    }
  }

  void clearTrip() {
    _platform.stopTracking();
    _location.stopTracking();
    emit(state.copyWith(
      legs: [],
      activeIndex: 0,
      trackingMode: TrackingMode.idle,
    ));
  }

  String get greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning, Commuter';
    if (h < 17) return 'Good afternoon, Commuter';
    return 'Good evening, Commuter';
  }
}
