import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'foundation_mushaf_page.dart';
import 'mushaf_paper.dart';
import 'quran_models.dart';

/// One ayah's words on a page of the selected Mushaf, in the page's own font.
typedef MushafScriptWords = ({
  List<Map<String, Object?>> words,
  String fontFamily,

  /// The font paints its own colours (tajweed) over black letters.
  bool colored,
});

/// The pages of every ayah in the selected Mushaf; null for an edition that
/// has no index of its own (the 604 Madani pages apply).
final mushafVersePagesProvider =
    FutureProvider.autoDispose<Map<String, List<int>>?>((ref) async {
      final repository = ref.watch(selectedMushafRepositoryProvider);
      if (!repository.mushaf.isFoundation) return null;
      final pages = await repository.foundationPageIndex();
      // Kept once loaded; a failure (no network yet) is tried again when a
      // reader next opens.
      ref.keepAlive();
      return pages;
    });

/// A page of the selected Mushaf as text, by `surah:ayah`: the readers draw
/// their ayahs with it. Null for an edition of pictures, which has no font.
/// The page and its font come from the Mushaf's own cache, so a page read or
/// downloaded before needs no network. A loaded page is kept, so an ayah
/// scrolled back to is drawn at once; a failed one is tried again when its
/// ayahs next come on screen.
final mushafPageScriptProvider = FutureProvider.autoDispose
    .family<Map<String, MushafScriptWords>?, int>((ref, number) async {
      final repository = ref.watch(selectedMushafRepositoryProvider);
      if (!repository.mushaf.isFoundation) return null;
      final page = (await repository.mushafPage(number)).foundation;
      if (page == null || page.rendering['mode'] == 'word-images') return null;
      final resources = await loadFoundationPageResources(
        page,
        repository.foundationAsset,
      );
      final family = resources.fontFamily;
      resources.dispose();
      if (family == null) return null;
      final ayahs = <String, MushafScriptWords>{};
      for (final word in page.words) {
        final key = word['verse_key']?.toString();
        if (key == null) continue;
        ayahs
            .putIfAbsent(
              key,
              () => (
                words: <Map<String, Object?>>[],
                fontFamily: family,
                colored: page.rendering['color_format'] != null,
              ),
            )
            .words
            .add(word);
      }
      ref.keepAlive();
      return ayahs;
    });

/// The first page of an ayah in the selected Mushaf, else its Madani page.
int? mushafPageOfAyah(
  Map<String, List<int>>? versePages,
  int surah,
  int ayah,
  List<int> madaniPages,
) => versePages?['$surah:$ayah']?.firstOrNull ?? madaniPages.firstOrNull;

/// An ayah as the selected Mushaf writes it: a span for each word, and the
/// ayah's end sign.
class MushafAyahScript {
  const MushafAyahScript({
    required this.words,
    required this.marker,
    required this.colored,
  });

  final List<TextSpan> words;
  final TextSpan? marker;
  final bool colored;

  /// The whole ayah in one span, its words a space apart.
  TextSpan span(TextStyle? style) => TextSpan(
    style: style,
    children: <InlineSpan>[
      for (final (index, word) in words.indexed) ...<InlineSpan>[
        if (index > 0) const TextSpan(text: ' '),
        word,
      ],
      if (marker != null) ...<InlineSpan>[const TextSpan(text: ' '), ?marker],
    ],
  );
}

/// Watches the pages of an ayah. Null while they load, when the edition has
/// no font, or when its words are not the [wordCount] words the reader
/// counts: the plain text is drawn then, and word selection stays right.
MushafAyahScript? watchMushafAyahScript(
  WidgetRef ref, {
  required int surah,
  required int ayah,
  required int wordCount,
}) {
  final key = '$surah:$ayah';
  final pages = ref.watch(mushafVersePagesProvider).valueOrNull?[key];
  if (pages == null) return null;
  final words = <TextSpan>[];
  TextSpan? marker;
  var colored = false;
  for (final page in pages) {
    final script = ref.watch(mushafPageScriptProvider(page)).valueOrNull?[key];
    if (script == null) return null;
    colored = colored || script.colored;
    for (final word in script.words) {
      final span = foundationWordSpan(
        word,
        TextStyle(fontFamily: script.fontFamily),
      );
      if (word['char_type_name'] == 'word') {
        words.add(span);
      } else if (word['char_type_name'] == 'end') {
        marker = span;
      }
    }
  }
  if (words.length != wordCount) return null;
  return MushafAyahScript(words: words, marker: marker, colored: colored);
}

/// How long a reader holds its text back for the Mushaf's script of its
/// first screen. A page on the phone comes well within it; one that needs a
/// slow network does not, and the text opens in the plain font.
const mushafScriptWait = Duration(milliseconds: 600);

/// Whether the script of the first screen of a reader opening at [ayah] has
/// loaded, or will not: the screen is then drawn once, in the font it keeps.
/// It looks at the ayah's pages and the page after, which the screen may
/// run on to.
bool watchMushafScriptSettled(WidgetRef ref, List<QuranAyah> items, int ayah) {
  final versePages = ref.watch(mushafVersePagesProvider);
  if (versePages.isLoading) return false;
  final pages = <int>{};
  for (final item in items) {
    if (item.number < ayah) continue;
    pages.addAll(
      versePages.valueOrNull?['${item.surahNumber}:${item.number}'] ??
          const <int>[],
    );
    if (pages.length > 1) break;
  }
  // Every page is asked for at once, not one after another.
  return pages
      .map((page) => ref.watch(mushafPageScriptProvider(page)).isLoading)
      .toList()
      .every((loading) => !loading);
}

/// The end of a Mushaf page between two ayahs of a reader: a thin line with
/// the number of the page that ended.
class ReaderPageBreak extends StatelessWidget {
  const ReaderPageBreak({required this.label, this.paper = false, super.key});

  final String label;

  /// On the Mushaf paper of the plain text, not on the app's surface.
  final bool paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = paper
        ? mushafAccentColor.withValues(alpha: .45)
        : theme.colorScheme.outlineVariant;
    final line = Expanded(
      child: Divider(height: 1, thickness: 1, color: color),
    );
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            line,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: paper
                      ? mushafAccentColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            line,
          ],
        ),
      ),
    );
  }
}
