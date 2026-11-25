import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';

/// A stop on a word before which a nun or a tanwin is merged, hidden or
/// turned (idgham, ikhfa, iqlab): the word stopped on is read by the rules
/// of a stop, the next one is begun plainly, and neither is a mistake.
/// Read on, the same places are asked for as written. The ayahs are those
/// of the app's own table of expected sounds.

const _mim = 24;
const _nun = 25;
const _ikhfa = 39;
const _iqlab = 40;

late final List<String> _symbols;
late final Map<String, Object?> _surahs;

ExpectedAyah _ayah(int surah, int ayah) =>
    ExpectedAyah.fromJson((_surahs['$surah']! as List)[ayah - 1], _symbols)!;

/// The sounds of [ayah] as read with a stop after each of the words
/// [stops]; with [clear], the hidden or turned nun at the end of that word
/// is said as a plain one.
List<int> _reading(
  ExpectedAyah ayah, {
  Set<int> stops = const {},
  int? clear,
  int? short,
}) {
  final sounds = <int>[];
  for (final (word, (start, end)) in ayah.spans.indexed) {
    // The sounds a word has only when begun after a stop are its first
    // ones; those of its ending are its last.
    var head = start;
    while (head < end && ayah.loose.contains(head)) {
      head += 1;
    }
    for (var i = start; i < end; i++) {
      final added = ayah.added.contains(i);
      final loose = ayah.loose.contains(i);
      final stopped = i < head
          ? stops.contains(word - 1)
          : stops.contains(word);
      // Loose and the ayah's own: said only when the reading goes on.
      if (loose && added != stopped) continue;
      var sound = ayah.sounds[i];
      if (word == clear && (sound == _ikhfa || sound == _iqlab)) sound = _nun;
      // A sound held is said once.
      if (word == short && i > start && ayah.sounds[i - 1] == sound) continue;
      sounds.add(sound);
    }
    if (stops.contains(word)) sounds.addAll(const <int>[0, 0, 0, 0]);
  }
  return <int>[...sounds, 0, 0, 0, 0];
}

/// What the follower makes of [sounds], each on one frame with four of
/// silence after it, fed ten frames at a time.
({List<FollowMiss> misses, List<FollowHeld> held, int next}) _follow(
  ExpectedAyah ayah,
  List<int> sounds,
) {
  final core = RecitationFollowCore(RecitationPassage(<ExpectedAyah>[ayah]));
  final total = sounds.length * 5;
  final lp = Float32List(total * recitationClasses)
    ..fillRange(0, total * recitationClasses, -20);
  for (var t = 0; t < total; t++) {
    lp[t * recitationClasses + (t % 5 == 0 ? sounds[t ~/ 5] : 0)] = -.01;
  }
  final misses = <FollowMiss>[];
  final held = <FollowHeld>[];
  for (var end = 10; end <= total + 40; end += 10) {
    final to = end > total ? total : end;
    final from = to > 250 ? to - 250 : 0;
    final events = core.step(
      Float32List.sublistView(
        lp,
        from * recitationClasses,
        to * recitationClasses,
      ),
      to - from,
      from,
    );
    misses.addAll(events.whereType<FollowMiss>());
    held.addAll(events.whereType<FollowHeld>());
  }
  return (misses: misses, held: held, next: core.next);
}

