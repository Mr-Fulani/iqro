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

  test('Mushaf variants expose only the mobile-safe Unicode renderer', () {
    final unicode = MushafVariant.fromJson(<String, Object?>{
      'source_id': 5,
      'name': 'KFGQPC HAFS',
      'qirat_name': 'Hafs',
      'pages_count': 604,
      'rendering': <String, Object?>{'available': true, 'mode': 'unicode-font'},
    });
    final pageFont = MushafVariant.fromJson(<String, Object?>{
      'source_id': 19,
      'name': 'QCF V4 Tajweed',
      'qirat_name': 'Hafs',
      'pages_count': 604,
      'rendering': <String, Object?>{'available': true, 'mode': 'page-font'},
    });

    expect(unicode.preferenceValue, '5');
    expect(unicode.supportedOnMobile, isTrue);
    expect(pageFont.supportedOnMobile, isFalse);
  });

  test('Foundation Mushaf words are grouped into ordered page lines', () {
    final page = FoundationMushafPageData.fromJson(<String, Object?>{
      'mushaf_id': 5,
      'page_number': 1,
      'qirat_name': 'Hafs',
      'words': <Map<String, Object?>>[
        <String, Object?>{
          'text': 'ٱللَّهِ',
          'line_number': 9,
          'position_in_line': 2,
        },
        <String, Object?>{
          'text': 'بِسۡمِ',
          'line_number': 9,
          'position_in_line': 1,
        },
        <String, Object?>{
          'text': 'ٱلۡحَمۡدُ',
          'line_number': 10,
          'position_in_line': 1,
        },
      ],
    });

    expect(page.lines, hasLength(2));
    expect(page.lines.first.map((word) => word.text), <String>[
      'بِسۡمِ',
      'ٱللَّهِ',
    ]);
  });

  test('Reciter uses Turkish content with an English fallback', () {
    final localized = Reciter.fromJson(<String, Object?>{
      'id': 'reciter',
      'slug': 'saad-al-ghamdi',
      'name_ar': 'سعد الغامدي',
      'name_en': 'Saad al-Ghamdi',
      'name_ru': 'Саад аль-Гамди',
      'name_tr': 'Saad el-Gamidi',
      'biography_en': 'English biography',
      'biography_tr': 'Türkçe biyografi',
    });
    final fallback = Reciter.fromJson(<String, Object?>{
      'id': 'fallback',
      'slug': 'fallback-reciter',
      'name_en': 'English name',
      'biography_en': 'English biography',
    });

    expect(localized.nameFor('tr'), 'Saad el-Gamidi');
    expect(localized.biographyFor('tr'), 'Türkçe biyografi');
    expect(fallback.nameFor('tr'), 'English name');
    expect(fallback.biographyFor('tr'), 'English biography');
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
