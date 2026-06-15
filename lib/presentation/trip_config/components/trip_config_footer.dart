import 'package:flutter/material.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/string_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../shared/widgets/snoozer_button.dart';

class TripConfigFooter extends StatelessWidget {
  const TripConfigFooter({
    super.key,
    required this.onArm,
    required this.onClear,
    this.canArm = true,
  });

  final VoidCallback onArm;
  final VoidCallback onClear;
  final bool canArm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.containerMargin,
        AppConstants.spaceMd,
        AppConstants.containerMargin,
        AppConstants.spaceMd + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ColorConstants.surfaceBase,
        border: Border(top: BorderSide(color: ColorConstants.divider, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: SnoozerButton(
              label: StringConstants.tripConfigClear,
              onTap: onClear,
              variant: SnoozerButtonVariant.secondary,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          Expanded(
            flex: 2,
            child: SnoozerButton(
              label: StringConstants.tripConfigArm,
              onTap: canArm ? onArm : null,
              icon: Icons.shield_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
