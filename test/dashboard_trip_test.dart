// Trip and saved-stop wiring between DashboardCubit and the native service.
//
// The native side (route sequencing, snooze, process death) is covered by the
// Robolectric tests in android/app/src/test. These pin the Dart half: what the
// dashboard sends to the service, and how it follows the service's alarms.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stop_snoozer/data/models/saved_location.dart';
import 'package:stop_snoozer/data/models/stop_point.dart';
import 'package:stop_snoozer/data/models/trip_leg.dart';
import 'package:stop_snoozer/data/repositories/saved_locations_repository.dart';
import 'package:stop_snoozer/data/repositories/stop_points_repository.dart';
import 'package:stop_snoozer/data/services/location_service.dart';
import 'package:stop_snoozer/data/services/platform_channel_service.dart';
import 'package:stop_snoozer/presentation/dashboard/dashboard_viewmodel.dart';

class FakePlatform implements PlatformChannelService {
  final calls = <String>[];
  List<Map<String, dynamic>>? lastRoute;
  List<Map<String, dynamic>>? lastTargets;
  Map<String, dynamic>? activeRoute;
  final alarms = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get alarmStream => alarms.stream;

  @override
  Future<void> startRoute(List<Map<String, dynamic>> legs) async {
    calls.add('startRoute');
    lastRoute = legs;
  }

  @override
  Future<void> stopRoute() async => calls.add('stopRoute');

  @override
  Future<Map<String, dynamic>?> getActiveRoute() async => activeRoute;

  @override
  Future<void> updateTrackingTargets(List<Map<String, dynamic>> t) async {
    calls.add('updateTrackingTargets');
    lastTargets = t;
  }

  @override
  Future<void> stopTracking() async => calls.add('stopTracking');

  @override
  Future<void> stopAlarm() async => calls.add('stopAlarm');

  @override
  Future<void> startGeofence({
    required String stopId,
    required String stopName,
    required double lat,
    required double lon,
    required double radiusMetres,
    String alarmStyle = 'defconDrill',
  }) async =>
      calls.add('startGeofence');

  @override
  Future<String?> checkPendingTripGroup() async => null;

