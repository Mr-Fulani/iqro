import 'package:flutter/painting.dart';

import '../../core/share/content_share.dart';
import 'foundation_mushaf_page.dart';
import 'quran_repository.dart';

/// An ayah as shared: the surah and its number, the Arabic, the meaning
/// and a link to the ayah on the site, without the translator's name. The
/// picture shows [glyphs], the ayah in the selected Mushaf's script, or the
/// plain Arabic with its end sign without them.
ContentShare ayahContentShare({
  required String locale,
  required String surahName,
  required int surah,
  required int ayah,
  required String arabic,
  required String readInIqro,
  String translation = '',
  List<InlineSpan> glyphs = const [],
}) => ContentShare(
  title: '$surahName · $surah:$ayah',
  arabic: arabic,
  arabicGlyphs: glyphs,
  arabicEnd: '\u06dd${_arabicDigits(ayah)}',
  cardReference: '$surahName · $surah:$ayah',
  translation: translation,
  url: ayahShareUrl(locale, surah, ayah),
  readInIqro: readInIqro,
);

String _arabicDigits(int number) => number
    .toString()
    .split('')
    .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
    .join();

/// How long sharing waits for the Mushaf's pages and their fonts.
const ayahShareGlyphsWait = Duration(seconds: 4);

/// The words of an ayah in the page fonts of the Mushaf [repository] reads,
/// over every page the ayah spans, as the reader loads them; the ayah's end
/// sign stays with the last word. Empty when a page or its font does not
/// arrive in time, for a Mushaf of pictures and for one whose font paints its
/// own colours (tajweed), which cannot take the card's ink: the picture is
/// then drawn in the plain script.
Future<List<InlineSpan>> ayahShareGlyphs(
  QuranRepository repository,
  int surah,
  int ayah,
) async {
  final verseKey = '$surah:$ayah';
  Future<List<InlineSpan>> load() async {
    final numbers = (await repository.foundationPageIndex())[verseKey];
    if (numbers == null) throw StateError('No QF page for $verseKey');
    final pages = await Future.wait(
      numbers.map((number) async {
        final page = (await repository.mushafPage(number)).foundation;
        if (page == null ||
            page.rendering['mode'] == 'word-images' ||
            page.rendering['color_format'] != null) {
          throw const FormatException('The page has no plain font');
        }
        final resources = await loadFoundationPageResources(
          page,
          repository.foundationAsset,
        );
        final family = resources.fontFamily;
        resources.dispose();
        if (family == null) throw const FormatException('No page font');
        return [
          for (final word in page.words)
            if (word['verse_key'] == verseKey)
              (
                end: word['char_type_name'] == 'end',
                span: foundationWordSpan(word, TextStyle(fontFamily: family)),
              ),
        ];
      }),
    );
    final words = [for (final page in pages) ...page];
    final spans = <InlineSpan>[
      for (final word in words)
        if (!word.end) word.span,
    ];
    final end = words.where((word) => word.end).firstOrNull?.span;
    if (end != null && spans.isNotEmpty) {
      spans.last = TextSpan(
        children: [
          spans.last,
          const TextSpan(text: ' '),
          end,
        ],
      );
    }
    return spans;
  }

  try {
    return await load().timeout(ayahShareGlyphsWait);
  } on Object {
    return const [];
  }
}