void main() {
  setUpAll(() {
    final table =
        jsonDecode(
              File('assets/recitation_model/expected.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    _symbols = (table['symbols']! as List).cast<String>();
    _surahs = table['surahs']! as Map<String, Object?>;
  });

  // surah, ayah, the word stopped on, what follows it.
  const merged = <(int, int, int, String)>[
    (67, 3, 4, 'tanwin before mim: "tibaqan ma"'),
    (2, 5, 2, 'tanwin before mim: "hudan min"'),
    (2, 48, 5, 'nun before nun: "an nafsin"'),
    (2, 25, 29, 'tanwin before mim: "azwajun mutahharah"'),
    (2, 10, 1, 'mim before mim: "qulubihim marad"'),
  ];
  const others = <(int, int, int, String)>[
    (2, 8, 2, 'nun before ya: "man yaqulu"'),
    (2, 7, 8, 'tanwin before waw: "ghishawatun walahum"'),
    (2, 2, 5, 'tanwin before lam: "hudan lilmuttaqin"'),
    (2, 5, 3, 'nun before ra: "min rabbihim"'),
    (2, 10, 8, 'tanwin before ba (iqlab): "alimun bima"'),
    (2, 27, 4, 'nun before ba (iqlab): "min ba\'di"'),
    (67, 3, 3, 'tanwin before ta (ikhfa): "samawatin tibaqan"'),
    (2, 10, 2, 'tanwin before fa (ikhfa): "maradun fazadahum"'),
    (2, 25, 9, 'nun before ta (ikhfa): "min tahtiha"'),
  ];

  group('a stop on the word', () {
    for (final (surah, number, word, name) in <(int, int, int, String)>[
      ...merged,
      ...others,
    ]) {
      test('$surah:$number, $name, is no mistake', () {
        final ayah = _ayah(surah, number);
        final seen = _follow(ayah, _reading(ayah, stops: <int>{word}));
        expect(seen.misses, isEmpty);
        expect(seen.next, ayah.spans.length);
        // No ghunnah is looked for in the word begun after the stop.
        final first = RecitationPassage(<ExpectedAyah>[
          ayah,
        ]).wordStart[word + 1];
        expect(seen.held.where((h) => h.place.first == first), isEmpty);
      });
    }
  });

  group('read on', () {
    for (final (surah, number, word, name) in merged) {
      test('$surah:$number, $name, has its ghunnah looked at: held, and '
          'said once', () {
        final ayah = _ayah(surah, number);
        final passage = RecitationPassage(<ExpectedAyah>[ayah]);
        final first = passage.wordStart[word + 1];
        final seen = _follow(ayah, _reading(ayah));
        expect(seen.misses, isEmpty);
        final full = seen.held.singleWhere((h) => h.place.first == first);
        expect(full.place.kind, lessThanOrEqualTo(1));
        expect(full.toFrame - full.fromFrame, 20);
        // Said once, with no stop before it: the ghunnah left out, which
        // the place is stopped for.
        final less = _follow(ayah, _reading(ayah, short: word + 1));
        final once = less.held.singleWhere((h) => h.place.first == first);
        expect(once.toFrame - once.fromFrame, 5);
      });
    }

    for (final (surah, number, word, name) in others.where(
      (place) => place.$4.contains('ikhfa') || place.$4.contains('iqlab'),
    )) {
      test('$surah:$number, $name: a plain nun is a mistake', () {
        final ayah = _ayah(surah, number);
        expect(_follow(ayah, _reading(ayah)).misses, isEmpty);
        final seen = _follow(ayah, _reading(ayah, clear: word));
        // (What is read after the place has stopped is not looked at.)
        expect(seen.misses.first.word, word);
        expect(seen.misses.first.why, FollowWhy.another);
        expect(seen.misses.first.heard, _nun);
      });
    }
  });

  test('the first word read, begun with a merged letter, is not asked for '
      'its ghunnah: nothing was read on from', () {
    final ayah = _ayah(67, 3);
    final core = RecitationFollowCore(RecitationPassage(<ExpectedAyah>[ayah]))
      ..moveTo(5);
    // "ma tara", the mim said once.
    final sounds = <int>[_mim, 32, 29, 3, 32, 10, 32, 29, 0, 0, 0, 0];
    final lp = Float32List(sounds.length * 5 * recitationClasses)
      ..fillRange(0, sounds.length * 5 * recitationClasses, -20);
    for (var t = 0; t < sounds.length * 5; t++) {
      lp[t * recitationClasses + (t % 5 == 0 ? sounds[t ~/ 5] : 0)] = -.01;
    }
    final events = <FollowEvent>[];
    for (var to = 10; to <= sounds.length * 5; to += 10) {
      events.addAll(
        core.step(
          Float32List.sublistView(lp, 0, to * recitationClasses),
          to,
          0,
        ),
      );
    }
    expect(events.whereType<FollowMiss>(), isEmpty);
    expect(events.whereType<FollowHeld>(), isEmpty);
    expect(core.next, greaterThanOrEqualTo(6));
  });
}
