import 'package:flutter/material.dart';

/// Uses the approved IQRO seal wherever an open-book icon was displayed.
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
    if (icon != Icons.menu_book &&
        icon != Icons.menu_book_outlined &&
        icon != Icons.menu_book_rounded &&
        icon != Icons.auto_stories_outlined) {
      return super.build(context);
    }
    final theme = IconTheme.of(context);
    final baseSize = size ?? theme.size ?? kDefaultFontSize;
    final extent = (applyTextScaling ?? theme.applyTextScaling ?? false)
        ? MediaQuery.textScalerOf(context).scale(baseSize)
        : baseSize;
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
