import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';

class SearchOmnibar extends StatefulWidget {
  const SearchOmnibar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.isSearching,
    this.onBack,
  });

  final TextEditingController controller;
  final void Function(String) onChanged;
  final bool isSearching;
  final VoidCallback? onBack;

  @override
  State<SearchOmnibar> createState() => _SearchOmnibarState();
}

class _SearchOmnibarState extends State<SearchOmnibar> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    widget.controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceXs,
      ),
      child: Row(
        children: [
          if (widget.onBack != null) ...[
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 44,
                height: 52,
                decoration: BoxDecoration(
                  color: ColorConstants.surfaceSecondary,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: ColorConstants.surfaceElevated),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ColorConstants.textSecondary,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceSm),
          ],
          Expanded(
            child: AnimatedContainer(
              duration:
                  const Duration(milliseconds: AppConstants.durationFast),
              height: 52,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: focused
                      ? ColorConstants.primary.withValues(alpha: 0.65)
                      : ColorConstants.surfaceElevated,
                  width: focused ? 1.5 : 1.0,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: ColorConstants.primary.withValues(alpha: 0.08),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.search_rounded,
                      color: ColorConstants.primary,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      autofocus: true,
                      onChanged: widget.onChanged,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: ColorConstants.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: 'Station, stop or area…',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: ColorConstants.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  if (widget.isSearching)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ColorConstants.primary,
                        ),
                      ),
                    )
                  else if (hasText)
                    GestureDetector(
                      onTap: _clear,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          Icons.close_rounded,
                          color: ColorConstants.textDisabled,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
