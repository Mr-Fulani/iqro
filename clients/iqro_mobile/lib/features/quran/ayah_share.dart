import 'package:flutter/painting.dart';

import '../../core/share/content_share.dart';
import '../tajweed/tajweed_models.dart';
import 'foundation_mushaf_page.dart';
import 'quran_repository.dart';

/// An ayah as shared: the surah and its number, the Arabic, the meaning
/// and a link to the ayah on the site. The translator is named only in the
/// message; the picture shows [glyphs], the ayah in the tajweed Mushaf's
/// script, or the plain Arabic without them.
ContentShare ayahContentShare({
  required String locale,
  required String surahName,
  required int surah,
  required int ayah,
  required String arabic,
  required String readInIqro,
  String translation = '',
  String translator = '',
  List<InlineSpan> glyphs = const [],
}) => ContentShare(
  title: '$surahName · $surah:$ayah',
  arabic: arabic,
  arabicGlyphs: glyphs,
  translation: translation,
  note: translation.trim().isEmpty ? '' : translator.trim(),
  url: ayahShareUrl(locale, surah, ayah),
  readInIqro: readInIqro,
);

/// How long sharing waits for the tajweed pages and their fonts.
const ayahShareGlyphsWait = Duration(seconds: 4);

/// The words of an ayah in the coloured QCF V4 Tajweed page fonts of QF
/// Mushaf 19, over every page the ayah spans, as the reader loads them.
/// Empty when a page or its font does not arrive in time: the picture is
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
            page.sourceId != tajweedMushafId ||
            page.rendering['mode'] == 'word-images') {
          throw const FormatException('The page has no tajweed font');
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
              foundationWordSpan(word, TextStyle(fontFamily: family)),
        ];
      }),
    );
    return [for (final words in pages) ...words];
  }

  try {
    return await load().timeout(ayahShareGlyphsWait);
  } on Object {
    return const [];
  }
}
