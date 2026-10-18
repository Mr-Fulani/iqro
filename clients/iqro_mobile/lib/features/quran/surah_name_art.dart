import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/iqro_theme.dart';
import 'truetype_glyph.dart';

/// QUL's surah header font, the source of the Mushaf's surah headings; the
/// same pinned file as the backend's `surah_header.py`. It is loaded from the
/// QUL CDN and cached, never bundled.
const surahHeaderFontUrl =
    'https://static-cdn.tarteel.ai/qul/fonts/surah-names/surah-header/'
    'QCF_SurahHeader_COLOR-Regular.ttf';
const surahHeaderFontSha256 =
    'de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b';
// Glyphs follow .notdef, uni0000, uni0009 and space in surah order.
const _firstSurahGlyphId = 4;

/// The header font, or null while it cannot be loaded or has changed.
final surahHeaderFontProvider = FutureProvider<ByteData?>((ref) async {
  try {
    final file = await ref
        .watch(quranRepositoryProvider)
        .foundationAsset(Uri.parse(surahHeaderFontUrl), surahHeaderFontSha256);
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != surahHeaderFontSha256) return null;
    return ByteData.sublistView(bytes);
  } on Object {
    return null;
  }
});

// In font units: the cartouche's open middle, clear of its border bands and
// end ornaments. Every surah's name lies within it, and nothing else does.
bool _insideCartouche(Rect contour) =>
    contour.width < 3000 &&
    contour.left > 900 &&
    contour.right < 7300 &&
    contour.top > -380 &&
    contour.bottom < 380;

/// The calligraphic «سورة …» of a Mushaf heading, without its cartouche.
GlyphOutline? readSurahNameOutline(ByteData font, int surah) {
  if (surah < 1 || surah > 114) return null;
  return readTrueTypeGlyph(
    font,
    _firstSurahGlyphId + surah - 1,
    keep: _insideCartouche,
  );
}

final surahNameOutlineProvider = Provider.family<GlyphOutline?, int>((
  ref,
  surah,
) {
  final font = ref.watch(surahHeaderFontProvider).valueOrNull;
  if (font == null) return null;
  try {
    return readSurahNameOutline(font, surah);
  } on Object {
    return null;
  }
});

/// A surah's name as the Mushaf prints it, fitted into [width] × [height].
/// Until the source font is available, [fallback] is set in the app's Arabic
/// typeface.
class SurahNameArt extends ConsumerWidget {
  const SurahNameArt({
    required this.surah,
    required this.fallback,
    this.height = 32,
    this.width = 108,
    this.color,
    super.key,
  });

  final int surah;
  final String fallback;
  final double height;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outline = ref.watch(surahNameOutlineProvider(surah));
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      height: height,
      child: outline == null
          ? Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                fallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: IqroTheme.arabicFontFamily,
                  fontSize: height * .6,
                  height: 1.3,
                  color: ink,
                ),
              ),
            )
          : Semantics(
              label: fallback,
              child: CustomPaint(painter: _OutlinePainter(outline, ink)),
            ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.outline, this.color);

  final GlyphOutline outline;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = outline.bounds;
    final scale = (size.width / bounds.width) < (size.height / bounds.height)
        ? size.width / bounds.width
        : size.height / bounds.height;
    canvas
      ..save()
      // Centred vertically, against the end edge like Arabic text.
      ..translate(
        size.width - bounds.width * scale,
        (size.height - bounds.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top)
      ..drawPath(outline.path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.outline != outline || old.color != color;
}
