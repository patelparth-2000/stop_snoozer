import 'package:flutter/material.dart';
import '../../../core/theme/theme_service.dart';

class StopSnoozerLogo extends StatelessWidget {
  const StopSnoozerLogo({super.key, this.size = 80});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (_, _) => CustomPaint(
        size: Size(size, size),
        painter: _LogoPainter(ThemeService.instance.logoColor),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Arch — bell/shelter outline
    final arch = Path()
      ..moveTo(50 * s, 15 * s)
      ..cubicTo(33.4 * s, 15 * s, 20 * s, 28.4 * s, 20 * s, 45 * s)
      ..lineTo(20 * s, 70 * s)
      ..lineTo(80 * s, 70 * s)
      ..lineTo(80 * s, 45 * s)
      ..cubicTo(80 * s, 28.4 * s, 66.6 * s, 15 * s, 50 * s, 15 * s)
      ..close();
    canvas.drawPath(arch, stroke);

    // Base bar
    final bar = Path()
      ..moveTo(15 * s, 75 * s)
      ..lineTo(85 * s, 75 * s)
      ..lineTo(85 * s, 80 * s)
      ..lineTo(15 * s, 80 * s)
      ..close();
    canvas.drawPath(bar, stroke);

    // Inner crescent / moon (filled)
    final moon = Path()
      ..moveTo(50 * s, 30 * s)
      ..cubicTo(58.3 * s, 30 * s, 65 * s, 36.7 * s, 65 * s, 45 * s)
      ..cubicTo(65 * s, 47.1 * s, 64.6 * s, 49.1 * s, 63.8 * s, 50.9 * s)
      ..cubicTo(62.3 * s, 49.8 * s, 60.5 * s, 49.1 * s, 58.5 * s, 49.1 * s)
      ..cubicTo(53.8 * s, 49.1 * s, 50 * s, 52.9 * s, 50 * s, 57.6 * s)
      ..cubicTo(50 * s, 58.8 * s, 50.3 * s, 60 * s, 50.7 * s, 61 * s)
      ..cubicTo(44.4 * s, 59.6 * s, 39.7 * s, 53.9 * s, 39.7 * s, 47.1 * s)
      ..cubicTo(39.7 * s, 38.8 * s, 46.4 * s, 32.1 * s, 54.7 * s, 32.1 * s)
      ..close();
    canvas.drawPath(moon, fill);

    // Dot below base bar
    canvas.drawCircle(Offset(50 * s, 85 * s), 5 * s, fill);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}
