import 'package:flutter/material.dart';

import '../../core/theme/iqro_theme.dart';

const mushafPaperColor = Color(0xFFFFFCF7);
const mushafInkColor = Color(0xFF392D20);
const mushafAccentColor = Color(0xFF857154);

// Lightness turned over with the hue kept (an inversion, then half a turn of
// hue), a little softer than black and white.
const _nightScale = .86;
const _nightOffset = 255 * _nightScale + 18;
const _nightMatrix = <double>[
  .574 * _nightScale, -1.430 * _nightScale, -.144 * _nightScale, 0, //
  _nightOffset,
  -.426 * _nightScale, -.430 * _nightScale, -.144 * _nightScale, 0, //
  _nightOffset,
  -.426 * _nightScale, -1.430 * _nightScale, .856 * _nightScale, 0, //
  _nightOffset,
  0, 0, 0, 1, 0,
];

/// The night Mushaf: the page as it is, printed, scanned or set in a colour
/// font, with the paper dark and the ink light. Tajweed colours and the
/// marks of a reader keep their hue.
const mushafNightFilter = ColorFilter.matrix(_nightMatrix);

/// [color] as [mushafNightFilter] shows it.
Color mushafNightColor(Color color) {
  final channels = <double>[color.r * 255, color.g * 255, color.b * 255];
  double channel(int row) {
    var value = _nightMatrix[row * 5 + 4];
    for (var i = 0; i < 3; i++) {
      value += _nightMatrix[row * 5 + i] * channels[i];
    }
    return value.clamp(0, 255) / 255;
  }

  return Color.from(
    alpha: color.a,
    red: channel(0),
    green: channel(1),
    blue: channel(2),
  );
}

/// Shows [child] through [mushafNightFilter] while [night] is on.
class MushafNight extends StatelessWidget {
  const MushafNight({required this.night, required this.child, super.key});

  final bool night;
  final Widget child;

  @override
  Widget build(BuildContext context) => night
      ? ColorFiltered(colorFilter: mushafNightFilter, child: child)
      : child;
}

/// Reflowable Quran text on the same paper as the page reader. Explicit ink
/// and paper colors keep the Arabic readable in both light and dark app themes.
class MushafAyahText extends StatelessWidget {
  const MushafAyahText({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: mushafPaperColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB7A77F)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFD1C4A4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Text(
            text,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: mushafInkColor,
              fontFamily: IqroTheme.arabicFontFamily,
              fontSize: 30,
              fontWeight: FontWeight.normal,
              height: 1.85,
            ),
          ),
        ),
      ),
    );
  }
}
