import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/number_formatters.dart';

class SplashProgressBar extends StatelessWidget {
  const SplashProgressBar({
    super.key,
    required this.progress,
    this.error,
  });

  final double progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _ErrorState(message: error!);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            StringConstants.splashDecompressing,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: ColorConstants.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: ColorConstants.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(ColorConstants.primary),
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              NumberFormatters.percentage(progress),
              style: GoogleFonts.sora(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ColorConstants.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.containerMargin),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: ColorConstants.error, size: 32),
          const SizedBox(height: AppConstants.spaceSm),
          Text(
            StringConstants.error,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ColorConstants.error,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: ColorConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
