import 'package:flutter/material.dart';

import '../theme.dart';

/// The Homzy house-with-window mark, drawn to match the SVG used in the web
/// UI (a navy house outline with a 2×2 blue window grid).
class HouseLogo extends StatelessWidget {
  const HouseLogo({
    super.key,
    this.size = 40,
    this.outline = Brand.navy,
    this.window = Brand.blue,
  });

  final double size;
  final Color outline;
  final Color window;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HousePainter(outline: outline, window: window),
      ),
    );
  }
}

/// Circular navy avatar with a white house mark — used for the bot in chat.
class BrokerAvatar extends StatelessWidget {
  const BrokerAvatar({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Brand.navy,
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: CustomPaint(
        painter: _HousePainter(outline: Colors.white, window: Brand.blue),
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  _HousePainter({required this.outline, required this.window});

  final Color outline;
  final Color window;

  @override
  void paint(Canvas canvas, Size size) {
    // Work in a 64×64 design space, scaled to the widget size.
    final s = size.width / 64.0;
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final roof = Path()
      ..moveTo(10 * s, 56 * s)
      ..lineTo(10 * s, 28 * s)
      ..lineTo(32 * s, 10 * s)
      ..lineTo(54 * s, 28 * s)
      ..lineTo(54 * s, 56 * s);
    canvas.drawPath(roof, stroke);

    final win = Paint()..color = window;
    final r = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 7, 7),
      const Radius.circular(1.5),
    );
    for (final pos in const [
      Offset(24, 34),
      Offset(33, 34),
      Offset(24, 43),
      Offset(33, 43),
    ]) {
      canvas.save();
      canvas.translate(pos.dx * s, pos.dy * s);
      canvas.scale(s);
      canvas.drawRRect(r, win);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HousePainter old) =>
      old.outline != outline || old.window != window;
}
