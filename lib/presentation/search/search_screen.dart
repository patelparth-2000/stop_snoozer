import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'search_viewmodel.dart';
import 'components/search_omnibar.dart';
import 'components/search_filter_bar.dart';
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
              // Filter chips
              const SizedBox(height: AppConstants.spaceSm),
              SearchFilterBar(
                activeFilter: state.activeFilter,
                onFilterChanged: context.read<SearchCubit>().setFilter,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              // Postcode mode / error banner
              if (state.isPostcodeMode && state.postcodeError == null)
                _ModeBanner(
                  message: StringConstants.searchPostcodeHint,
                  color: ColorConstants.primaryGlow,
                  icon: Icons.location_on_outlined,
                ),
              if (state.postcodeError != null)
                _ModeBanner(
                  message: state.postcodeError!,
                  color: Colors.red.withAlpha(60),
                  icon: Icons.error_outline_rounded,
                  textColor: Colors.red.shade300,
                ),
              const Divider(height: 1),
              Expanded(
                child: state.hasQuery
                    ? _ResultList(
                        results: state.results,
                        query: state.query,
                        duplicateNames: state.duplicateNames,
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

// ── Postcode / error banner ────────────────────────────────────────────────

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({
    required this.message,
    required this.color,
    required this.icon,
    this.textColor,
  });

  final String message;
  final Color color;
  final IconData icon;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? ColorConstants.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.containerMargin,
        vertical: AppConstants.spaceXs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: AppConstants.spaceSm),
          Flexible(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result list ────────────────────────────────────────────────────────────

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.results,
    required this.query,
    required this.duplicateNames,
    required this.onTap,
  });

  final List<StopPoint> results;
  final String query;
  final Set<String> duplicateNames;
  final void Function(StopPoint) onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          '${StringConstants.searchNoResults} "$query"',
          style: const TextStyle(
            color: ColorConstants.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      padding: const EdgeInsets.only(top: AppConstants.spaceSm),
      itemBuilder: (_, i) {
        final stop = results[i];
        return StopResultCard(
          stop: stop,
          onTap: () => onTap(stop),
          showIndicator: duplicateNames.contains(stop.name),
        );
      },
    );
  }
}

// ── Placeholder ────────────────────────────────────────────────────────────

class _PlaceholderState extends StatelessWidget {
  const _PlaceholderState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_rounded,
            color: ColorConstants.textDisabled,
            size: 48,
          ),
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
            style: const TextStyle(
              fontSize: 13,
              color: ColorConstants.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}
