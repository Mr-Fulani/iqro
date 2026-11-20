import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';

/// The ayahs whose words the screen and the table of expected sounds count
/// differently: for their surahs the recitation check listens with the
/// phone's speech recognition instead of the model.
const _knownDifferent = <String>{};

void main() {
  test(
    'the table of expected sounds has the screen\'s words of every ayah',
    () {
      // The text as the app gets it (text_uthmani of every ayah, 19.11.2026).
      final text =
          jsonDecode(
                utf8.decode(
                  gzip.decode(
                    File(
                      'test/fixtures/quran_text_uthmani.json.gz',
                    ).readAsBytesSync(),
                  ),
                ),
              )
              as Map<String, Object?>;
      final table =
          jsonDecode(
                File(
                  'assets/recitation_model/expected.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final symbols = (table['symbols']! as List).cast<String>();
      final surahs = table['surahs']! as Map<String, Object?>;
      final different = <String>{};
      var ayahs = 0;
      for (var surah = 1; surah <= 114; surah++) {
        final texts = (text['$surah']! as List).cast<String>();
        final entries = surahs['$surah']! as List;
        expect(entries.length, texts.length, reason: 'ayahs of surah $surah');
        for (final (index, ayahText) in texts.indexed) {
          ayahs += 1;
          final words = ayahWords(
            QuranAyah(
              id: '',
              surahNumber: surah,
              number: index + 1,
              textUthmani: ayahText,
              pages: const <int>[],
            ),
          );
          final expected = ExpectedAyah.fromJson(entries[index], symbols);
          if (expected == null || expected.spans.length != words.length) {
            different.add('$surah:${index + 1}');
          }
        }
      }
      expect(ayahs, 6236);
      expect(different, _knownDifferent);
    },
  );

  test('a word of the table has the sounds of a stop on it beside those of '
      'reading on, and neither is asked for', () {
    final table =
        jsonDecode(
              File('assets/recitation_model/expected.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final symbols = (table['symbols']! as List).cast<String>();
    final surah = (table['surahs']! as Map<String, Object?>)['2']! as List;
    String word(ExpectedAyah ayah, int index, {required bool loose}) {
      final (start, end) = ayah.spans[index];
      return <String>[
        for (var i = start; i < end; i++)
          if (ayah.loose.contains(i) == loose) symbols[ayah.sounds[i] - 1],
      ].join();
    }

    // 2:7, the ninth word: "ghishawatun wa…" read on, "ghishawah" when the
    // reader stops at the mark after it.
    final seventh = ExpectedAyah.fromJson(surah[6], symbols)!;
    expect(word(seventh, 8, loose: false), 'غِشَااوَ');
    expect(word(seventh, 8, loose: true), 'تُووه');
    // The "h" is the stop's own sound; the ending of reading on is the
    // ayah's.
    final (start, end) = seventh.spans[8];
    expect(
      <String>[
        for (var i = start; i < end; i++)
          if (seventh.added.contains(i)) symbols[seventh.sounds[i] - 1],
      ],
      <String>['ه'],
    );
    // 2:2, "la rayba fihi": a stop on either of the two words between the
    // three-dot marks leaves only the last short vowel unsaid.
    final second = ExpectedAyah.fromJson(surah[1], symbols)!;
    expect(word(second, 3, loose: false), 'رَيب');
    expect(word(second, 3, loose: true), contains('َ'));
    expect(word(second, 4, loose: false), 'فِۦۦه');
    expect(word(second, 4, loose: true), 'ِ');
  });

  test('the table writes the imala of 11:41 as the model hears it and takes '
      'the long sound of the letter ayn for no idgham', () {
    final table =
        jsonDecode(
              File('assets/recitation_model/expected.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final symbols = (table['symbols']! as List).cast<String>();
    final surahs = table['surahs']! as Map<String, Object?>;
    ExpectedAyah ayah(int surah, int number) => ExpectedAyah.fromJson(
      (surahs['$surah']! as List)[number - 1],
      symbols,
    )!;
    // "majraha" with imala: a kasra and its long vowel, which is what the
    // model writes of a right reading; the imala's own sounds it never does.
    final hud = ayah(11, 41);
    final (start, end) = hud.spans[5];
    expect(
      <String>[
        for (var i = start; i < end; i++) symbols[hud.sounds[i] - 1],
      ].join(),
      'مَجڇرِۦۦهَاا',
    );
    // "kaf ha ya ayn sad", "ayn sin qaf": the ayn's long "y" is a madd of
    // four or six counts, not a ghunnah that may be held too short.
    expect(ayah(19, 1).units, isEmpty);
    expect(ayah(42, 2).units, isEmpty);
  });
}
