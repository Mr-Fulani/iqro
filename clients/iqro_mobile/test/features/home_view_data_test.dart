import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/home/home_view_data.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  test('home resolves the actual surah instead of a fixed Al-Fatiha label', () {
    const catalog = QuranCatalog(
      fromCache: false,
      surahs: <Surah>[
        Surah(
          id: '2',
          number: 2,
          nameAr: 'البقرة',
          nameEn: 'Al-Baqarah',
          nameRu: 'Аль-Бакара',
          ayahCount: 286,
          revelationType: 'medinan',
        ),
      ],
    );

    expect(findSurah(catalog, 2)?.nameFor('ru'), 'Аль-Бакара');
    expect(findSurah(catalog, 1), isNull);
  });

  test('dua of the day is stable for the same local calendar date', () {
    final entries = <DuaEntry>[_dua('1'), _dua('2'), _dua('3')];

    final morning = duaForDate(entries, DateTime(2026, 9, 2, 8));
    final evening = duaForDate(entries, DateTime(2026, 9, 2, 23));
    final nextDay = duaForDate(entries, DateTime(2026, 9, 3, 8));

    expect(evening?.id, morning?.id);
    expect(nextDay?.id, isNot(morning?.id));
    expect(duaForDate(const <DuaEntry>[], DateTime(2026)), isNull);
  });

  test('next prayer uses chronological time and skips sunrise', () {
    final schedule = PrayerSchedule(
      date: DateTime(2026, 9, 2),
      timezone: 'Europe/Istanbul',
      times: <String, DateTime>{
        'maghrib': DateTime(2026, 9, 2, 19, 30),
        'sunrise': DateTime(2026, 9, 2, 6, 30),
        'asr': DateTime(2026, 9, 2, 16, 45),
        'dhuhr': DateTime(2026, 9, 2, 13),
        'fajr': DateTime(2026, 9, 2, 5, 15),
        'isha': DateTime(2026, 9, 2, 21),
      },
      timesUtc: const <String, DateTime>{},
      methodName: 'test',
      warnings: const <String>[],
    );

    final next = nextPrayerOccurrence(schedule, DateTime(2026, 9, 2, 14));

    expect(next?.code, 'asr');
    expect(next?.time, DateTime(2026, 9, 2, 16, 45));
  });

  test('after Isha the home shows tomorrow Fajr instead of a fake prayer', () {
    final schedule = PrayerSchedule(
      date: DateTime(2026, 9, 2),
      timezone: 'Europe/Istanbul',
      times: <String, DateTime>{
        'fajr': DateTime(2026, 9, 2, 5, 15),
        'isha': DateTime(2026, 9, 2, 21),
      },
      timesUtc: const <String, DateTime>{},
      methodName: 'test',
      warnings: const <String>[],
    );

    final next = nextPrayerOccurrence(schedule, DateTime(2026, 9, 2, 23));

    expect(next?.code, 'fajr');
    expect(next?.time, DateTime(2026, 9, 3, 5, 15));
  });
}

DuaEntry _dua(String id) => DuaEntry(
  id: id,
  sourceNumber: int.parse(id),
  collection: 'hisn-al-muslim',
  categoryTitle: 'Category $id',
  arabicText: 'دعاء',
  meaning: 'Dua $id',
  transliteration: '',
  repetitions: 1,
  sourceLabel: 'Source',
);
