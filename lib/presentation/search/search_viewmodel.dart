import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/stop_point.dart';
import '../../data/repositories/stop_points_repository.dart';
import '../../core/constants/app_constants.dart';

// ── State ──────────────────────────────────────────────────────────────────

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
  });

  final String query;
  final List<StopPoint> results;
  final bool isSearching;

  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    List<StopPoint>? results,
    bool? isSearching,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        isSearching: isSearching ?? this.isSearching,
      );

  @override
  List<Object?> get props => [query, results, isSearching];
}

// ── Cubit (ViewModel) ─────────────────────────────────────────────────────

class SearchCubit extends Cubit<SearchState> {
  SearchCubit({StopPointsRepository? repo})
      : _repo = repo ?? StopPointsRepository(),
        super(const SearchState());

  final StopPointsRepository _repo;
  Timer? _debounce;

  void onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      emit(const SearchState());
      return;
    }
    emit(state.copyWith(query: value, isSearching: true));
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String query) async {
    final results = await _repo.search(query);
    emit(state.copyWith(results: results, isSearching: false));
  }

  void clear() {
    _debounce?.cancel();
    emit(const SearchState());
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
