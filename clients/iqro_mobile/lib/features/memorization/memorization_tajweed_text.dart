import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/theme/iqro_theme.dart';
import '../quran/foundation_mushaf_page.dart';
import '../quran/mushaf_edition.dart';
import '../quran/quran_models.dart';
import '../tajweed/tajweed_models.dart';
import '../tajweed/tajweed_sheet.dart';

typedef MemorizationRange = ({int surah, int start, int end});

/// A word of a practice ayah in its QF Mushaf 19 page font.
typedef MemorizationGlyph = ({
  Map<String, Object?> word,
  String fontFamily,

  /// `position_in_verse`; null for the ayah-end marker.
  int? position,
});

class MemorizationTajweedText {
  const MemorizationTajweedText({required this.words, required this.pages});

  /// The glyphs of each practice ayah, by ayah number.
  final Map<int, List<MemorizationGlyph>> words;

  /// The QF Mushaf 19 page of each practice ayah, for its tajweed.
  final Map<int, int> pages;
}

/// The colour-coded tajweed text of a practice range, as on the web. Fails
/// when a page or its font is unavailable; the plain text is shown instead.
final memorizationTajweedTextProvider = FutureProvider.autoDispose
    .family<MemorizationTajweedText, MemorizationRange>((ref, range) async {
      final repository = ref.watch(
        mushafRepositoryProvider(MushafIdentity.defaultEdition),
      );
      final index = await repository.foundationPageIndex();
      final pages = <int, int>{
        for (var ayah = range.start; ayah <= range.end; ayah++)
          ayah:
              index['${range.surah}:$ayah']?.firstOrNull ??
              (throw StateError('No QF page for ${range.surah}:$ayah')),
      };
      final words = <int, List<MemorizationGlyph>>{};
      await Future.wait(
        pages.values.toSet().map((number) async {
          final page = (await repository.mushafPage(number)).foundation;
          if (page == null || page.rendering['mode'] == 'word-images') {
            throw const FormatException('The page has no font');
          }
          final resources = await loadFoundationPageResources(
            page,
            repository.foundationAsset,
          );
          final family = resources.fontFamily;
          resources.dispose();
          if (family == null) throw const FormatException('No page font');
          for (final word in page.words) {
            final key = word['verse_key']?.toString().split(':');
            final ayah = int.tryParse(key?.last ?? '');
            if (key?.first != '${range.surah}' || pages[ayah] != number) {
              continue;
            }
            words.putIfAbsent(ayah!, () => []).add((
              word: word,
              fontFamily: family,
              position: word['char_type_name'] == 'word'
                  ? (word['position_in_verse'] as num?)?.toInt()
                  : null,
            ));
          }
        }),
      );
      return MemorizationTajweedText(words: words, pages: pages);
    });

/// A practice ayah in the coloured QF Mushaf 19 glyphs, word by word, with the
/// legend of its tajweed rules. Coloured words open their tajweed card.
class MemorizationTajweedAyah extends ConsumerWidget {
  const MemorizationTajweedAyah({
    required this.ayah,
    required this.range,
    required this.fallback,
    this.recitationId,
    super.key,
  });

  final QuranAyah ayah;
  final MemorizationRange range;

  /// The plain Uthmani text, while the glyphs load or when they cannot.
  final Widget fallback;

  /// The plan's reciter, for words played from a tajweed card.
  final String? recitationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(memorizationTajweedTextProvider(range)).valueOrNull;
    final glyphs = text?.words[ayah.number];
    final page = text?.pages[ayah.number];
    if (glyphs == null || glyphs.isEmpty || page == null) return fallback;
    final reference = ref.watch(tajweedRulesProvider).valueOrNull;
    final tajweed = reference == null
        ? null
        : ref
              .watch(tajweedPageProvider(page))
              .valueOrNull
              ?.ayah('${ayah.surahNumber}:${ayah.number}');
    final recitation = recitationId;
    void open(TajweedSelection selection) => showTajweedSheet(
      context,
      reference: reference!,
      ayahs: [tajweed!],
      wholePage: false,
      selection: selection,
      recitation: recitation == null ? null : () async => recitation,
    );
    final style = TextStyle(
      fontSize: 30,
      height: 1.8,
      color: IqroTheme.arabicInk(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          container: true,
          label: ayah.textUthmani,
          child: Wrap(
            textDirection: TextDirection.rtl,
            spacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final glyph in glyphs)
                _glyph(
                  glyph,
                  style.copyWith(fontFamily: glyph.fontFamily),
                  glyph.position == null
                      ? null
                      : tajweed?.word(glyph.position!),
                  open,
                ),
            ],
          ),
        ),
        if (tajweed != null && tajweed.rules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TajweedLegend(
              title: context.l10n.tajweedLegendAyah,
              rules: reference!.present(tajweed.rules),
              onSelected: (code) => open(TajweedRuleSelection(code)),
            ),
          ),
      ],
    );
  }

  Widget _glyph(
    MemorizationGlyph glyph,
    TextStyle style,
    TajweedWord? word,
    void Function(TajweedSelection selection) open,
  ) {
    final text = ExcludeSemantics(
      child: Text.rich(
        foundationWordSpan(glyph.word, style),
        textDirection: TextDirection.rtl,
      ),
    );
    if (word == null || word.rules.isEmpty) return text;
    return Semantics(
      button: true,
      label: word.text,
      child: InkWell(
        key: ValueKey('tajweed-word-${ayah.number}-${word.position}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => open(
          TajweedWordSelection(
            '${ayah.surahNumber}:${ayah.number}',
            word.position,
          ),
        ),
        child: text,
      ),
    );
  }
}
