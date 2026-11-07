import 'dart:convert';

import 'package:flutter/material.dart';

part 'home_section_icons.g.dart';

/// A Home section's icon: one thin line on a 64 grid, shared with the site
/// (services/web/lib/home-section-icons.json). `currentColor` in the art is
/// [color].
class HomeSectionIcon extends StatelessWidget {
  const HomeSectionIcon({
    required this.section,
    required this.color,
    this.size = 30,
    super.key,
  });

  final String section;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LinePainter(section, color)),
    ),
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.section, this.color);

  final String section;
  final Color color;

  Path _path(String value) {
    final tokens = RegExp(
      r'[MLCQZ]|-?\d*\.?\d+',
    ).allMatches(value).map((m) => m.group(0)!).toList();
    var index = 0;
    double number() => double.parse(tokens[index++]);
    final path = Path();
    while (index < tokens.length) {
      switch (tokens[index++]) {
        case 'M':
          path.moveTo(number(), number());
        case 'L':
          path.lineTo(number(), number());
        case 'C':
          path.cubicTo(
            number(),
            number(),
            number(),
            number(),
            number(),
            number(),
          );
        case 'Q':
          path.quadraticBezierTo(number(), number(), number(), number());
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    for (final raw in (_homeSectionShapes[section] as List? ?? [])) {
      final shape = raw as Map<String, dynamic>;
      canvas.drawPath(
        _path(shape['d'] as String),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = (shape['strokeWidth'] as num).toDouble()
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.section != section || old.color != color;
}
