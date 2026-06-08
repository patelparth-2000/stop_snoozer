import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';

class SlideToDismissBar extends StatefulWidget {
  const SlideToDismissBar({
    super.key,
    required this.onProgressChanged,
    required this.onDismissed,
    this.progress = 0.0,
  });

  final void Function(double progress) onProgressChanged;
  final VoidCallback onDismissed;
  final double progress;

  @override
  State<SlideToDismissBar> createState() => _SlideToDismissBarState();
}

class _SlideToDismissBarState extends State<SlideToDismissBar> {
  double _localProgress = 0.0;
  double _trackWidth = 0.0;
  static const double _thumbSize = 52.0;

  @override
  void didUpdateWidget(SlideToDismissBar old) {
    super.didUpdateWidget(old);
    if (widget.progress != old.progress && widget.progress != _localProgress) {
      setState(() => _localProgress = widget.progress);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_trackWidth <= 0) return;
    final newProgress = (_localProgress + details.delta.dx / (_trackWidth - _thumbSize))
        .clamp(0.0, 1.0);
    setState(() => _localProgress = newProgress);
    widget.onProgressChanged(newProgress);
    if (newProgress >= AppConstants.dismissThreshold) {
      widget.onDismissed();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_localProgress < AppConstants.dismissThreshold) {
      setState(() => _localProgress = 0.0);
      widget.onProgressChanged(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          StringConstants.alarmSlide,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: ColorConstants.textSecondary,
            letterSpacing: 0.05,
          ),
        ),
        const SizedBox(height: AppConstants.spaceMd),
        LayoutBuilder(
          builder: (_, constraints) {
            _trackWidth = constraints.maxWidth;
            final thumbLeft = _localProgress * (_trackWidth - _thumbSize);
            return Container(
              height: _thumbSize,
              decoration: BoxDecoration(
                color: ColorConstants.surfaceElevated,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Stack(
                children: [
                  // Fill indicator
                  FractionallySizedBox(
                    widthFactor: _localProgress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ColorConstants.errorGlow,
                        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      ),
                    ),
                  ),
                  // Draggable thumb
                  Positioned(
                    left: thumbLeft,
                    top: 0,
                    child: GestureDetector(
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ColorConstants.error,
                          boxShadow: [
                            BoxShadow(
                              color: ColorConstants.errorGlow,
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
