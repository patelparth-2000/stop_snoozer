import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'search_viewmodel.dart';
import 'components/search_omnibar.dart';
import 'components/stop_result_card.dart';
import '../../core/constants/color_constants.dart';
import '../../core/constants/string_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/stop_point.dart';
import '../trip_config/trip_config_viewmodel.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onStopSelected(StopPoint stop) {
    context.read<TripConfigCubit>().addLeg(stop);
    context.push('/trip-config');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.surfaceBase,
      body: BlocBuilder<SearchCubit, SearchState>(
        builder: (context, state) => SafeArea(
          child: Column(
            children: [
              SearchOmnibar(
                controller: _ctrl,
                onChanged: context.read<SearchCubit>().onQueryChanged,
                onBack: () => context.pop(),
                isSearching: state.isSearching,
              ),
              const Divider(height: 1),
              Expanded(
                child: state.hasQuery
                    ? _ResultList(
                        results: state.results,
                        query: state.query,
                        onTap: _onStopSelected,
                      )
                    : const _PlaceholderState(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.results,
    required this.query,
    required this.onTap,
  });
  final List<StopPoint> results;
  final String query;
  final void Function(StopPoint) onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          '${StringConstants.searchNoResults} "$query"',
          style: const TextStyle(color: ColorConstants.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      padding: const EdgeInsets.only(top: AppConstants.spaceSm),
      itemBuilder: (_, i) => StopResultCard(
        stop: results[i],
        onTap: () => onTap(results[i]),
      ),
    );
  }
}

class _PlaceholderState extends StatelessWidget {
  const _PlaceholderState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_rounded, color: ColorConstants.textDisabled, size: 48),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            StringConstants.searchPlaceholder,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ColorConstants.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            StringConstants.searchPlaceholderSub,
            style: const TextStyle(fontSize: 13, color: ColorConstants.textDisabled),
          ),
        ],
      ),
    );
  }
}
