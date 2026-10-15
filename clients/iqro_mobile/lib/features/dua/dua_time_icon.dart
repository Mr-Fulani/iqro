import 'package:flutter/material.dart';

/// Geometry matches the website's morning and evening vector marks.
class DuaTimeIcon extends StatelessWidget {
  const DuaTimeIcon({required this.evening, super.key});

  final bool evening;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 64,
      child: CustomPaint(painter: _DuaTimePainter(evening)),
    ),
  );
}

class _DuaTimePainter extends CustomPainter {
  const _DuaTimePainter(this.evening);
  final bool evening;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (evening) {
      final moon = Path()
        ..moveTo(43, 8)
        ..cubicTo(35, 8, 30, 14, 31, 21)
        ..cubicTo(32, 30, 43, 34, 50, 27)
        ..cubicTo(41, 29, 36, 17, 43, 8)
        ..close();
      canvas.drawPath(moon, fill..color = const Color(0xFFE7C27D));
      final star = Path()
        ..moveTo(14, 11)
        ..lineTo(15.2, 13.8)
        ..lineTo(18, 15)
        ..lineTo(15.2, 16.2)
        ..lineTo(14, 19)
        ..lineTo(12.8, 16.2)
        ..lineTo(10, 15)
        ..lineTo(12.8, 13.8)
        ..close();
      canvas.drawPath(star, fill..color = const Color(0xFFA99BC9));
      canvas.drawCircle(const Offset(23, 23), 1.3, fill);
      canvas.drawCircle(
        const Offset(32, 39),
        8,
        fill..color = const Color(0xFFD99473),
      );
    } else {
      canvas.drawCircle(
        const Offset(32, 28),
        10,
        fill..color = const Color(0xFFD5A34C),
      );
      stroke.color = const Color(0xFFD5A34C);
      for (final ray in const [
        [32.0, 8.0, 32.0, 13.0],
        [16.0, 15.0, 19.5, 18.5],
        [48.0, 15.0, 44.5, 18.5],
        [9.0, 28.0, 14.0, 28.0],
        [50.0, 28.0, 55.0, 28.0],
      ]) {
        canvas.drawLine(Offset(ray[0], ray[1]), Offset(ray[2], ray[3]), stroke);
      }
    }
    final hills = Path()
      ..moveTo(8, 40)
      ..quadraticBezierTo(20, 25, 32, 38)
      ..quadraticBezierTo(44, 26, 56, 40)
      ..lineTo(56, 52)
      ..lineTo(8, 52)
      ..close();
    canvas.drawPath(
      hills,
      fill..color = Color(evening ? 0xFFE1DCEB : 0xFFD6E5DA),
    );
    final foreground = Path()
      ..moveTo(8, 44)
      ..quadraticBezierTo(21, 36, 33, 44)
      ..quadraticBezierTo(45, 52, 56, 43)
      ..lineTo(56, 52)
      ..lineTo(8, 52)
      ..close();
    canvas.drawPath(
      foreground,
      fill..color = Color(evening ? 0xFF786EAD : 0xFF0B5D4A),
    );
    canvas.drawLine(
      const Offset(17, 57),
      const Offset(47, 57),
      stroke..color = Color(evening ? 0xFFA99BC9 : 0xFF91B4A5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DuaTimePainter oldDelegate) =>
      oldDelegate.evening != evening;
}
