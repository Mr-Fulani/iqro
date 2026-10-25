import 'audio_models.dart';
import 'reciter_catalog.dart';

/// The Audio tab's queue, as docs/audio-listening-queue.md sets it out and the
/// site follows (services/web/lib/listening-queue.ts): which surah plays
/// after, before and instead of the current one. Pure rules, unit-tested apart
/// from the player.

/// What happens when a surah ends by itself. Saved by [Enum.name].
enum ListeningQueueMode { stop, next, loop }

const defaultListeningQueueMode = ListeningQueueMode.next;
const quranSurahCount = 114;

final List<int> _allSurahs = List<int>.unmodifiable(
  List<int>.generate(quranSurahCount, (index) => index + 1),
);

ListeningQueueMode? listeningQueueModeNamed(Object? name) {
  for (final mode in ListeningQueueMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

/// The surahs a recording holds, in order; an empty list stands for the whole
/// Quran (catalogs from before the list).
List<int> heldSurahs(Iterable<int>? surahNumbers) {
  final held =
      (surahNumbers ?? const <int>[])
          .where((surah) => surah >= 1 && surah <= quranSurahCount)
          .toSet()
          .toList()
        ..sort();
  return held.isEmpty ? _allSurahs : List<int>.unmodifiable(held);
}

/// An unknown recitation plays as the whole Quran, as the buttons always did.
List<int> recitationHeldSurahs(Recitation? recitation) =>
    heldSurahs(recitation?.coverage?.surahNumbers);

/// The nearest held surah in [direction]; with [wrap], past either end to the
/// other.
int? stepHeldSurah(
  List<int> held,
  int current,
  int direction, {
  required bool wrap,
}) {
  if (held.isEmpty) return null;
  if (direction > 0) {
    for (final surah in held) {
      if (surah > current) return surah;
    }
    return wrap ? held.first : null;
  }
  for (final surah in held.reversed) {
    if (surah < current) return surah;
  }
  return wrap ? held.last : null;
}

/// What plays once the current surah ends by itself; null ends playback.
int? surahAfter(List<int> held, int current, ListeningQueueMode mode) {
  if (mode == ListeningQueueMode.stop) return null;
  return stepHeldSurah(held, current, 1, wrap: mode == ListeningQueueMode.loop);
}

/// The previous and next buttons: they cross the ends only in the loop mode.
int? adjacentQueueSurah(
  List<int> held,
  int? current,
  int direction,
  ListeningQueueMode mode,
) {
  if (current == null) return null;
  return stepHeldSurah(
    held,
    current,
    direction,
    wrap: mode == ListeningQueueMode.loop,
  );
}

/// Where a switch to another recording lands: the same surah, the next held
/// one, or the last.
int? nearestHeldSurah(List<int> held, int wanted) {
  if (held.isEmpty) return null;
  if (held.contains(wanted)) return wanted;
  for (final surah in held) {
    if (surah > wanted) return surah;
  }
  return held.last;
}

/// How the players title a surah: "2 · Аль-Бакара", or "Сура 2" while no
/// name is known. [surahWord] is the app's word for a surah.
String surahDisplayTitle(int surah, String? name, {required String surahWord}) {
  final known = name?.trim() ?? '';
  if (known.isEmpty || known == '$surahWord $surah') return '$surahWord $surah';
  return '$surah · $known';
}

/// "Play the whole Quran": the stop mode would end after one surah, so it
/// moves on.
ListeningQueueMode wholeQuranMode(ListeningQueueMode mode) =>
    mode == ListeningQueueMode.stop ? ListeningQueueMode.next : mode;

sealed class ListeningQueueRow {
  const ListeningQueueRow();
}

final class ListeningQueueSurahRow extends ListeningQueueRow {
  const ListeningQueueSurahRow(this.surah);

  final int surah;

  @override
  bool operator ==(Object other) =>
      other is ListeningQueueSurahRow && other.surah == surah;

  @override
  int get hashCode => surah.hashCode;

  @override
  String toString() => 'surah $surah';
}

/// A run of surahs the recording does not hold.
final class ListeningQueueGapRow extends ListeningQueueRow {
  const ListeningQueueGapRow(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is ListeningQueueGapRow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'gap $from–$to';
}

/// The queue list: held surahs, with each run of missing ones folded into one
/// row.
List<ListeningQueueRow> listeningQueueRows(List<int> held) {
  final rows = <ListeningQueueRow>[];
  var expected = 1;
  for (final surah in held) {
    if (surah > expected) rows.add(ListeningQueueGapRow(expected, surah - 1));
    rows.add(ListeningQueueSurahRow(surah));
    expected = surah + 1;
  }
  if (held.isNotEmpty && expected <= quranSurahCount) {
    rows.add(ListeningQueueGapRow(expected, quranSurahCount));
  }
  return rows;
}

/// The reciter's recordings the player can switch between: one listening
/// recitation per style, the current one kept, as the Audio tab picks them.
List<Recitation> listeningVariants(
  ReciterPerson person,
  Iterable<Recitation> recitations, {
  String? currentId,
}) {
  final own = recitationsForPerson(person, recitations)
      .where((item) => item.supports(AudioRecitationRole.listening))
      .toList(growable: false);
  return <Recitation>[
    for (final style in orderedRecitationStyles(own))
      ?recitationForPersonStyle(person, own, style, preferredId: currentId),
  ];
}
