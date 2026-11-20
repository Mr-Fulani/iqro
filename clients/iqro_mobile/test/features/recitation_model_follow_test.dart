import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/recitation_model/pipeline.dart';

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
        FollowHeld(:final place, :final fromFrame, :final toFrame) =>
          'held ${place.kind} on ${place.word} for ${toFrame - fromFrame}',
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

  test('a word read has its held sound pointed out, with how long', () {
    // The second word has a nun held for four counts.
    final ayah = ExpectedAyah(
      Uint8List.fromList(<int>[1, 2, 3, 4, 24, 24, 24, 24, 5, 6, 7, 8]),
      <(int, int)>[(0, 3), (3, 9), (9, 12)],
      <(int, int, int, int, int)>[(0, 4, 8, 1, 4)],
    );
    final full = RecitationFollowCore(RecitationPassage(<ExpectedAyah>[ayah]));
    final seen = _follow(full, <int>[
      1, 2, 3, 4, 24, 24, 24, 24, 5, 6, 7, 8, 0, 0, 0, //
    ]);
    // From the nun's first frame to the sound after it: four counts.
    expect(seen, contains('held 0 on 1 for 20'));
    final short = RecitationFollowCore(RecitationPassage(<ExpectedAyah>[ayah]));
    final less = _follow(short, <int>[1, 2, 3, 4, 24, 5, 6, 7, 8, 0, 0, 0]);
    expect(less, contains('held 0 on 1 for 5'));
  });

  test('another letter in a word stops the place on it', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    // The second word's 5 is said as 20, a letter that is not near it.
    final seen = _follow(core, <int>[1, 2, 3, 4, 20, 6, 7, 8, 9, 0, 0, 0]);
    expect(seen, contains('miss 1'));
    expect(core.next, 1);
    // Read rightly after that, the place goes on.
    final again = RecitationFollowCore(RecitationPassage(_ayahs()));
    _follow(again, <int>[
      1, 2, 3, 4, 20, 6, 0, 0, 0, 0, 4, 5, 6, 7, 8, 9, 0, 0, 0, //
    ]);
    expect(again.wrong, isFalse);
    expect(again.next, 3);
  });

  test('a long first word said with another letter is a mistake too', () {
    // As "alif lam ra" for "alif lam mim": one long word, most of it right.
    final passage = RecitationPassage(<ExpectedAyah>[
      ExpectedAyah(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
        <(int, int)>[(0, 6), (6, 9)],
        <(int, int, int, int, int)>[],
      ),
    ]);
    final core = RecitationFollowCore(passage);
    final seen = _follow(core, <int>[1, 2, 3, 20, 5, 6, 7, 8, 9, 0, 0, 0]);
    expect(seen, contains('miss 0'));
    expect(core.next, 0);
  });

  test('a word to be read again is waited on', () {
    final core = RecitationFollowCore(RecitationPassage(_ayahs()));
    _follow(core, <int>[1, 2, 3, 4, 5, 6, 0, 0, 0]);
    expect(core.next, 2);
    core.sayAgain(1);
    expect(core.next, 1);
    expect(core.wrong, isTrue);
  });

  test('a later word that begins as the word expected is no word left out '
      'until five of its sounds are heard', () {
    // The second word and the fourth begin with the same two sounds.
    RecitationFollowCore core() => RecitationFollowCore(
      RecitationPassage(<ExpectedAyah>[
        ExpectedAyah(
          Uint8List.fromList(<int>[
            1, 2, 3, //
            4, 5, 6, 7, 8, 9, //
            10, 11, 12, //
            4, 5, 20, 21, 22, 23,
          ]),
          <(int, int)>[(0, 3), (3, 9), (9, 12), (12, 18)],
          <(int, int, int, int, int)>[],
        ),
      ]),
    );
    // Four sounds that the fourth word has: the model may have misheard
    // the second, which the reader is still on.
    expect(
      _follow(core(), <int>[1, 2, 3, 4, 5, 20, 21, 0, 0, 0]),
      isNot(contains('miss 1')),
    );
    // All of the fourth: the second and the third were left out.
    expect(
      _follow(core(), <int>[1, 2, 3, 4, 5, 20, 21, 22, 23, 0, 0, 0]),
      contains('miss 1'),
    );
    // A later word that begins otherwise is one after three sounds.
    expect(
      _follow(core(), <int>[1, 2, 3, 10, 11, 12, 0, 0, 0]),
      contains('miss 1'),
    );
  });

  group('silence', () {
    // Ten seconds: the reader's voice, then nothing.
    Float32List loudness() => Float32List(3000)
      ..fillRange(0, 500, 1e6)
      ..fillRange(500, 1000, 10);
    Float32List sounds(int frames) {
      final lp = Float32List(frames * recitationClasses)
        ..fillRange(0, frames * recitationClasses, -20);
      for (var t = 0; t < frames; t++) {
        lp[t * recitationClasses + 5] = -.01;
      }
      return lp;
    }

    test('what the model makes up in the middle of a silence is written '
        'over', () {
      final lp = sounds(500);
      hushSilence(lp, 0, 500, loudness(), 1000);
      bool silent(int frame) => lp[frame * recitationClasses] == 0;
      // While the reader speaks, and three tenths of a second after.
      expect(silent(100), isFalse);
      expect(silent(260), isFalse);
      // Deep in the silence, to its very end.
      expect(silent(300), isTrue);
      expect(silent(499), isTrue);
      expect(lp[300 * recitationClasses + 5], -20);
    });

    test('a room as loud as the voice is left as the model hears it', () {
      final lp = sounds(500);
      final noisy = Float32List(3000)
        ..fillRange(0, 500, 1e6)
        ..fillRange(500, 1000, 5e4);
      hushSilence(lp, 0, 500, noisy, 1000);
      expect(lp[400 * recitationClasses], -20);
    });

    test('nothing is written over before the voice is known', () {
      final lp = sounds(100);
      hushSilence(lp, 0, 100, Float32List(3000), 200);
      expect(lp[50 * recitationClasses], -20);
    });
  });

  group('a word may be stopped on', () {
    // Three words. The second ends in 7 8 when the reading goes on and in
    // 30 when it is stopped on; the third begins with 31 only after a stop.
    RecitationFollowCore core() => RecitationFollowCore(
      RecitationPassage(<ExpectedAyah>[
        ExpectedAyah(
          Uint8List.fromList(<int>[
            1, 2, 3, //
            4, 5, 6, 7, 8, 30, //
            31, 9, 10, 11, 12,
          ]),
          <(int, int)>[(0, 3), (3, 9), (9, 14)],
          <(int, int, int, int, int)>[],
          <int>{6, 7, 8, 9},
        ),
      ]),
    );

    test('read on, it has the sounds of reading on', () {
      final follower = core();
      final seen = _follow(follower, <int>[
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0, 0, 0, //
      ]);
      expect(seen, <String>['on 0', 'on 1', 'on 2']);
      expect(follower.next, 3);
    });

    test('stopped on, it has the sounds of the stop, and the next word '
        'those of a beginning', () {
      final follower = core();
      final seen = _follow(follower, <int>[
        1, 2, 3, 4, 5, 6, 30, 0, 0, 0, 0, 0, 0, //
        31, 9, 10, 11, 12, 0, 0, 0,
      ]);
      expect(seen, <String>['on 0', 'on 1', 'on 2']);
      expect(follower.next, 3);
    });

    test('with neither ending said it is read all the same: the reader '
        'stopped on its last letter', () {
      final follower = core();
      final seen = _follow(follower, <int>[
        1, 2, 3, 4, 5, 6, 0, 0, 0, 0, 9, 10, 11, 12, 0, 0, 0, //
      ]);
      expect(seen, <String>['on 0', 'on 1', 'on 2']);
    });

    test('a sound that is always said is still asked for', () {
      final follower = core();
      final seen = _follow(follower, <int>[
        1, 2, 3, 4, 20, 21, 30, 0, 0, 0, 0, 0, 0, //
        31, 9, 10, 11, 12, 0, 0, 0,
      ]);
      expect(seen, contains('miss 1'));
      expect(follower.next, 1);
    });
  });
}
