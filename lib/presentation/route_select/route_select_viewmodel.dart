import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/stop_point.dart';
import '../../data/repositories/route_topology_repository.dart';
import '../../data/services/platform_channel_service.dart';

/// Why the app cannot offer underground tracking for a journey.
enum RouteSelectBlocker {
  none,

  /// The shipped database has no topology rows. Populate with
  /// `python tools/build_naptan_db.py --with-topology`.
  noTopologyData,

  /// No line connects these two stops in a single ride.
  notConnected,

  /// Device has no accelerometer — nothing to detect stops with.
  noSensors,
}

class RouteSelectState extends Equatable {
  const RouteSelectState({
    this.origin,
    this.destination,
    this.lines = const [],
    this.selectedLineId,
    this.viableRoutes = const [],
    this.selectedDirection,
    this.selectedBranchId,
    this.branchOptions = const [],
    this.plan = const [],
    this.loading = false,
    this.blocker = RouteSelectBlocker.none,
    this.hasBarometer = true,
    this.started = false,
    this.sensorLoggingEnabled = false,
  });

  final StopPoint? origin;
  final StopPoint? destination;

  final List<TransitLine> lines;
  final String? selectedLineId;

  /// `(direction, branchId)` pairs where origin precedes destination.
  final List<({String direction, int branchId})> viableRoutes;
  final String? selectedDirection;
  final int? selectedBranchId;

  /// Non-empty when the user must choose a branch (the Kennington case).
  final List<BranchOption> branchOptions;

  final List<PlannedStation> plan;
  final bool loading;
  final RouteSelectBlocker blocker;

  /// False on devices without a pressure sensor — accuracy is materially lower
  /// and the UI says so rather than promising what it cannot deliver.
  final bool hasBarometer;

  final bool started;

  /// Writes a per-journey sensor CSV for threshold calibration (F1).
  /// Off by default: it costs storage and is only useful during field testing.
  final bool sensorLoggingEnabled;

  /// True once there is exactly one unambiguous route to track.
  bool get isResolved =>
      selectedLineId != null &&
      selectedDirection != null &&
      selectedBranchId != null &&
      plan.length >= 2;

  int get stopCount => plan.isEmpty ? 0 : plan.length - 1;

  RouteSelectState copyWith({
    StopPoint? origin,
    StopPoint? destination,
    List<TransitLine>? lines,
    String? selectedLineId,
    List<({String direction, int branchId})>? viableRoutes,
    String? selectedDirection,
    int? selectedBranchId,
    List<BranchOption>? branchOptions,
    List<PlannedStation>? plan,
    bool? loading,
    RouteSelectBlocker? blocker,
    bool? hasBarometer,
    bool? started,
    bool? sensorLoggingEnabled,
    bool clearSelection = false,
  }) =>
      RouteSelectState(
        origin: origin ?? this.origin,
        destination: destination ?? this.destination,
        lines: lines ?? this.lines,
        selectedLineId:
            clearSelection ? null : (selectedLineId ?? this.selectedLineId),
        viableRoutes: viableRoutes ?? this.viableRoutes,
        selectedDirection:
            clearSelection ? null : (selectedDirection ?? this.selectedDirection),
        selectedBranchId:
            clearSelection ? null : (selectedBranchId ?? this.selectedBranchId),
        branchOptions: branchOptions ?? this.branchOptions,
        plan: clearSelection ? const [] : (plan ?? this.plan),
        loading: loading ?? this.loading,
        blocker: blocker ?? this.blocker,
        hasBarometer: hasBarometer ?? this.hasBarometer,
        started: started ?? this.started,
        sensorLoggingEnabled:
            sensorLoggingEnabled ?? this.sensorLoggingEnabled,
      );

  @override
  List<Object?> get props => [
        origin, destination, lines, selectedLineId, viableRoutes,
        selectedDirection, selectedBranchId, branchOptions, plan,
        loading, blocker, hasBarometer, started, sensorLoggingEnabled,
      ];
}

/// Drives mandatory route pre-selection (U4).
///
/// Pre-selection is not a UX preference — it is what makes underground tracking
/// tractable. Multiple routes reach most destinations, and discriminating them
/// from sensors needs roughly three stops of evidence, long after the branch
/// decision has been made. Resolving the route up front, while the user is above
/// ground and attentive, removes the ambiguity entirely.
class RouteSelectCubit extends Cubit<RouteSelectState> {
  RouteSelectCubit({
    RouteTopologyRepository? topology,
    PlatformChannelService? platform,
  })  : _topology = topology ?? RouteTopologyRepository(),
        _platform = platform ?? PlatformChannelService.instance,
        super(const RouteSelectState());

  final RouteTopologyRepository _topology;
  final PlatformChannelService _platform;

