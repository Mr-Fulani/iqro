import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:just_audio/just_audio.dart';

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

  test('audio track selects a published rendition with a safe fallback', () {
    final playback = SurahPlayback.fromJson(<String, Object?>{
      'track': <String, Object?>{
        'id': 'track',
        'recitation_id': 'recitation',
        'surah_number': 1,
        'duration_ms': 90000,
        'offline_download_allowed': false,
        'asset': <String, Object?>{
          'url': 'https://cdn.example/standard.mp3',
          'codec': 'mp3',
          'bitrate_kbps': 128,
        },
        'renditions': <Object?>[
          <String, Object?>{
            'id': 'economy',
            'quality': 'economy',
            'is_default': false,
            'asset': <String, Object?>{
              'url': 'https://cdn.example/economy.opus',
              'codec': 'opus',
              'bitrate_kbps': 48,
            },
          },
          <String, Object?>{
            'id': 'standard',
            'quality': 'standard',
            'is_default': true,
            'asset': <String, Object?>{
              'url': 'https://cdn.example/standard.mp3',
              'codec': 'mp3',
              'bitrate_kbps': 128,
            },
          },
          <String, Object?>{
            'id': 'high',
            'quality': 'high',
            'is_default': false,
            'asset': <String, Object?>{
              'url': 'https://cdn.example/high.mp3',
              'codec': 'mp3',
              'bitrate_kbps': 256,
            },
          },
        ],
      },
    });

    final high = playback.withPreferredQuality('high');
    final unavailable = playback.withPreferredQuality('future-quality');
    final restored = SurahPlayback.fromJson(high.toJson());

    expect(playback.track.renditionQuality, 'standard');
    expect(high.track.url, 'https://cdn.example/high.mp3');
    expect(high.track.bitrateKbps, 256);
    expect(unavailable.track.url, 'https://cdn.example/standard.mp3');
    expect(restored.track.renditionQuality, 'high');
    expect(restored.track.renditions, hasLength(3));
  });

  test('rub al-hizb contract preserves its parent hizb and quarter', () {
    final division = QuranDivision.fromJson(<String, Object?>{
      'number': 49,
      'hizb_number': 13,
      'quarter_number': 1,
      'start_ayah': <String, Object?>{
        'id': 'ayah-18-1',
        'surah': 18,
        'number': 1,
      },
      'end_ayah': <String, Object?>{
        'id': 'ayah-18-16',
        'surah': 18,
        'number': 16,
      },
      'start_page': 293,
      'end_page': 295,
    });

    expect(division.number, 49);
    expect(division.hizbNumber, 13);
    expect(division.quarterNumber, 1);
    expect(division.startAyah.key, '18:1');
    expect(division.startPage, 293);
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

  test('Mushaf page hit map resolves a tap to the correct ayah', () {
    final page = MushafPageData.fromJson(<String, Object?>{
      'number': 50,
      'image_width': 900,
      'image_height': 1380,
      'assets': const <Object?>[],
      'regions': <Object?>[
        <String, Object?>{
          'id': 'region-1',
          'ayah': <String, Object?>{'id': 'ayah-1', 'surah': 3, 'number': 7},
          'reading_order': 1,
          'polygon': <Object?>[
            <Object?>[.1, .2],
            <Object?>[.9, .2],
            <Object?>[.9, .3],
            <Object?>[.1, .3],
          ],
          'x': '0.1',
          'y': '0.2',
          'width': '0.8',
          'height': '0.1',
        },
      ],
    });

    expect(page.ayahAt(.5, .25)?.key, '3:7');
    expect(page.ayahAt(.5, .5), isNull);
    expect(page.ayahAt(double.nan, .25), isNull);
    expect(page.ayahAt(1.1, .25), isNull);
    expect(page.imageWidth, 900);
    expect(page.imageHeight, 1380);
  });

  test('Mushaf page only selects integrity-bound WebP renditions', () {
    final page = MushafPageData.fromJson(<String, Object?>{
      'number': 1,
      'assets': <Object?>[
        <String, Object?>{
          'url': 'http://media.iqro.forum/page-001.webp',
          'width': 720,
          'height': 1104,
          'bytes': 1000,
          'sha256': 'a' * 64,
        },
        <String, Object?>{
          'url': 'https://media.iqro.forum/page-001-w720.webp',
          'width': 720,
          'height': 1104,
          'bytes': 1000,
          'sha256': 'b' * 64,
        },
        <String, Object?>{
          'url': 'https://media.iqro.forum/page-001-w1080.webp',
          'width': 1080,
          'height': 1656,
          'bytes': 2000,
          'sha256': 'c' * 64,
        },
      ],
      'regions': const <Object?>[],
    });

    expect(page.assets, hasLength(2));
    expect(page.bestAssetFor(360, 2)?.width, 720);
    expect(page.bestAssetFor(400, 3)?.width, 1080);
  });

  test('Mushaf reading progress follows canonical region order', () {
    final page = MushafPageData.fromJson(<String, Object?>{
      'number': 2,
      'assets': const <Object?>[],
      'regions': <Object?>[
        <String, Object?>{
          'ayah': <String, Object?>{'surah': 2, 'number': 2},
          'reading_order': 2,
        },
        <String, Object?>{
          'ayah': <String, Object?>{'surah': 2, 'number': 1},
          'reading_order': 1,
        },
      ],
    });

    expect(page.firstAyahReference, (surah: 2, ayah: 1));
  });

  test('Surah playback parses timing segments for ayah highlighting', () {
    final playback = SurahPlayback.fromJson(<String, Object?>{
      'track': <String, Object?>{
        'id': 'track',
        'recitation_id': 'recitation',
        'surah_number': 3,
        'duration_ms': 12000,
        'offline_download_allowed': false,
        'asset': <String, Object?>{'url': 'https://cdn.example/3.mp3'},
      },
      'segments': <Object?>[
        <String, Object?>{
          'ayah_id': 'ayah-1',
          'surah_number': 3,
          'ayah_number': 1,
          'start_ms': 0,
          'end_ms': 5761,
        },
        <String, Object?>{
          'ayah_id': 'ayah-2',
          'surah_number': 3,
          'ayah_number': 2,
          'start_ms': 5761,
          'end_ms': 10092,
        },
      ],
    });

    expect(playback.track.surah, 3);
    expect(playback.segmentFor(2)?.start, const Duration(milliseconds: 5761));
    expect(
      playback.segmentFor(2)?.contains(const Duration(milliseconds: 6000)),
      isTrue,
    );
  });

  test(
    'Surah playback normalizes transport order before binary search use',
    () {
      final playback = SurahPlayback.fromJson(<String, Object?>{
        'track': <String, Object?>{
          'id': 'track',
          'recitation_id': 'recitation',
          'surah_number': 3,
          'duration_ms': 12000,
          'offline_download_allowed': false,
          'asset': <String, Object?>{'url': 'https://cdn.example/3.mp3'},
        },
        'segments': <Object?>[
          <String, Object?>{
            'ayah_id': 'ayah-2',
            'surah_number': 3,
            'ayah_number': 2,
            'start_ms': 5000,
            'end_ms': 9000,
          },
          <String, Object?>{
            'ayah_id': 'ayah-1',
            'surah_number': 3,
            'ayah_number': 1,
            'start_ms': 0,
            'end_ms': 5000,
          },
        ],
      });

      expect(playback.segments.map((segment) => segment.ayah), <int>[1, 2]);
    },
  );

  test('Surah playback rejects overlapping or reversed ayah timings', () {
    expect(
      () => SurahPlayback.fromJson(<String, Object?>{
        'track': <String, Object?>{
          'id': 'track',
          'recitation_id': 'recitation',
          'surah_number': 3,
          'duration_ms': 12000,
          'offline_download_allowed': false,
          'asset': <String, Object?>{'url': 'https://cdn.example/3.mp3'},
        },
        'segments': <Object?>[
          <String, Object?>{
            'ayah_id': 'ayah-1',
            'surah_number': 3,
            'ayah_number': 1,
            'start_ms': 5000,
            'end_ms': 9000,
          },
          <String, Object?>{
            'ayah_id': 'ayah-2',
            'surah_number': 3,
            'ayah_number': 2,
            'start_ms': 0,
            'end_ms': 4000,
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('player exposes position relative to the selected ayah range', () {
    const track = AudioTrack(
      id: 'track',
      recitationId: 'recitation',
      surah: 1,
      url: 'https://cdn.example/1.mp3',
      duration: Duration(milliseconds: 34615),
      offlineDownloadAllowed: false,
    );
    const segments = <AudioSegment>[
      AudioSegment(
        ayahId: 'ayah-1',
        surah: 1,
        ayah: 1,
        start: Duration.zero,
        end: Duration(milliseconds: 2751),
      ),
      AudioSegment(
        ayahId: 'ayah-7',
        surah: 1,
        ayah: 7,
        start: Duration(milliseconds: 20605),
        end: Duration(milliseconds: 34615),
      ),
    ];
    const state = IqroAudioState(
      track: track,
      duration: Duration(milliseconds: 34615),
      position: Duration(milliseconds: 23605),
      segments: segments,
      activeAyah: 7,
      rangeStartAyah: 7,
      rangeEndAyah: 7,
    );

    expect(state.displayedAyah, 7);
    expect(state.relativePosition, const Duration(seconds: 3));
    expect(state.effectiveDuration, const Duration(milliseconds: 14010));
    expect(
      state.logicalPositionForPlayer(const Duration(seconds: 3)),
      const Duration(milliseconds: 23605),
    );
    expect(
      state.playerPositionForLogical(const Duration(milliseconds: 23605)),
      const Duration(seconds: 3),
    );
  });

  test('ayah playback is loaded as one clipped audio source', () {
    const track = AudioTrack(
      id: 'track',
      recitationId: 'recitation',
      surah: 2,
      url: 'https://cdn.example/2.mp3',
      duration: Duration(minutes: 10),
      offlineDownloadAllowed: false,
    );
    const mediaItem = MediaItem(id: 'track', title: 'Al-Baqarah');
    const start = Duration(seconds: 212);
    const end = Duration(seconds: 234);

    final source = buildIqroAudioSource(
      track: track,
      mediaItem: mediaItem,
      start: start,
      end: end,
    );

    expect(source, isA<ClippingAudioSource>());
    final clipped = source as ClippingAudioSource;
    expect(clipped.child.uri, Uri.parse(track.url));
    expect(clipped.start, start);
    expect(clipped.end, end);
    expect(clipped.duration, end - start);
  });

  test('Juz navigation parses exact page and ayah boundaries', () {
    final division = QuranDivision.fromJson(<String, Object?>{
      'number': 2,
      'start_page': 22,
      'end_page': 41,
      'start_ayah': <String, Object?>{'id': 'start', 'surah': 2, 'number': 142},
      'end_ayah': <String, Object?>{'id': 'end', 'surah': 2, 'number': 252},
    });

    expect(division.number, 2);
    expect(division.startPage, 22);
    expect(division.startAyah.key, '2:142');
    expect(division.endPage, 41);
    expect(division.endAyah.key, '2:252');
  });

  test('grouped tafsir covers every ayah in its declared range', () {
    final tafsir = QuranAyahTafsir.fromJson(<String, Object?>{
      'verse_key': '2:1',
      'start_verse_key': '2:1',
      'end_verse_key': '2:5',
      'text': 'Grouped explanation',
    });

    expect(tafsir.covers(2, 1), isTrue);
    expect(tafsir.covers(2, 3), isTrue);
    expect(tafsir.covers(2, 5), isTrue);
    expect(tafsir.covers(2, 6), isFalse);
  });

  test('browser font Mushafs remain hidden until native assets exist', () {
    final unicode = MushafVariant.fromJson(<String, Object?>{
      'source_id': 5,
      'name': 'KFGQPC HAFS',
      'qirat_name': 'Hafs',
      'pages_count': 604,
      'rendering': <String, Object?>{
        'available': true,
        'mode': 'unicode-font',
        'font_url':
            'https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/font.woff2',
      },
    });
    final pageFont = MushafVariant.fromJson(<String, Object?>{
      'source_id': 19,
      'name': 'QCF V4 Tajweed',
      'qirat_name': 'Hafs',
      'pages_count': 604,
      'rendering': <String, Object?>{
        'available': true,
        'mode': 'page-font',
        'font_url_template':
            'https://verses.quran.foundation/fonts/quran/hafs/v4/p{page}.woff2',
      },
    });

    expect(unicode.preferenceValue, '5');
    expect(unicode.supportedOnMobile, isFalse);
    expect(unicode.fontUriForPage(4)?.host, 'verses.quran.foundation');
    expect(pageFont.supportedOnMobile, isFalse);
    expect(pageFont.fontUriForPage(4)?.path, endsWith('/p4.woff2'));

    final unsafe = MushafVariant.fromJson(<String, Object?>{
      'source_id': 5,
      'name': 'Unsafe',
      'qirat_name': 'Hafs',
      'pages_count': 604,
      'rendering': <String, Object?>{
        'available': true,
        'mode': 'unicode-font',
        'font_url': 'https://example.com/font.woff2',
      },
    });
    expect(unsafe.fontUriForPage(1), isNull);
    expect(unsafe.supportedOnMobile, isFalse);
  });

  test('foundation Mushaf page derives first ayah from verse mapping', () {
    final page = FoundationMushafPage.fromJson(<String, Object?>{
      'page_number': 42,
      'verse_mapping': <String, Object?>{'5': '3-11', '4': '176'},
    }, fromCache: true);

    expect(page.pageNumber, 42);
    expect(page.firstAyahReference, (surah: 4, ayah: 176));
    expect(page.fromCache, isTrue);
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

  test('Prayer method enables local calculation only for pinned engine', () {
    final method = PrayerMethod.fromJson(
      <String, Object?>{
        'id': 'method-id',
        'code': 'muslim-world-league',
        'available': true,
        'checksum_sha256': 'checksum',
        'parameters': <String, Object?>{
          'fajr_angle': '18.00',
          'isha': <String, Object?>{
            'type': 'angle',
            'angle': '17.00',
            'interval_minutes': null,
          },
          'method_adjustments': <String, Object?>{'dhuhr': 1},
        },
      },
      algorithmId: 'adhan-js-python-adapter',
      algorithmVersion: '4.4.4-quran.1-adhanpy.1.0.5',
      timezoneDatabaseVersion: '2026.3',
    );

    expect(method.supportsLocalCalculation, isTrue);
    expect(method.fajrAngle, 18);
    expect(method.ishaAngle, 17);
    expect(method.adjustments['dhuhr'], 1);
  });

  test('Prayer schedule preserves server local wall time and UTC instant', () {
    final schedule = PrayerSchedule.fromJson(<String, Object?>{
      'date': '2026-09-01',
      'timezone': 'Europe/Istanbul',
      'method': <String, Object?>{'code': 'muslim-world-league'},
      'times': <String, Object?>{
        'fajr': <String, Object?>{
          'local': '2026-09-01T04:51:00+03:00',
          'utc': '2026-09-01T01:51:00Z',
        },
      },
      'warnings': const <Object?>[],
    });

    expect(schedule.times['fajr']?.hour, 4);
    expect(schedule.timesUtc['fajr'], DateTime.utc(2026, 9, 1, 1, 51));
  });
}
