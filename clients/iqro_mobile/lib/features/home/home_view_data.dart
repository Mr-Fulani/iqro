import '../dua/dua_repository.dart';
import '../prayer/prayer_repository.dart';
import '../quran/quran_models.dart';

class PrayerOccurrence {
  const PrayerOccurrence({required this.code, required this.time});

  final String code;
  final DateTime time;
}

Surah? findSurah(QuranCatalog? catalog, int number) {
  if (catalog == null) return null;
  for (final surah in catalog.surahs) {
    if (surah.number == number) return surah;
  }
  return null;
}

DuaEntry? duaForDate(List<DuaEntry>? entries, DateTime date) {
  if (entries == null || entries.isEmpty) return null;
  final day = DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(2000)).inDays;
  final index = ((day % entries.length) + entries.length) % entries.length;
  return entries[index];
}

PrayerOccurrence? nextPrayerOccurrence(PrayerSchedule? schedule, DateTime now) {
  if (schedule == null || schedule.times.isEmpty) return null;
  final upcoming =
      schedule.times.entries
          .where((entry) => entry.key != 'sunrise' && entry.value.isAfter(now))
          .map((entry) => PrayerOccurrence(code: entry.key, time: entry.value))
          .toList(growable: false)
        ..sort((left, right) => left.time.compareTo(right.time));
  if (upcoming.isNotEmpty) return upcoming.first;

  final fajr = schedule.times['fajr'];
  if (fajr == null) return null;
  return PrayerOccurrence(
    code: 'fajr',
    time: fajr.add(const Duration(days: 1)),
  );
}
