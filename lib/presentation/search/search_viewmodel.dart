import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';
import '../../data/repositories/stop_points_repository.dart';
import '../../data/services/postcode_geocoder.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/string_constants.dart';

// ── Transit filter ─────────────────────────────────────────────────────────

enum TransitFilter { all, bus, tube, rail }

extension TransitFilterX on TransitFilter {
  String get label {
    switch (this) {
      case TransitFilter.all:  return 'All';
      case TransitFilter.bus:  return 'Bus';
      case TransitFilter.tube: return 'Tube & DLR';
      case TransitFilter.rail: return 'Rail';
    }
  }

  /// DB transit_type values for this filter, or null for "no filter".
  List<String>? get dbTypes {
    switch (this) {
      case TransitFilter.all:  return null;
      case TransitFilter.bus:  return ['bus'];
      case TransitFilter.tube: return ['underground', 'dlr', 'tram'];
      case TransitFilter.rail: return ['train', 'overground'];
    }
  }
}

// ── State ──────────────────────────────────────────────────────────────────

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.duplicateNames = const {},
    this.isSearching = false,
    this.activeFilter = TransitFilter.all,
    this.isPostcodeMode = false,
    this.postcodeError,
  });

  final String query;
  final List<StopPoint> results;
  /// Names that appear more than once in [results] — cards with these names
  /// should display their indicator to disambiguate.
  final Set<String> duplicateNames;
  final bool isSearching;
  final TransitFilter activeFilter;
  /// True when the current query matches the UK postcode pattern.
  final bool isPostcodeMode;
  /// Non-null when a postcode lookup returned no match.
  final String? postcodeError;

  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    List<StopPoint>? results,
    Set<String>? duplicateNames,
    bool? isSearching,
    TransitFilter? activeFilter,
    bool? isPostcodeMode,
    String? postcodeError,
    bool clearPostcodeError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        duplicateNames: duplicateNames ?? this.duplicateNames,
        isSearching: isSearching ?? this.isSearching,
        activeFilter: activeFilter ?? this.activeFilter,
        isPostcodeMode: isPostcodeMode ?? this.isPostcodeMode,
        postcodeError: clearPostcodeError ? null : (postcodeError ?? this.postcodeError),
      );

  @override
  List<Object?> get props => [
        query, results, duplicateNames, isSearching,
        activeFilter, isPostcodeMode, postcodeError,
      ];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class SearchCubit extends Cubit<SearchState> {
  SearchCubit({StopPointsRepository? repo})
      : _repo = repo ?? StopPointsRepository(),
        super(const SearchState());

  final StopPointsRepository _repo;
  Timer? _debounce;

  // ── Filter ────────────────────────────────────────────────────────────────

  void setFilter(TransitFilter filter) {
    if (state.activeFilter == filter) return;
    emit(state.copyWith(activeFilter: filter, clearPostcodeError: true));
    // Re-run the current query with the new filter.
    if (state.hasQuery) {
      _debounce?.cancel();
      if (state.isPostcodeMode) {
        _searchByPostcode(state.query.trim());
      } else {
        _search(state.query.trim());
      }
    }
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  void onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      emit(SearchState(activeFilter: state.activeFilter));
      return;
    }

    final isPostcode = PostcodeGeocoder.isPostcode(value);
    emit(state.copyWith(
      query: value,
      isSearching: true,
      isPostcodeMode: isPostcode,
      clearPostcodeError: true,
    ));

    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () => isPostcode
          ? _searchByPostcode(value.trim())
          : _search(value.trim()),
    );
  }

  // ── Search implementations ────────────────────────────────────────────────

  Future<void> _search(String query) async {
    final results = await _repo.search(query, transitTypes: state.activeFilter.dbTypes);
    emit(state.copyWith(
      results: results,
      duplicateNames: _computeDuplicates(results),
      isSearching: false,
    ));
  }

  Future<void> _searchByPostcode(String postcode) async {
    final results = await _repo.postcodeSearch(
      postcode,
      transitTypes: state.activeFilter.dbTypes,
    );
    if (results == null) {
      emit(state.copyWith(
        isSearching: false,
        postcodeError: StringConstants.searchPostcodeNotFound,
        results: const [],
        duplicateNames: const {},
      ));
      return;
    }
    emit(state.copyWith(
      results: results,
      duplicateNames: _computeDuplicates(results),
      isSearching: false,
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Set<String> _computeDuplicates(List<StopPoint> stops) {
    final counts = <String, int>{};
    for (final s in stops) {
      counts[s.name] = (counts[s.name] ?? 0) + 1;
    }
    return counts.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toSet();
  }

  void clear() {
    _debounce?.cancel();
    emit(SearchState(activeFilter: state.activeFilter));
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
