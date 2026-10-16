import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'mushaf_paper.dart';

/// Ornamental surah-header cartouche of the printed Mushaf. It is the same
/// 156×60 nine-slice as the website's `services/web/public/mushaf/
/// surah-frame.svg`: two 72-unit end caps keep their proportions and the
/// 12-unit patterned tile repeats across the line, so the frame spans any
/// width and stays vector-sharp at every pixel density.
void paintSurahHeaderFrame(Canvas canvas, Rect rect) {
  const cap = 72.0;
  const tile = 12.0;
  final scale = rect.height / 60;
  final middle = math.max(0.0, rect.width / scale - 2 * cap);
  final tiles = math.max(1, (middle / tile).round());
  final end = cap + middle;
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(scale);
  _paintCap(canvas);
  canvas.drawRect(Rect.fromLTRB(cap, 2, end, 12), _band);
  canvas.drawRect(Rect.fromLTRB(cap, 48, end, 58), _band);
  canvas.drawRect(Rect.fromLTRB(cap, 12, end, 16), _ring);
  canvas.drawRect(Rect.fromLTRB(cap, 44, end, 48), _ring);
  for (final (y, paint) in [
    (2.0, _outer),
    (58.0, _outer),
    (12.0, _rule),
    (48.0, _rule),
    (16.0, _line),
    (44.0, _line),
  ]) {
    canvas.drawLine(Offset(cap, y), Offset(end, y), paint);
  }
  for (var index = 0; index < tiles; index++) {
    final x = cap + (index + .5) * middle / tiles;
    canvas.drawPath(_diamond(x, 7, 3), _ornament);
    canvas.drawPath(_diamond(x, 53, 3), _ornament);
  }
  canvas.translate(2 * cap + middle, 0);
  canvas.scale(-1, 1);
  _paintCap(canvas);
  canvas.restore();
}

final _band = Paint()..color = mushafAccentColor.withValues(alpha: .2);
final _ring = Paint()..color = mushafAccentColor.withValues(alpha: .09);
final _ornament = Paint()..color = mushafAccentColor.withValues(alpha: .6);
final _inset = Paint()..color = mushafAccentColor.withValues(alpha: .45);
final _paper = Paint()..color = mushafPaperColor;
final _dot = Paint()..color = mushafInkColor;
final _outer = _stroke(mushafInkColor, 1.6);
final _rule = _stroke(mushafAccentColor, .9);
final _line = _stroke(mushafInkColor, 1);

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width;

Path _diamond(double x, double y, double radius) => Path()
  ..moveTo(x, y - radius)
  ..lineTo(x + radius, y)
  ..lineTo(x, y + radius)
  ..lineTo(x - radius, y)
  ..close();

/// Adds the cartouche end that points at the medallion, from (72,16) to
/// (72,44).
Path _cartoucheEnd(Path path) => path
  ..lineTo(56, 16)
  ..cubicTo(50, 16, 46, 24, 40, 30)
  ..cubicTo(46, 36, 50, 44, 56, 44)
  ..lineTo(72, 44);

final _capBand = Path()
  ..moveTo(2, 2)
  ..lineTo(72, 2)
  ..lineTo(72, 12)
  ..lineTo(12, 12)
  ..lineTo(12, 48)
  ..lineTo(72, 48)
  ..lineTo(72, 58)
  ..lineTo(2, 58)
  ..close();
final _capRing =
    _cartoucheEnd(
        Path()
          ..moveTo(12, 12)
          ..lineTo(72, 12)
          ..lineTo(72, 16),
      )
      ..lineTo(72, 48)
      ..lineTo(12, 48)
      ..close();
final _capOuter = Path()
  ..moveTo(72, 2)
  ..lineTo(6, 2)
  ..quadraticBezierTo(2, 2, 2, 6)
  ..lineTo(2, 54)
  ..quadraticBezierTo(2, 58, 6, 58)
  ..lineTo(72, 58);
final _capRule = Path()
  ..moveTo(72, 12)
  ..lineTo(12, 12)
  ..lineTo(12, 48)
  ..lineTo(72, 48);
final _capLine = _cartoucheEnd(Path()..moveTo(72, 16));
final _capOrnaments = () {
  final path = Path();
  for (final x in <double>[18, 30, 42, 54, 66]) {
    path
      ..addPath(_diamond(x, 7, 3), Offset.zero)
      ..addPath(_diamond(x, 53, 3), Offset.zero);
  }
  for (final y in <double>[18, 30, 42]) {
    path.addPath(_diamond(7, y, 3), Offset.zero);
  }
  return path;
}();
final _medallion = Path()
  ..moveTo(14, 30)
  ..lineTo(26, 16)
  ..lineTo(38, 30)
  ..lineTo(26, 44)
  ..close();

void _paintCap(Canvas canvas) {
  canvas
    ..drawPath(_capBand, _band)
    ..drawPath(_capRing, _ring)
    ..drawPath(_capOuter, _outer)
    ..drawPath(_capRule, _rule)
    ..drawPath(_capLine, _line)
    ..drawPath(_capOrnaments, _ornament)
    ..drawCircle(const Offset(7, 7), 2.2, _dot)
    ..drawCircle(const Offset(7, 53), 2.2, _dot)
    ..drawPath(_medallion, _paper)
    ..drawPath(_medallion, _rule)
    ..drawPath(_diamond(26, 30, 7), _inset)
    ..drawCircle(const Offset(26, 30), 2.2, _paper);
}
