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

  test('a catalog without the surah list treats every surah as present', () {
    final recitation = parse(null, surahCount: 114);

    expect(recitation.coversSurah(57), isTrue);
  });
}
