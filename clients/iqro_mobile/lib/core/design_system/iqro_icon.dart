import 'package:flutter/material.dart';

/// Hands raised in du'a. No icon font has this glyph, so only [IqroIcon]
/// draws it; a plain [Icon] shows nothing.
const iqroDuaIcon = IconData(0xF0001, fontFamily: 'IqroDrawn');

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
    if (!seal && icon != iqroDuaIcon) return super.build(context);
    final theme = IconTheme.of(context);
    final baseSize = size ?? theme.size ?? kDefaultFontSize;
    final extent = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(baseSize)
        : baseSize;
    if (!seal) {
      final iconColor = color ?? theme.color ?? const Color(0xFF000000);
      return Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: extent,
            child: CustomPaint(
              painter: _DuaHandsPainter(
                iconColor.withValues(alpha: iconColor.a * (theme.opacity ?? 1)),
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

/// Two open palms on a 24-unit grid, stroked like Material's outlined icons.
class _DuaHandsPainter extends CustomPainter {
  const _DuaHandsPainter(this.color);
  final Color color;

  // The left hand; the right one is its mirror image.
  static final _hand = Path()
    ..moveTo(8.1, 21)
    ..cubicTo(8.1, 18.5, 10.1, 17.5, 10.1, 15)
    ..lineTo(10.1, 5.5)
    ..cubicTo(10.1, 3.8, 7.6, 3.8, 7.6, 5.5)
    ..lineTo(7.6, 10)
    ..cubicTo(7.6, 8.6, 5.2, 8.6, 5.2, 10)
    ..lineTo(5.2, 12.5)
    ..cubicTo(5.2, 11.2, 3, 11.2, 3, 12.5)
    ..lineTo(3, 15.5)
    ..cubicTo(3, 18, 4.6, 19.5, 4.6, 21);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(_hand, paint)
      ..translate(24, 0)
      ..scale(-1, 1)
      ..drawPath(_hand, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_DuaHandsPainter oldDelegate) =>
      oldDelegate.color != color;
}
