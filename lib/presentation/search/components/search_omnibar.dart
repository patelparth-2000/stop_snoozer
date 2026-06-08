import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class SearchOmnibar extends StatelessWidget {
  const SearchOmnibar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onBack,
    required this.isSearching,
  });

  final TextEditingController controller;
  final void Function(String) onChanged;
  final VoidCallback onBack;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ColorConstants.surfaceBase,
      padding: EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceMd,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: ColorConstants.textPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSm),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onChanged,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: ColorConstants.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: StringConstants.searchHint,
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: ColorConstants.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMd,
                  ),
                  border: InputBorder.none,
                  suffixIcon: isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ColorConstants.primary,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
