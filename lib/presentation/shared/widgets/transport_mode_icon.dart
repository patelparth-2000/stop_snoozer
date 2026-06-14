import 'package:flutter/material.dart';
import '../../../core/constants/color_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/stop_point.dart';

class TransportModeIcon extends StatelessWidget {
  const TransportModeIcon({
    super.key,
    required this.mode,
    this.size = 32.0,
  });

  final TransitMode mode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _resolveMode(mode);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }

  static (IconData, Color) _resolveMode(TransitMode m) => switch (m) {
        TransitMode.tube       => (Icons.directions_subway, ColorConstants.transportTube),
        TransitMode.bus        => (Icons.directions_bus,    ColorConstants.transportBus),
        TransitMode.rail       => (Icons.train,             ColorConstants.transportRail),
        TransitMode.dlr        => (Icons.tram,              ColorConstants.transportDlr),
        TransitMode.overground => (Icons.directions_transit, ColorConstants.transportOverground),
        TransitMode.tram       => (Icons.tram,              ColorConstants.transportTram),
        TransitMode.ferry      => (Icons.directions_boat,   ColorConstants.transportRail),
      };

  static String label(TransitMode m) => switch (m) {
        TransitMode.tube       => 'Tube',
        TransitMode.bus        => 'Bus',
        TransitMode.rail       => 'Rail',
        TransitMode.dlr        => 'DLR',
        TransitMode.overground => 'Overground',
        TransitMode.tram       => 'Tram',
        TransitMode.ferry      => 'Ferry',
      };
}
