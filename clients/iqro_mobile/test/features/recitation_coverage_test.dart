import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';

void main() {
  Recitation parse(Object? surahNumbers, {int surahCount = 3}) =>
      Recitation.fromJson(<String, Object?>{
        'id': 'recitation',
        'code': 'code',
        'style': 'murattal',
        'reciter': <String, Object?>{'id': 'reciter', 'slug': 'reciter'},
        'rights': <String, Object?>{'stream': true},
        'coverage': <String, Object?>{
          'surah_count': surahCount,
          'surah_numbers': ?surahNumbers,
        },
        'capabilities': <String, Object?>{
          'listen': true,
          'ayah_playback': false,
          'memorization': false,
          'offline': false,
        },
      });

  test('a partial listening recording knows which surahs it holds', () {
    final recitation = parse(<Object?>[1, 18, 112, 'x']);

    expect(recitation.coverage?.surahNumbers, <int>[1, 18, 112]);
    expect(recitation.coversSurah(18), isTrue);
    expect(recitation.coversSurah(2), isFalse);
  });

  test('surah navigation skips to the next surah the recording holds', () {
    final recitation = parse(<Object?>[1, 18, 112]);

    expect(recitation.adjacentSurah(1, 1), 18);
    expect(recitation.adjacentSurah(18, 1), 112);
    expect(recitation.adjacentSurah(112, 1), isNull);
    expect(recitation.adjacentSurah(18, -1), 1);
    expect(recitation.adjacentSurah(1, -1), isNull);
  });

  test('a catalog without the surah list treats every surah as present', () {
    final recitation = parse(null, surahCount: 114);

    expect(recitation.coversSurah(57), isTrue);
    expect(recitation.adjacentSurah(113, 1), 114);
    expect(recitation.adjacentSurah(114, 1), isNull);
  });
}
