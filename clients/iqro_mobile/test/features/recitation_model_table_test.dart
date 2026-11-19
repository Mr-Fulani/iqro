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
}