  Future<void> begin({
    required StopPoint origin,
    required StopPoint destination,
  }) async {
    emit(state.copyWith(
      origin: origin,
      destination: destination,
      loading: true,
      clearSelection: true,
      blocker: RouteSelectBlocker.none,
      started: false,
    ));

    final capability = await _platform.getUndergroundCapability();
    if (!capability.hasAccelerometer) {
      emit(state.copyWith(
        loading: false,
        blocker: RouteSelectBlocker.noSensors,
        hasBarometer: capability.hasBarometer,
      ));
      return;
    }

    if (!await _topology.hasTopology()) {
      emit(state.copyWith(
        loading: false,
        blocker: RouteSelectBlocker.noTopologyData,
        hasBarometer: capability.hasBarometer,
      ));
      return;
    }

    // Only lines serving *both* ends can carry this journey in one ride.
    final originLines = await _topology.linesServing(origin.id);
    final destLines = await _topology.linesServing(destination.id);
    final destIds = destLines.map((l) => l.id).toSet();
    final shared = originLines.where((l) => destIds.contains(l.id)).toList();

    emit(state.copyWith(
      lines: shared,
      loading: false,
      hasBarometer: capability.hasBarometer,
      blocker: shared.isEmpty
          ? RouteSelectBlocker.notConnected
          : RouteSelectBlocker.none,
    ));

    // Single option: choose it rather than making the user tap the only choice.
    if (shared.length == 1) await selectLine(shared.first.id);
  }

  Future<void> selectLine(String lineId) async {
    final origin = state.origin;
    final destination = state.destination;
    if (origin == null || destination == null) return;

    emit(state.copyWith(
      selectedLineId: lineId,
      loading: true,
      selectedDirection: null,
      selectedBranchId: null,
      branchOptions: const [],
      plan: const [],
    ));

    final routes = await _topology.viableRoutes(
      lineId: lineId,
      originStopId: origin.id,
      destinationStopId: destination.id,
    );

    if (routes.isEmpty) {
      emit(state.copyWith(
        loading: false,
        viableRoutes: const [],
        blocker: RouteSelectBlocker.notConnected,
      ));
      return;
    }

    emit(state.copyWith(
      viableRoutes: routes,
      loading: false,
      blocker: RouteSelectBlocker.none,
    ));

    // Direction is derived, never asked: only one ordering puts the origin
    // before the destination. Asking would invite the user to get it wrong.
    if (routes.length == 1) {
      await selectRoute(routes.first.direction, routes.first.branchId);
    } else {
      await _loadBranchOptions(lineId, routes);
    }
  }

  /// Surfaces the branch choice at the divergence station.
  Future<void> _loadBranchOptions(
    String lineId,
    List<({String direction, int branchId})> routes,
  ) async {
    final origin = state.origin;
    if (origin == null) return;
    final direction = routes.first.direction;

    // Ask at the divergence point on the path, which is where the user's own
    // decision actually happens.
    final options = <BranchOption>[];
    for (final r in routes.where((r) => r.direction == direction)) {
      final plan = await _topology.buildPlan(
        lineId: lineId,
        direction: r.direction,
        branchId: r.branchId,
        originStopId: origin.id,
        destinationStopId: state.destination!.id,
      );
      for (final station in plan) {
        final branchOpts = await _topology.branchOptionsAt(
          lineId: lineId,
          direction: r.direction,
          stopId: station.stopId,
        );
        if (branchOpts.isNotEmpty) {
          options.addAll(branchOpts.where(
            (b) => !options.any((o) => o.branchId == b.branchId),
          ));
          break;
        }
      }
    }

    emit(state.copyWith(
      selectedDirection: direction,
      branchOptions: options,
    ));
  }

  Future<void> selectRoute(String direction, int branchId) async {
    final origin = state.origin;
    final destination = state.destination;
    final lineId = state.selectedLineId;
    if (origin == null || destination == null || lineId == null) return;

    emit(state.copyWith(loading: true));
    final plan = await _topology.buildPlan(
      lineId: lineId,
      direction: direction,
      branchId: branchId,
      originStopId: origin.id,
      destinationStopId: destination.id,
    );

    emit(state.copyWith(
      selectedDirection: direction,
      selectedBranchId: branchId,
      plan: plan,
      loading: false,
      blocker: plan.length < 2
          ? RouteSelectBlocker.notConnected
          : RouteSelectBlocker.none,
    ));
  }

  void setSensorLogging(bool enabled) =>
      emit(state.copyWith(sensorLoggingEnabled: enabled));

  /// Hands the resolved plan to the native engine.
  ///
  /// [enableSensorLogging] should only be set for field-test runs; it writes a
  /// CSV per journey to external storage.
  Future<void> startTracking({bool enableSensorLogging = false}) async {
    if (!state.isResolved) return;
    final json = RouteTopologyRepository.encodePlan(
      lineId: state.selectedLineId!,
      direction: state.selectedDirection!,
      stations: state.plan,
      startIndex: 0,
    );
    await _platform.startUndergroundTracking(
      journeyPlan: json,
      enableSensorLogging: enableSensorLogging,
    );
    emit(state.copyWith(started: true));
  }
}
