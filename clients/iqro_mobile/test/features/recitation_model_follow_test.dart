import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';

/// Two ayahs of four and two words, three sounds each, all different.
List<ExpectedAyah> _ayahs() => <ExpectedAyah>[
  ExpectedAyah(
    Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
    <(int, int)>[(0, 3), (3, 6), (6, 9), (9, 12)],
    <(int, int, int, int, int)>[],
  ),
  ExpectedAyah(Uint8List.fromList(<int>[13, 14, 15, 16, 17, 18]), <(int, int)>[
    (0, 3),
    (3, 6),
  ], <(int, int, int, int, int)>[]),
];

/// What the model would give for these sounds said one after another:
/// each on one frame, four frames of silence after it.
Float32List _frames(List<int> sounds) {
  final lp = Float32List(sounds.length * 5 * recitationClasses)
    ..fillRange(0, sounds.length * 5 * recitationClasses, -20);
  for (var t = 0; t < sounds.length * 5; t++) {
    lp[t * recitationClasses + (t % 5 == 0 ? sounds[t ~/ 5] : 0)] = -.01;
  }
  return lp;
}

/// Feeds [sounds] to a follower ten frames at a time, as the app does: the
/// last 130 frames each step.
List<String> _follow(RecitationFollowCore core, List<int> sounds) {
  final lp = _frames(sounds);
  final total = sounds.length * 5;
  final seen = <String>[];
  for (var end = 10; end <= total + 40; end += 10) {
    final to = end > total ? total : end;
    final from = to > 130 ? to - 130 : 0;
    final window = Float32List.sublistView(
      lp,
      from * recitationClasses,
      to * recitationClasses,
    );
    for (final event in core.step(window, to - from, from)) {
      seen.add(switch (event) {
        FollowPlace(:final word) => 'on $word',
        FollowMiss(:final word) => 'miss $word',
        FollowAyahRead(:final ayah) => 'ayah $ayah',
      });
    }
  }
  return seen;
}

void main() {
  test('a right reading moves the place word by word', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    final seen = _follow(core, <int>[
      for (var s = 1; s <= 18; s++) s,
      0, 0, 0, //
    ]);
    expect(seen.where((e) => e.startsWith('on')).toList(), <String>[
      'on 0', 'on 1', 'on 2', 'on 3', 'on 4', 'on 5', //
    ]);
    expect(seen.where((e) => e.startsWith('miss')), isEmpty);
    expect(seen, containsAll(<String>['ayah 0', 'ayah 1']));
    expect(core.next, 6);
  });

  test('a word left out is a mistake, and the place waits on it', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    final seen = _follow(core, <int>[1, 2, 3, 7, 8, 9, 10, 11, 12]);
    expect(seen, contains('miss 1'));
    expect(core.next, 1);
    expect(core.wrong, isTrue);
    // Read after all: the place moves on from it.
    final after = RecitationFollowCore(RecitationPassage(_ayahs()));
    final again = _follow(after, <int>[
      1, 2, 3, 7, 8, 9, 40, 40, 40, 40, 40, 4, 5, 6, 7, 8, 9, 0, 0, 0, //
    ]);
    expect(again, contains('miss 1'));
    expect(after.next, greaterThanOrEqualTo(3));
    expect(after.wrong, isFalse);
  });

  test('other words in place of the next one are a mistake', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    final seen = _follow(core, <int>[
      1, 2, 3, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, //
    ]);
    expect(seen, contains('miss 1'));
    expect(core.next, 1);
  });

  test('what is said before the first word is no mistake', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    final seen = _follow(core, <int>[
      30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 1, 2, 3, 4, 5, 6, //
    ]);
    expect(seen.where((e) => e.startsWith('miss')), isEmpty);
    expect(core.next, greaterThanOrEqualTo(1));
  });

  test('the last word said again is no mistake', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    final seen = _follow(core, <int>[
      1, 2, 3, 4, 5, 6, 0, 0, 0, 4, 5, 6, 4, 5, 6, 4, 5, 6, 7, 8, 9, //
    ]);
    expect(seen.where((e) => e.startsWith('miss')), isEmpty);
    expect(core.next, greaterThanOrEqualTo(2));
  });

  test('two words read again take the place back', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    _follow(core, <int>[
      1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 0, 0, 0, //
    ]);
    expect(core.wrong, isFalse);
    expect(core.next, 2);
  });

  test('a held sound is one sound to the follower', () {
    final passage = RecitationPassage(<ExpectedAyah>[
      ExpectedAyah(
        Uint8List.fromList(<int>[1, 2, 2, 2, 2, 3, 4, 5]),
        <(int, int)>[(0, 6), (6, 8)],
        <(int, int, int, int, int)>[],
      ),
    ]);
    expect(passage.sounds, <int>[1, 2, 3, 4, 5]);
    final core = RecitationFollowCore(passage);
    final seen = _follow(core, <int>[1, 2, 2, 2, 2, 2, 2, 3, 4, 5, 0, 0, 0]);
    expect(seen.where((e) => e.startsWith('miss')), isEmpty);
    expect(core.next, 2);
  });

  test('a ghunnah held too short is remarked on, a full one is not', () {
    final ayah = ExpectedAyah(
      Uint8List.fromList(<int>[
        1,
        2,
        24,
        24,
        24,
        24,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16, //
      ]),
      <(int, int)>[(0, 20)],
      <(int, int, int, int, int)>[(0, 2, 6, 0, 4)],
    );
    final rest = <int>[for (var s = 5; s <= 16; s++) s];
    final short = <int>[1, 2, 24, 24, 3, 4, ...rest];
    expect(
      tajweedRemarks(_frames(short), short.length * 5, ayah),
      <TajweedRemark>[(kind: 0, word: 0, heard: 2, expected: 4)],
    );
    final full = <int>[1, 2, 24, 24, 24, 24, 3, 4, ...rest];
    expect(tajweedRemarks(_frames(full), full.length * 5, ayah), isEmpty);
  });
}
