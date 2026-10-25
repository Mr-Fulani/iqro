import 'package:flutter/material.dart';

/// Du'a: a mihrab with a hanging lamp. No icon font has this glyph, so only
/// [IqroIcon] draws it; a plain [Icon] shows nothing.
const iqroDuaIcon = IconData(0xF0001, fontFamily: 'IqroDrawn');

/// Prayer: a figure in sujud. Drawn by [IqroIcon] only, like [iqroDuaIcon].
const iqroSalahIcon = IconData(0xF0002, fontFamily: 'IqroDrawn');

/// Uses the approved IQRO seal wherever an open-book icon was displayed, and
/// draws the icons no font provides.
class IqroIcon extends Icon {
  const IqroIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
  });

  @override
  Widget build(BuildContext context) {
    final seal =
        icon == Icons.menu_book ||
        icon == Icons.menu_book_outlined ||
        icon == Icons.menu_book_rounded ||
        icon == Icons.auto_stories_outlined;
    final drawn = icon == iqroDuaIcon || icon == iqroSalahIcon;
    if (!seal && !drawn) return super.build(context);
    final theme = IconTheme.of(context);
    final baseSize = size ?? theme.size ?? kDefaultFontSize;
    final extent = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(baseSize)
        : baseSize;
    if (!seal) {
      final iconColor = color ?? theme.color ?? const Color(0xFF000000);
      final paint = iconColor.withValues(
        alpha: iconColor.a * (theme.opacity ?? 1),
      );
      return Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(
          // Centred in a larger box, as Icon centres its glyph.
          child: SizedBox.square(
            dimension: extent,
            child: Center(
              child: SizedBox.square(
                dimension: extent,
                child: CustomPaint(
                  painter: icon == iqroSalahIcon
                      ? _SujudPainter(paint)
                      : _DuaMihrabPainter(paint),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final opacity = (theme.opacity ?? 1) * ((color ?? theme.color)?.a ?? 1);
    return Semantics(
      label: semanticLabel,
      child: Image.asset(
        'assets/brand/iqro-logo.png',
        width: extent,
        height: extent,
        fit: BoxFit.contain,
        opacity: AlwaysStoppedAnimation(opacity),
        excludeFromSemantics: true,
      ),
    );
  }
}

/// A mihrab with a hanging lamp on a 24-unit grid, stroked like Material's
/// outlined icons.
class _DuaMihrabPainter extends CustomPainter {
  const _DuaMihrabPainter(this.color);
  final Color color;

  static final _arch = Path()
    ..moveTo(4.5, 21.5)
    ..lineTo(4.5, 11.5)
    ..quadraticBezierTo(4.5, 5.5, 12, 2)
    ..quadraticBezierTo(19.5, 5.5, 19.5, 11.5)
    ..lineTo(19.5, 21.5)
    ..close();
  static final _lamp = Path()
    ..moveTo(10.5, 8.2)
    ..lineTo(13.5, 8.2)
    ..lineTo(14.4, 9.6)
    ..quadraticBezierTo(15.6, 12.3, 14.2, 15)
    ..lineTo(9.8, 15)
    ..quadraticBezierTo(8.4, 12.3, 9.6, 9.6)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(_arch, stroke)
      ..drawLine(const Offset(12, 2), const Offset(12, 8), thin)
      ..drawPath(_lamp, Paint()..color = color)
      ..drawLine(const Offset(10.5, 16.2), const Offset(13.5, 16.2), thin)
      ..restore();
  }

  @override
  bool shouldRepaint(_DuaMihrabPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A figure in sujud, facing the qibla on the left: forehead and palms on the
/// ground, hips raised, knees and toes down. Same grid and strokes as
/// [_DuaMihrabPainter].
class _SujudPainter extends CustomPainter {
  const _SujudPainter(this.color);
  final Color color;

  static final _body = Path()
    ..moveTo(6.9, 14.6)
    ..cubicTo(9.6, 10.2, 12.6, 7.6, 16, 7.6)
    ..cubicTo(18.3, 7.6, 18.9, 9.4, 18.6, 11.6)
    ..lineTo(17.9, 19);
  static final _arm = Path()
    ..moveTo(8.8, 12.6)
    ..quadraticBezierTo(11.2, 15.9, 9.3, 19);
  static final _toes = Path()
    ..moveTo(20.8, 19)
    ..lineTo(21.8, 16.9);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawLine(const Offset(2, 19), const Offset(22, 19), stroke)
      ..drawCircle(const Offset(4.7, 16.5), 2.2, Paint()..color = color)
      ..drawPath(_body, stroke)
      ..drawPath(_arm, stroke)
      ..drawPath(_toes, stroke)
      ..restore();
  }

  @override
  bool shouldRepaint(_SujudPainter oldDelegate) => oldDelegate.color != color;
}