  @override
  Future<Map<String, dynamic>?> checkPendingAlarm() async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeSavedRepo implements SavedLocationsRepository {
  FakeSavedRepo(this.items);
  List<SavedLocation> items;

  @override
  Future<List<SavedLocation>> loadAll() async => [...items];
  @override
  Future<void> upsert(SavedLocation loc) async {
    items = [...items.where((l) => l.id != loc.id), loc];
  }
  @override
  Future<void> update(SavedLocation loc) async => upsert(loc);
  @override
  Future<void> delete(String id) async {
    items = items.where((l) => l.id != id).toList();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeLocation implements LocationService {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class FakeStops implements StopPointsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

StopPoint _stop(String name, double lat) => StopPoint(
      id: 'id_$name', name: name, latitude: lat, longitude: -0.1,
      mode: TransitMode.rail,
    );

SavedLocation _saved(String name, {bool active = false}) =>
    SavedLocation.fromStop(_stop(name, 51.6), radius: 800).copyWith(isActive: active);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Alarm history is written to SQLite on every alarm; give it a real
  // in-process database and a temp documents directory.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final docs = Directory.systemTemp.createTempSync('snoozer_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });

  late FakePlatform platform;
  late FakeSavedRepo saved;
  late DashboardCubit cubit;

  DashboardCubit build() => DashboardCubit(
        platform: platform,
        savedRepo: saved,
        location: FakeLocation(),
        repo: FakeStops(),
      );

  setUp(() {
    platform = FakePlatform();
    saved = FakeSavedRepo([]);
    cubit = build();
  });

  tearDown(() => cubit.close());

  Future<void> alarmFor(String name) async {
    platform.alarms.add({'stopId': 'id_$name', 'stopName': name, 'distanceMetres': 0.0});
    await Future<void>.delayed(Duration.zero);
  }

  final trip = [
    TripLeg(stop: _stop('Alpha', 51.50)),
    TripLeg(stop: _stop('Bravo', 51.52), alarmStyle: AlarmStyle.subtlePulse),
    TripLeg(stop: _stop('Charlie', 51.54), wakeRadiusMetres: 700),
  ];

  test('a trip sends every stop to the service, in order, with its settings', () {
    cubit.loadTrip(trip);
    expect(platform.calls, contains('startRoute'));
    expect(platform.calls, isNot(contains('startGeofence')));
    expect(platform.lastRoute!.map((l) => l['stopName']), ['Alpha', 'Bravo', 'Charlie']);
    expect(platform.lastRoute![1]['alarmStyle'], 'subtlePulse');
    expect(platform.lastRoute![2]['radiusMetres'], 700);
  });

  test('each stop alarm moves the timeline on; the last one clears the trip', () async {
    cubit.loadTrip(trip);
    await alarmFor('Alpha');
    expect(cubit.state.activeIndex, 1);
    expect(cubit.state.legs[0].status, LegStatus.complete);
    expect(cubit.state.legs[1].status, LegStatus.active);
    await alarmFor('Bravo');
    await alarmFor('Charlie');
    expect(cubit.state.legs.every((l) => l.status == LegStatus.complete), isTrue);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(cubit.state.hasActiveTrip, isFalse);
    expect(platform.calls, isNot(contains('stopTracking')),
        reason: 'the service ends the trip itself when the last alarm is dismissed');
  });

  test('a snoozed stop ringing again does not skip the next stop', () async {
    cubit.loadTrip(trip);
    await alarmFor('Alpha');
    await alarmFor('Alpha'); // re-ring after snooze
    expect(cubit.state.activeIndex, 1);
    expect(cubit.state.legs[1].status, LegStatus.active);
  });

  test('a saved stop ringing mid-trip is reported as itself and keeps the trip', () async {
    cubit.loadTrip(trip);
    platform.alarms.add({'stopId': 'id_Home', 'stopName': 'Home', 'distanceMetres': 10.0});
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.activeIndex, 0);
    expect(cubit.state.legs[0].status, LegStatus.active);
  });

  test('switching off the last saved stop sends an empty list, not stop-all', () async {
    saved.items = [_saved('Home', active: true)];
    await cubit.load();
    platform.calls.clear();
    await cubit.toggleSavedLocation(saved.items.first.id);
    expect(platform.calls, ['updateTrackingTargets']);
    expect(platform.lastTargets, isEmpty);
  });

  test('saved stops carry the user\'s wake radius', () async {
    saved.items = [_saved('Home')];
    await cubit.load();
    await cubit.toggleSavedLocation(saved.items.first.id);
    expect(platform.lastTargets!.single['radiusMetres'], 800);
  });

  test('deleting a switched-on saved stop stops tracking it', () async {
    saved.items = [_saved('Home', active: true), _saved('Work', active: true)];
    await cubit.load();
    platform.calls.clear();
    await cubit.deleteSavedLocation(saved.items.first.id);
    expect(platform.calls, ['updateTrackingTargets']);
    expect(platform.lastTargets!.map((t) => t['stopName']), ['Work']);
  });

  test('reopening the app redraws the trip the service is still running', () async {
    platform.activeRoute = {
      'index': 1,
      'legs': [
        {'stopId': 'id_Alpha', 'stopName': 'Alpha', 'lat': 51.5, 'lon': -0.1, 'radius': 300.0, 'mode': 'rail'},
        {'stopId': 'id_Bravo', 'stopName': 'Bravo', 'lat': 51.52, 'lon': -0.1, 'radius': 500.0, 'mode': 'tube', 'alarmStyle': 'subtlePulse'},
      ],
    };
    await cubit.load();
    expect(cubit.state.legs.map((l) => l.stop.name), ['Alpha', 'Bravo']);
    expect(cubit.state.activeIndex, 1);
    expect(cubit.state.legs[0].status, LegStatus.complete);
    expect(cubit.state.legs[1].status, LegStatus.active);
    expect(cubit.state.legs[1].wakeRadiusMetres, 500);
    expect(cubit.state.legs[1].stop.mode, TransitMode.tube);
    expect(cubit.state.legs[1].alarmStyle, AlarmStyle.subtlePulse);
  });

  test('ending a trip early stops only the trip', () {
    cubit.loadTrip(trip);
    cubit.clearTrip();
    expect(platform.calls, contains('stopRoute'));
    expect(platform.calls, isNot(contains('stopTracking')));
    expect(cubit.state.hasActiveTrip, isFalse);
  });
}
