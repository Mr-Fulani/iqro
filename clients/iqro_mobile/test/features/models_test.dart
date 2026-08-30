import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  test('Quran and audio contracts parse current backend envelopes', () {
    final surahs = parseSurahs(<String, Object?>{
      'results': <Object?>[
        <String, Object?>{
          'id': '1',
          'number': 1,
          'name_ar': 'الفاتحة',
          'name_en': 'Al-Fatiha',
          'name_ru': 'Аль-Фатиха',
          'ayah_count': 7,
          'revelation_type': 'meccan',
          'first_page': 1,
        },
      ],
    });
    final track = AudioTrack.fromPlayback(<String, Object?>{
      'track': <String, Object?>{
        'id': 'track',
        'recitation_id': 'recitation',
        'surah_number': 1,
        'duration_ms': 90000,
        'offline_download_allowed': false,
        'asset': <String, Object?>{'url': 'https://cdn.example/1.mp3'},
      },
    });

    expect(surahs.single.nameFor('ru'), 'Аль-Фатиха');
    expect(track.url, 'https://cdn.example/1.mp3');
    expect(track.duration, const Duration(seconds: 90));
  });

  test('Mushaf page derives its real first ayah for reading progress', () {
    final page = MushafPageData.fromJson(<String, Object?>{
      'number': 2,
      'assets': const <Object?>[],
      'regions': <Object?>[
        <String, Object?>{
          'ayah': <String, Object?>{'surah': 2, 'number': 1},
          'reading_order': 1,
        },
      ],
    });

    expect(page.firstAyahReference, (surah: 2, ayah: 1));
  });

  test('Prayer method reads localized name and server defaults', () {
    final method = PrayerMethod.fromJson(<String, Object?>{
      'id': 'method-id',
      'code': 'muslim-world-league',
      'checksum_sha256': 'checksum',
      'name': <String, Object?>{
        'en': 'Muslim World League',
        'ru': 'Всемирная исламская лига',
      },
      'high_latitude_rules': <String, Object?>{'default': 'middle_of_night'},
      'polar_resolutions': <String, Object?>{'default': 'unresolved'},
    });

    expect(method.nameFor('ru'), 'Всемирная исламская лига');
    expect(method.nameFor('tr'), 'Muslim World League');
    expect(method.highLatitudeRule, 'middle_of_night');
  });
}
