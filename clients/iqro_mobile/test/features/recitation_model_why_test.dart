import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/reader_flow_screen.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/recitation_model/model_listener.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

/// Two ayahs of four and two words, three sounds each, all different.
RecitationFollowCore _core() => RecitationFollowCore(
  RecitationPassage(<ExpectedAyah>[
    ExpectedAyah(
      Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
      <(int, int)>[(0, 3), (3, 6), (6, 9), (9, 12)],
      <(int, int, int, int, int)>[],
    ),
    ExpectedAyah(
      Uint8List.fromList(<int>[13, 14, 15, 16, 17, 18]),
      <(int, int)>[(0, 3), (3, 6)],
      <(int, int, int, int, int)>[],
    ),
  ]),
);

/// The mistakes the follower finds in [sounds], each said on one frame
/// with four of silence after it, fed ten frames at a time.
List<FollowMiss> _misses(List<int> sounds, [RecitationFollowCore? follower]) {
  final core = follower ?? _core();
  final total = sounds.length * 5;
  final lp = Float32List(total * recitationClasses)
    ..fillRange(0, total * recitationClasses, -20);
  for (var t = 0; t < total; t++) {
    lp[t * recitationClasses + (t % 5 == 0 ? sounds[t ~/ 5] : 0)] = -.01;
  }
  final misses = <FollowMiss>[];
  for (var end = 10; end <= total + 40; end += 10) {
    final to = end > total ? total : end;
    misses.addAll(
      core
          .step(Float32List.sublistView(lp, 0, to * recitationClasses), to, 0)
          .whereType<FollowMiss>(),
    );
  }
  return misses;
}

