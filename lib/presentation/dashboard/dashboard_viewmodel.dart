import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/alarm_event.dart';
import '../../data/models/saved_location.dart';
import '../../data/models/stop_point.dart';
import '../../data/models/trip_leg.dart';
import '../../data/repositories/alarm_history_repository.dart';
import '../../data/repositories/saved_locations_repository.dart';
import '../../data/repositories/stop_points_repository.dart';
import '../../data/repositories/trip_groups_repository.dart';
import '../../data/services/location_service.dart';
import '../../data/services/platform_channel_service.dart';

// ── State ──────────────────────────────────────────────────────────────────

enum TrackingMode { idle, aboveGround, subterranean }

class DashboardState extends Equatable {
  const DashboardState({
    this.legs = const [],
    this.nearbyStops = const [],
    this.savedLocations = const [],
    this.detectedStopName,
    this.trackingMode = TrackingMode.idle,
    this.activeIndex = 0,
    this.isLocating = true,
    this.currentLat,
    this.currentLon,
    this.alarmStop,
    this.alarmDistanceMetres,
    this.alarmFiredAt,
    this.alarmCountdownSecs = 5,
    this.warningMessage,
  });

  final List<TripLeg> legs;
  final List<StopPoint> nearbyStops;
  final List<SavedLocation> savedLocations;
  final String? detectedStopName;
  final TrackingMode trackingMode;
  final int activeIndex;
  final bool isLocating;
  final double? currentLat;
  final double? currentLon;
  final StopPoint? alarmStop;
  final double? alarmDistanceMetres;
  /// Epoch-ms when the service first fired the alarm (for countdown sync).
  final int? alarmFiredAt;
  final int alarmCountdownSecs;
  final String? warningMessage;

  bool get hasActiveTrip => legs.isNotEmpty;
  TripLeg? get activeLeg =>
      legs.isNotEmpty && activeIndex < legs.length ? legs[activeIndex] : null;

  DashboardState copyWith({
    List<TripLeg>? legs,
    List<StopPoint>? nearbyStops,
    List<SavedLocation>? savedLocations,
    String? detectedStopName,
    TrackingMode? trackingMode,
    int? activeIndex,
    bool? isLocating,
    double? currentLat,
    double? currentLon,
    StopPoint? alarmStop,
    double? alarmDistanceMetres,
    int? alarmFiredAt,
    int? alarmCountdownSecs,
    bool clearAlarm = false,
    String? warningMessage,
    bool clearWarning = false,
  }) =>
      DashboardState(
        legs:               legs               ?? this.legs,
        nearbyStops:        nearbyStops        ?? this.nearbyStops,
        savedLocations:     savedLocations     ?? this.savedLocations,
        detectedStopName:   detectedStopName   ?? this.detectedStopName,
        trackingMode:       trackingMode       ?? this.trackingMode,
        activeIndex:        activeIndex        ?? this.activeIndex,
        isLocating:         isLocating         ?? this.isLocating,
        currentLat:         currentLat         ?? this.currentLat,
        currentLon:         currentLon         ?? this.currentLon,
        alarmStop:          clearAlarm ? null  : (alarmStop ?? this.alarmStop),
        alarmDistanceMetres: clearAlarm ? null
            : (alarmDistanceMetres ?? this.alarmDistanceMetres),
        alarmFiredAt:       clearAlarm ? null  : (alarmFiredAt ?? this.alarmFiredAt),
        alarmCountdownSecs: alarmCountdownSecs ?? this.alarmCountdownSecs,
        warningMessage: clearWarning ? null : (warningMessage ?? this.warningMessage),
      );

