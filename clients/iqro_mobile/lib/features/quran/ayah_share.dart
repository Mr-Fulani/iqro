import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/share/content_share.dart';
import 'foundation_mushaf_page.dart';
import 'quran_models.dart';
import 'quran_repository.dart';
import 'word_range.dart';

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

/// An ayah's words in the page fonts of a Mushaf, by `position_in_verse`,
/// and its end sign.
typedef AyahShareScript = ({List<InlineSpan> words, InlineSpan? end});

/// The words of an ayah in the page fonts of the Mushaf [repository] reads,
/// over every page the ayah spans, as the reader loads them. Null when a
/// page or its font does not arrive in time, for a Mushaf of pictures and
/// for one whose font paints its own colours (tajweed), which cannot take
/// the card's ink: the picture is then drawn in the plain script.
Future<AyahShareScript?> ayahShareScript(
  QuranRepository repository,
  int surah,
  int ayah,
) async {
  final verseKey = '$surah:$ayah';
  Future<AyahShareScript> load() async {
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
    return (
      words: <InlineSpan>[
        for (final word in words)
          if (!word.end) word.span,
      ],
      end: words.where((word) => word.end).firstOrNull?.span,
    );
  }

  try {
    return await load().timeout(ayahShareGlyphsWait);
  } on Object {
    return null;
  }
}

// The end sign stays with the last word.
InlineSpan _withEnd(InlineSpan word, InlineSpan? end) => end == null
    ? word
    : TextSpan(
        children: [
          word,
          const TextSpan(text: ' '),
          end,
        ],
      );

/// The whole ayah for the picture: its words in the Mushaf's fonts, the end
/// sign with the last. Empty when [ayahShareScript] has none.
Future<List<InlineSpan>> ayahShareGlyphs(
  QuranRepository repository,
  int surah,
  int ayah,
) async {
  final script = await ayahShareScript(repository, surah, ayah);
  if (script == null || script.words.isEmpty) return const [];
  return [
    ...script.words.take(script.words.length - 1),
    _withEnd(script.words.last, script.end),
  ];
}

/// The selected words as shared: from one word to several ayahs of a surah.
/// A part of an ayah has no meaning under it, as translations are of whole
/// ayahs, and says so in its reference («из аята 2:286»); an ayah's end sign
/// is drawn only after its last word. Whole ayahs carry their meanings.
/// [scripts] holds the ayahs in the Mushaf's fonts; without one of them, or
/// when its words are not the words the reader counts, the plain script is
/// drawn.
ContentShare wordRangeContentShare({
  required String locale,
  required String surahName,
  required QuranWordRange range,
  required List<QuranAyah> ayahs,
  required String readInIqro,
  required String Function(String reference, {required bool several}) partOf,
  Map<int, AyahShareScript> scripts = const {},
  Map<int, String> translations = const {},
}) {
  final surah = range.start.surah;
  final selected = [
    for (final ayah in ayahs)
      if (ayah.number >= range.start.ayah && ayah.number <= range.end.ayah)
        (ayah: ayah, words: ayahWords(ayah)),
  ];
  final inScript = selected.every(
    (item) => scripts[item.ayah.number]?.words.length == item.words.length,
  );
  final plain = <String>[];
  final glyphs = <InlineSpan>[];
  var whole = true;
  for (final (:ayah, :words) in selected) {
    final from = ayah.number == range.start.ayah ? range.start.position : 1;
    final to = ayah.number == range.end.ayah
        ? range.end.position.clamp(1, words.length)
        : words.length;
    if (from > 1 || to < words.length) whole = false;
    final script = inScript ? scripts[ayah.number] : null;
    for (var position = from; position <= to; position += 1) {
      plain.add(words[position - 1]);
      final word =
          script?.words[position - 1] ?? TextSpan(text: words[position - 1]);
      glyphs.add(
        position < words.length
            ? word
            : _withEnd(
                word,
                script != null
                    ? script.end
                    : TextSpan(text: '۝${_arabicDigits(ayah.number)}'),
              ),
      );
    }
  }
  final several = range.start.ayah != range.end.ayah;
  final reference = several
      ? '$surah:${range.start.ayah}–${range.end.ayah}'
      : '$surah:${range.start.ayah}';
  final title = whole
      ? '$surahName · $reference'
      : '$surahName · ${partOf(reference, several: several)}';
  final meanings = [
    for (final item in selected) translations[item.ayah.number]?.trim() ?? '',
  ];
  return ContentShare(
    title: title,
    arabic: plain.join(' '),
    arabicGlyphs: glyphs,
    cardReference: title,
    translation: whole && meanings.every((meaning) => meaning.isNotEmpty)
        ? meanings.join(' ')
        : '',
    url: ayahShareUrl(locale, surah, range.start.ayah),
    readInIqro: readInIqro,
  );
}

/// Opens the share sheet for the selected words: loads the surah, the
/// selected Mushaf's script of its ayahs and, for whole ayahs, their
/// meanings in the reader's translation.
Future<void> shareWordRange(
  BuildContext context,
  WidgetRef ref,
  QuranWordRange range,
) async {
  final locale = Localizations.localeOf(context).languageCode;
  final l10n = context.l10n;
  final quran = ref.read(quranRepositoryProvider);
  final mushaf = ref.read(selectedMushafRepositoryProvider);
  final analytics = ref.read(analyticsProvider.notifier);
  final surah = range.start.surah;
  final surahName =
      ref
          .read(quranCatalogProvider)
          .valueOrNull
          ?.surahs
          .where((item) => item.number == surah)
          .firstOrNull
          ?.nameFor(locale) ??
      '${l10n.surah} $surah';
  final List<QuranAyah> ayahs;
  try {
    ayahs = await quran.ayahs(surah);
  } on Object {
    return;
  }
  final numbers = [
    for (var ayah = range.start.ayah; ayah <= range.end.ayah; ayah += 1) ayah,
  ];
  final scripts = await Future.wait(
    numbers.map((ayah) => ayahShareScript(mushaf, surah, ayah)),
  );
  final translations = <int, String>{};
  try {
    final editions = await quran.translationEditions(locale);
    final preferred = ref
        .read(appPreferencesProvider)
        .preferredTranslationSourceId;
    final source =
        editions.where((item) => item.sourceId == preferred).firstOrNull ??
        editions.firstOrNull;
    if (source != null) {
      for (final item in await quran.translations(
        sourceId: source.sourceId,
        surah: surah,
      )) {
        translations[item.ayah] = item.text;
      }
    }
  } on Object {
    // Whole ayahs go without their meanings.
  }
  if (!context.mounted) return;
  final shared = await shareContent(
    context,
    wordRangeContentShare(
      locale: locale,
      surahName: surahName,
      range: range,
      ayahs: ayahs,
      readInIqro: l10n.shareReadInIqro,
      partOf: (reference, {required several}) => several
          ? l10n.shareCardFromAyahs(reference)
          : l10n.shareCardFromAyah(reference),
      scripts: {
        for (final (index, script) in scripts.indexed) numbers[index]: ?script,
      },
      translations: translations,
    ),
  );
  if (shared) {
    analytics.track(AnalyticsEvent.share, const {
      'content_type': 'ayah',
      'method': 'native',
    });
  }
}