void main() {
  test('a word left out is called a word left out', () {
    final miss = _misses(<int>[1, 2, 3, 7, 8, 9, 10, 11, 12, 0, 0, 0]).single;
    expect(miss.word, 1);
    expect(miss.why, FollowWhy.skipped);
  });

  test('another letter is named, with the letter written', () {
    // The second word's 5 is said as 20.
    final miss = _misses(<int>[1, 2, 3, 4, 20, 6, 7, 8, 9, 0, 0, 0]).single;
    expect(miss.word, 1);
    expect(miss.why, FollowWhy.another);
    expect(miss.expected, 5);
    expect(miss.heard, 20);
  });

  test('what is not the word, and no more can be said of, has no reason '
      'made up for it', () {
    final miss = _misses(<int>[
      1, 2, 3, 20, 21, 22, 23, 24, 25, 26, 27, 28, 20, 21, 22, 0, 0, 0, //
    ]).first;
    expect(miss.word, 1);
    expect(miss.why, FollowWhy.unknown);
  });

  group('tajweed', () {
    // 39 is the model's hidden nun (ikhfa), 25 a plain one, 38 the echo of
    // a qalqalah.
    RecitationFollowCore core(List<int> second, {List<int>? last}) =>
        RecitationFollowCore(
          RecitationPassage(<ExpectedAyah>[
            ExpectedAyah(
              Uint8List.fromList(<int>[1, 2, 3, ...second, 7, 8, 9]),
              <(int, int)>[
                (0, 3),
                (3, 3 + second.length),
                (3 + second.length, 6 + second.length),
              ],
              <(int, int, int, int, int)>[],
            ),
            ExpectedAyah(
              Uint8List.fromList(last ?? <int>[13, 14, 15]),
              <(int, int)>[
                (0, (last ?? <int>[13, 14, 15]).length),
              ],
              <(int, int, int, int, int)>[],
            ),
          ]),
        );

    test('a nun said clearly where it is hidden is a mistake, and named', () {
      final miss = _misses(<int>[
        1, 2, 3, 4, 25, 5, 6, 7, 8, 9, 0, 0, 0, //
      ], core(<int>[4, 39, 5, 6])).single;
      expect(miss.word, 1);
      expect(miss.why, FollowWhy.another);
      expect(miss.expected, 39);
      expect(miss.heard, 25);
    });

    test('hidden as written, it is none', () {
      expect(
        _misses(<int>[
          1, 2, 3, 4, 39, 5, 6, 7, 8, 9, 0, 0, 0, //
        ], core(<int>[4, 39, 5, 6])),
        isEmpty,
      );
    });

    test('a qalqalah left out inside an ayah is a mistake, and named', () {
      final miss = _misses(<int>[
        1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, //
      ], core(<int>[4, 38, 5, 6])).single;
      expect(miss.word, 1);
      expect(miss.why, FollowWhy.another);
      expect(miss.expected, 38);
      // Said, it is none.
      expect(
        _misses(<int>[
          1, 2, 3, 4, 38, 5, 6, 7, 8, 9, 0, 0, 0, //
        ], core(<int>[4, 38, 5, 6])),
        isEmpty,
      );
    });

    test('at the end of an ayah the qalqalah is there only with a stop: '
        'left out, it is no mistake', () {
      expect(
        _misses(<int>[
          1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 0, 0, 0, //
        ], core(<int>[4, 5, 6], last: <int>[13, 14, 15, 38])),
        isEmpty,
      );
    });
  });

  group('the line under the text says why', () {
    RecitationWhy why(
      FollowWhy why, [
      String expected = '',
      String heard = '',
    ]) => (why: why, expected: expected, heard: heard);

    test('in Russian, each reason in its own words', () {
      final l10n = lookupAppLocalizations(const Locale('ru'));
      expect(
        recitationWhyText(l10n, why(FollowWhy.skipped)),
        'Слово пропущено. Прочитайте его',
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.another, 'م', 'ر')),
        'Слышно «ر» вместо «م»',
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.another, 'ِ', 'ُ')),
        'Другая огласовка: слышна дамма, а написана кясра',
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.ghunnah)),
        contains('Гунна'),
      );
      expect(recitationWhyText(l10n, why(FollowWhy.madd)), contains('Мадд'));
      expect(
        recitationWhyText(l10n, why(FollowWhy.shaddah)),
        'Шадда: буква не удвоена',
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.izhar)),
        startsWith('Изхар'),
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.omitted, 'ت')),
        'Пропущен звук или слог слова',
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.added, '', 'ن')),
        'В слове лишний звук',
      );
      // The model's own marks are not shown: the rule is named.
      expect(
        recitationWhyText(l10n, why(FollowWhy.another, 'ں', 'ن')),
        startsWith('Ихфа'),
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.another, '۾', 'ن')),
        startsWith('Икляб'),
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.another, 'ڇ')),
        startsWith('Калькаля'),
      );
      expect(
        recitationWhyText(l10n, why(FollowWhy.unknown)),
        'Слово не распознано. Прочитайте его ещё раз',
      );
      // "Another" with nothing to name is not given a letter.
      expect(
        recitationWhyText(l10n, why(FollowWhy.another)),
        'Слово не распознано. Прочитайте его ещё раз',
      );
    });

    test('in every language of the app, short enough for two lines of a '
        'phone, and never "read louder"', () {
      for (final code in <String>['ru', 'en', 'ar', 'tr']) {
        final l10n = lookupAppLocalizations(Locale(code));
        for (final reason in <RecitationWhy>[
          why(FollowWhy.skipped),
          why(FollowWhy.another, 'م', 'ر'),
          why(FollowWhy.another, 'َ', 'ِ'),
          why(FollowWhy.another, 'ں', 'ن'),
          why(FollowWhy.another, '۾', 'ن'),
          why(FollowWhy.another, 'ڇ'),
          why(FollowWhy.ghunnah),
          why(FollowWhy.madd),
          why(FollowWhy.shaddah),
          why(FollowWhy.izhar),
          why(FollowWhy.omitted, 'ت'),
          why(FollowWhy.added, '', 'ن'),
          why(FollowWhy.unknown),
        ]) {
          final text = recitationWhyText(l10n, reason);
          expect(text, isNotEmpty, reason: code);
          expect(text.length, lessThan(70), reason: '$code: $text');
          expect(text, isNot(l10n.recitationNotHearingOnDevice));
          expect(text, isNot(l10n.recitationNotHearing));
        }
        // A letter is shown as written; a vowel is called by its name.
        expect(
          recitationWhyText(l10n, why(FollowWhy.another, 'م', 'ر')),
          allOf(contains('م'), contains('ر')),
        );
        // (Arabic is itself written with the marks.)
        if (code != 'ar') {
          expect(
            recitationWhyText(l10n, why(FollowWhy.another, 'َ', 'ِ')),
            allOf(isNot(contains('َ')), isNot(contains('ِ'))),
          );
        }
        expect(
          recitationWhyText(l10n, why(FollowWhy.another, 'َ', 'ِ')),
          allOf(
            contains(l10n.recitationVowelFatha),
            contains(l10n.recitationVowelKasra),
          ),
        );
      }
    });
  });
}