  @override
  List<Object?> get props => [
        legs, nearbyStops, savedLocations, detectedStopName, trackingMode,
        activeIndex, isLocating, currentLat, currentLon,
        alarmStop, alarmDistanceMetres, alarmFiredAt, alarmCountdownSecs,
        warningMessage,
      ];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    StopPointsRepository? repo,
    LocationService? location,
    PlatformChannelService? platform,
    SavedLocationsRepository? savedRepo,
  })  : _repo      = repo      ?? StopPointsRepository(),
        _location  = location  ?? LocationService.instance,
        _platform  = platform  ?? PlatformChannelService.instance,
        _savedRepo = savedRepo ?? SavedLocationsRepository.instance,
        super(const DashboardState()) {
    _alarmSub = _platform.alarmStream.listen(_onNativeAlarm);
  }

  final StopPointsRepository _repo;
  final LocationService _location;
  final PlatformChannelService _platform;
  final SavedLocationsRepository _savedRepo;
  final _groupsRepo = TripGroupsRepository.instance;
  StreamSubscription<Map<String, dynamic>>? _alarmSub;

  void _onNativeAlarm(Map<String, dynamic> event) {
    final distance      = (event['distanceMetres'] as num?)?.toDouble() ?? 0.0;
    final firedAt       = (event['firedAt']        as num?)?.toInt();
    final countdownSecs = (event['countdownSecs']  as num?)?.toInt() ?? 5;
    final stopId        = event['stopId'] as String? ?? '';
    // The alarm is for whichever stop the service says fired — a saved stop
    // can ring mid-trip, so this must not assume it is the trip's active leg.
    final legIndex = state.legs.indexWhere((l) => l.stop.id == stopId);
    final stop = legIndex >= 0
        ? state.legs[legIndex].stop
        : StopPoint(
            id: stopId,
            name: event['stopName'] as String? ?? 'Your Stop',
            latitude: 0,
            longitude: 0,
            mode: TransitMode.bus,
          );
    _recordAlarmEvent(stop.id, stop.name, distance);
    emit(state.copyWith(
      alarmStop: stop,
      alarmDistanceMetres: distance,
      alarmFiredAt: firedAt,
      alarmCountdownSecs: countdownSecs,
    ));
    if (legIndex >= 0 && legIndex == state.activeIndex) _completeActiveLeg();
  }

  void _recordAlarmEvent(String stopId, String stopName, double distanceMetres) {
    final event = AlarmEvent(
      id:             const Uuid().v4(),
      stopId:         stopId,
      stopName:       stopName,
      firedAt:        DateTime.now(),
      distanceMetres: distanceMetres,
    );
    AlarmHistoryRepository.instance.insert(event);
  }

  void clearAlarm() => emit(state.copyWith(clearAlarm: true));

  void clearWarning() => emit(state.copyWith(clearWarning: true));

  void openWifiSettings() => _platform.openWifiSettings();

  Future<void> load() async {
    // Load saved locations first so dashboard never flickers to empty
    // if location permission is denied or getCurrentLocation throws.
    final saved = await _savedRepo.loadAll();
    emit(state.copyWith(savedLocations: saved));
    _resumeActiveSavedLocations(saved);

    // Load current location and nearby stops independently so a location
    // failure never prevents saved locations from appearing.
    try {
      final loc = await _location.getCurrentLocation();
      if (loc != null) {
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
      } else {
        emit(state.copyWith(isLocating: false));
      }
    } catch (_) {
      emit(state.copyWith(isLocating: false));
    }

    // Redraw a trip the native service is still running — the app may have
    // been closed or killed since it was armed.
    await _restoreActiveRoute();

    // If a group-based commute alarm fired while app was inactive, load the
    // full trip group so all legs are tracked in sequence.
    final pendingGroupId = await _platform.checkPendingTripGroup();
    // A trip already running natively (e.g. a scheduled trip that started as
    // a route) must not be restarted from its first stop.
    if (pendingGroupId != null && !state.hasActiveTrip) {
      final group = await _groupsRepo.findById(pendingGroupId);
      if (group != null && group.legs.isNotEmpty) {
        loadTrip(group.legs);
        return;
      }
    }

    // Check if the proximity alarm fired while the app was killed.
    final pending = await _platform.checkPendingAlarm();
    if (pending != null) {
      final stopId        = pending['stopId']        as String? ?? '';
      final stopName      = pending['stopName']      as String? ?? 'Your Stop';
      final dist          = (pending['distanceMetres'] as num?)?.toDouble() ?? 0.0;
      final firedAt       = (pending['firedAt']      as num?)?.toInt();
      final countdownSecs = (pending['countdownSecs'] as num?)?.toInt() ?? 5;
      _recordAlarmEvent(stopId, stopName, dist);
      final stop = StopPoint(
        id: stopId, name: stopName,
        latitude: 0, longitude: 0, mode: TransitMode.bus,
      );
      emit(state.copyWith(
        alarmStop: stop,
        alarmDistanceMetres: dist,
        alarmFiredAt: firedAt,
        alarmCountdownSecs: countdownSecs,
      ));
    }
  }

  /// Re-arms the native service for every saved location whose toggle is on.
  /// Called on every cold start so tracking survives app kills and device reboots.
  void _resumeActiveSavedLocations(List<SavedLocation> saved) {
    final active = saved.where((l) => l.isActive).toList();
    if (active.isEmpty) return;
    final targets = active.map((l) {
      final stop = l.toStopPoint();
      return <String, dynamic>{
        'stopId':       stop.id,
        'stopName':     stop.name,
        'lat':          stop.latitude,
        'lon':          stop.longitude,
        'radiusMetres': l.radius,
        if (stop.wifiSsid != null) 'ssid': stop.wifiSsid!,
      };
    }).toList();
    _platform.updateTrackingTargets(targets);
    final hasWifi = active.any((l) => l.wifiSsid != null);
    emit(state.copyWith(
      trackingMode: hasWifi ? TrackingMode.subterranean : TrackingMode.aboveGround,
    ));
  }

  void loadTrip(List<TripLeg> legs) {
    if (legs.isEmpty) return;
    final armed = [
      legs.first.copyWith(status: LegStatus.active),
      ...legs.skip(1).map((l) => l.copyWith(status: LegStatus.queued)),
    ];
    final first = armed.first.stop;
    emit(state.copyWith(
      legs: armed,
      activeIndex: 0,
      trackingMode: first.wifiSsid != null
          ? TrackingMode.subterranean
          : TrackingMode.aboveGround,
    ));
    // The whole trip goes to the native service, which arms each stop in turn
    // as the previous alarm is dismissed — from the notification, the alarm
    // screen, or with the app closed. Arming only the first stop from here
    // used to end the trip the moment stop 1 was dismissed.
    _platform.startRoute(armed.map((l) => l.toNativeRouteLeg()).toList());
    // Auto-save destination stop so it appears in Saved Stops
    _saveStop(legs.first);
  }

  Future<void> _restoreActiveRoute() async {
    if (state.hasActiveTrip) return;
    final route = await _platform.getActiveRoute();
    final raw = route?['legs'];
    if (raw is! List || raw.isEmpty) return;
    final index = (route?['index'] as num?)?.toInt() ?? 0;
    final legs = <TripLeg>[];
    for (var i = 0; i < raw.length; i++) {
      final m = Map<String, dynamic>.from(raw[i] as Map);
      legs.add(TripLeg(
        stop: StopPoint.fromMap({
          'id':        m['stopId'] ?? '',
          'name':      m['stopName'] ?? '',
          'lat':       m['lat'] ?? 0,
          'lng':       m['lon'] ?? 0,
          'mode':      m['mode'] ?? 'bus',
          'wifi_ssid': m['ssid'],
        }),
        wakeRadiusMetres: ((m['radius'] ?? m['radiusMetres'] ?? 300) as num).toDouble(),
        alarmStyle: m['alarmStyle'] == 'subtlePulse'
            ? AlarmStyle.subtlePulse
            : AlarmStyle.defconDrill,
        status: i < index
            ? LegStatus.complete
            : (i == index ? LegStatus.active : LegStatus.queued),
      ));
    }
    emit(state.copyWith(
      legs: legs,
      activeIndex: index.clamp(0, legs.length - 1),
      trackingMode: TrackingMode.aboveGround,
    ));
  }

  Future<void> _saveStop(TripLeg leg) async {
    final loc = SavedLocation.fromStop(leg.stop, radius: leg.wakeRadiusMetres);
    await _savedRepo.upsert(loc);
    final updated = await _savedRepo.loadAll();
    emit(state.copyWith(savedLocations: updated));
  }

  /// Toggles a saved location on/off.
  /// Multiple locations can be active simultaneously — all are tracked in
  /// parallel; whichever is reached first fires the alarm.
  Future<void> toggleSavedLocation(String id) async {
    final idx = state.savedLocations.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final loc    = state.savedLocations[idx];
    final turnOn = !loc.isActive;

    // Toggle only this location — leave others as-is
    await _savedRepo.update(loc.copyWith(isActive: turnOn));
    final updated = state.savedLocations
        .map((l) => l.id == id ? l.copyWith(isActive: turnOn) : l)
        .toList();

    emit(state.copyWith(savedLocations: updated));
    _pushSavedTargets(updated);
  }

  Future<void> deleteSavedLocation(String id) async {
    final wasActive =
        state.savedLocations.any((l) => l.id == id && l.isActive);
    await _savedRepo.delete(id);
    final updated = state.savedLocations.where((l) => l.id != id).toList();
    emit(state.copyWith(savedLocations: updated));
    // Deleting a switched-on stop used to leave the service tracking it, so a
    // stop that was no longer in the list still rang.
    if (wasActive) _pushSavedTargets(updated);
  }

  /// Sends the switched-on saved stops to the service. An empty list is sent
  /// too: the service then stops tracking saved stops, but keeps any trip.
  void _pushSavedTargets(List<SavedLocation> all) {
    final active = all.where((l) => l.isActive).toList();
    final targets = active.map((l) {
      final stop = l.toStopPoint();
      return <String, dynamic>{
        'stopId':       stop.id,
        'stopName':     stop.name,
        'lat':          stop.latitude,
        'lon':          stop.longitude,
        'radiusMetres': l.radius,
        if (stop.wifiSsid != null) 'ssid': stop.wifiSsid!,
      };
    }).toList();
    _platform.updateTrackingTargets(targets);

    final hasWifi = active.any((l) => l.toStopPoint().wifiSsid != null);
    emit(state.copyWith(
      trackingMode: active.isNotEmpty
          ? (hasWifi ? TrackingMode.subterranean : TrackingMode.aboveGround)
          : (state.hasActiveTrip ? state.trackingMode : TrackingMode.idle),
    ));
  }

  /// Marks the active leg done and the next one active. Display only: the
  /// native service arms the next stop itself when this alarm is dismissed.
  void _completeActiveLeg() {
    if (state.legs.isEmpty) return;
    final legs = [...state.legs];
    legs[state.activeIndex] =
        legs[state.activeIndex].copyWith(status: LegStatus.complete);

    final nextIndex = state.activeIndex + 1;
    if (nextIndex < legs.length) {
      legs[nextIndex] = legs[nextIndex].copyWith(status: LegStatus.active);
      emit(state.copyWith(legs: legs, activeIndex: nextIndex));
    } else {
      emit(state.copyWith(legs: legs));
      _tripDoneTimer?.cancel();
      _tripDoneTimer = Timer(const Duration(seconds: 2), _clearTripDisplay);
    }
  }

  Timer? _tripDoneTimer;

  void _clearTripDisplay() {
    if (isClosed) return;
    emit(state.copyWith(
      legs: [],
      activeIndex: 0,
      trackingMode: state.savedLocations.any((l) => l.isActive)
          ? state.trackingMode
          : TrackingMode.idle,
    ));
  }

  /// Ends the trip early. Saved stops keep being tracked.
  void clearTrip() {
    _tripDoneTimer?.cancel();
    _platform.stopRoute();
    _location.stopTracking();
    _clearTripDisplay();
  }

  String get greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning, Commuter';
    if (h < 17) return 'Good afternoon, Commuter';
    return 'Good evening, Commuter';
  }

  @override
  Future<void> close() {
    _alarmSub?.cancel();
    _tripDoneTimer?.cancel();
    return super.close();
  }
}
