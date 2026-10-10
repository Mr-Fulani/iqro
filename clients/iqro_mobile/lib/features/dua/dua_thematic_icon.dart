import 'dart:convert';
import 'package:flutter/material.dart';
import 'dua_time_icon.dart';

part 'dua_topic_icons.g.dart';

class DuaThematicIcon extends StatelessWidget {
  const DuaThematicIcon({required this.topic, super.key});
  final String topic;

  @override
  Widget build(BuildContext context) {
    if (topic == 'morning' || topic == 'evening') {
      return DuaTimeIcon(evening: topic == 'evening');
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 64,
        child: CustomPaint(painter: _TopicPainter(topic)),
      ),
    );
  }
}

class _TopicPainter extends CustomPainter {
  const _TopicPainter(this.topic);
  final String topic;

  Color _color(String value) =>
      Color(int.parse('ff${value.substring(1)}', radix: 16));

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
    for (final raw in (_duaVectorShapes[topic] as List? ?? [])) {
      final shape = raw as Map<String, dynamic>;
      double value(String key) => (shape[key] as num? ?? 0).toDouble();
      final path = switch (shape['tag']) {
        'circle' =>
          Path()..addOval(
            Rect.fromCircle(
              center: Offset(value('cx'), value('cy')),
              radius: value('r'),
            ),
          ),
        'rect' =>
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                value('x'),
                value('y'),
                value('width'),
                value('height'),
              ),
              Radius.circular(value('rx')),
            ),
          ),
        _ => _path(shape['d'] as String),
      };
      if (shape['fill'] != 'none') {
        canvas.drawPath(path, Paint()..color = _color(shape['fill'] as String));
      }
      if (shape['stroke'] != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = _color(shape['stroke'] as String)
            ..style = PaintingStyle.stroke
            ..strokeWidth = value('strokeWidth')
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TopicPainter oldDelegate) => oldDelegate.topic != topic;
}
