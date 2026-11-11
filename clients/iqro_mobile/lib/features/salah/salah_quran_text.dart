import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/arabic_digits.dart';
import '../dua/dua_arabic.dart';
import '../quran/mushaf_paper.dart';
import '../quran/mushaf_script.dart';
import '../quran/word_range.dart';
import 'salah_models.dart';

/// One ayah of a formula taken from the Quran.
typedef SalahQuranAyah = ({
  int number,

  /// The basmala written before the first ayah of most surahs.
  String? opening,
  String text,
});

final _ayahEnd = RegExp(r'\s*﴿[٠-٩]+﴾\s*');

/// The ayahs of a formula taken from the Quran. The course sends them as one
/// line, each ayah closed by its number in ﴿ ﴾. Null for any other formula,
/// and for a text that is not the ayahs its source names.
List<SalahQuranAyah>? salahQuranAyahs(SalahFormula formula) {
  final SalahFormulaSource(:kind, :surah, :ayahFrom, :ayahTo) = formula.source;
  if (kind != 'quran' || surah == null || ayahFrom == null || ayahTo == null) {
    return null;
  }
  final texts = formula.arabic.split(_ayahEnd);
  if (texts.length != ayahTo - ayahFrom + 2 || texts.removeLast().isNotEmpty) {
    return null;
  }
  return <SalahQuranAyah>[
    for (final (index, text) in texts.indexed)
      if (index == 0 && ayahFrom == 1 && surah != 1 && surah != 9)
        _withOpening(text)
      else
        (number: ayahFrom + index, opening: null, text: text.trim()),
  ];
}

SalahQuranAyah _withOpening(String text) {
  final parts = splitDuaArabic(text);
  return (
    number: 1,
    opening: parts.where((part) => part.opening).firstOrNull?.text,
    text: parts
        .where((part) => !part.opening)
        .map((part) => part.text)
        .join(' '),
  );
}

/// How long the ayahs are held back for the script of the selected Mushaf,
/// so they are drawn once, in the font they keep. As in the Quran readers.
const _scriptWait = Duration(seconds: 1);

/// The ayahs of a formula as the Quran readers draw them: each ayah on its
/// own lines, in the script of the selected Mushaf and with its end sign;
/// in the plain Quran font when the Mushaf has no font or is not loaded.
class SalahQuranText extends ConsumerStatefulWidget {
  const SalahQuranText({
    required this.surah,
    required this.ayahs,
    required this.style,
    super.key,
  });

  final int surah;
  final List<SalahQuranAyah> ayahs;
  final TextStyle? style;

  @override
  ConsumerState<SalahQuranText> createState() => _SalahQuranTextState();
}

class _SalahQuranTextState extends ConsumerState<SalahQuranText> {
  late final Timer _wait;
  var _waited = false;

  @override
  void initState() {
    super.initState();
    _wait = Timer(_scriptWait, () => setState(() => _waited = true));
  }

  @override
  void dispose() {
    _wait.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versePages = ref.watch(mushafVersePagesProvider);
    var loading = versePages.isLoading;
    final scripts = <MushafAyahScript?>[];
    for (final ayah in widget.ayahs) {
      final key = '${widget.surah}:${ayah.number}';
      for (final page in versePages.valueOrNull?[key] ?? const <int>[]) {
        if (ref.watch(mushafPageScriptProvider(page)).isLoading) loading = true;
      }
      scripts.add(
        watchMushafAyahScript(
          ref,
          surah: widget.surah,
          ayah: ayah.number,
          wordCount: quranWords(ayah.text).length,
        ),
      );
    }
    // A Mushaf with tajweed paints its colours over dark letters: in the
    // dark theme they get the Mushaf's paper under them, as in the readers.
    final onPaper =
        theme.brightness == Brightness.dark &&
        scripts.any((script) => script?.colored ?? false);
    final style = onPaper
        ? widget.style?.copyWith(color: mushafInkColor)
        : widget.style;
    final opening = widget.ayahs.first.opening;
    final ayahs = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, ayah) in widget.ayahs.indexed)
          Text.rich(
            scripts[index] == null
                ? TextSpan(
                    text: '${ayah.text} ﴿${arabicIndicDigits(ayah.number)}﴾',
                  )
                : TextSpan(
                    children: <InlineSpan>[
                      for (final (word, span)
                          in scripts[index]!.words.indexed) ...<InlineSpan>[
                        if (word > 0) const TextSpan(text: ' '),
                        span,
                      ],
                      // A no-break space keeps the sign with the last word.
                      const TextSpan(text: ' '),
                      ?scripts[index]!.marker,
                    ],
                  ),
            key: ValueKey('salah-ayah-${widget.surah}-${ayah.number}'),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: style,
          ),
      ],
    );
    return Opacity(
      opacity: loading && !_waited ? 0 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (opening != null) ...<Widget>[
            Text(
              opening,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: widget.style?.copyWith(
                fontSize: (widget.style?.fontSize ?? 28) * .78,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (onPaper)
            DecoratedBox(
              decoration: BoxDecoration(
                color: mushafPaperColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: ayahs,
              ),
            )
          else
            ayahs,
        ],
      ),
    );
  }
}
