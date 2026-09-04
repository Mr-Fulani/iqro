import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_widget_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() async {
    tz_data.initializeTimeZones();
    await initializeDateFormatting();
  });

  test('builds eight days of native transitions from one prayer source', () {
    final zone = tz.getLocation('Europe/Berlin');
    final schedules = List<PrayerSchedule>.generate(
      prayerWidgetVisibleDays + 1,
      (index) => _schedule(DateTime(2026, 3, 28 + index), zone),
    );

    final timeline = buildPrayerWidgetTimeline(
      schedules: schedules,
      locationName: 'Berlin',
      copy: PrayerWidgetCopy.forLocale('en'),
      now: DateTime.utc(2026, 3, 28, 2),
    );

    expect(timeline, hasLength(prayerWidgetVisibleDays * 6));
    final firstMidnight = tz.TZDateTime(zone, 2026, 3, 29);
    final secondMidnight = tz.TZDateTime(zone, 2026, 3, 30);
    expect(
      secondMidnight.toUtc().difference(firstMidnight.toUtc()),
      const Duration(hours: 23),
      reason: 'DST-aware midnight timestamps must be retained',
    );
    final firstScheduleMidnight = tz.TZDateTime(zone, 2026, 3, 28);
    expect(timeline[firstScheduleMidnight]!.nextPrayer, 'Fajr 05:00');
    expect(timeline[firstScheduleMidnight]!.dateLocation, contains('Berlin'));

    final afterFajr = _entryAt(timeline, schedules.first.timesUtc['fajr']!);
    expect(afterFajr.nextPrayer, 'Dhuhr 12:30');

    final afterIsha = _entryAt(timeline, schedules.first.timesUtc['isha']!);
    expect(afterIsha.nextPrayer, 'Fajr 05:00');
    expect(afterIsha.fajrTime, '05:00');
  });

  test('returns a privacy-safe placeholder instead of stale account data', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    final copy = PrayerWidgetCopy.forLocale('ru');
    final timeline = buildPrayerWidgetTimeline(
      schedules: const <PrayerSchedule>[],
      locationName: copy.currentLocation,
      copy: copy,
      now: now,
    );

    expect(timeline, hasLength(1));
    final entry = timeline.values.single;
    expect(entry.dateLocation, contains('IQRO'));
    expect(entry.nextPrayer, isEmpty);
    expect(entry.fajrTime, '—');
  });

  test('widget copy follows every supported app locale', () {
    expect(PrayerWidgetCopy.forLocale('ru').staticData.fajrLabel, 'Фаджр');
    expect(PrayerWidgetCopy.forLocale('en').staticData.fajrLabel, 'Fajr');
    expect(PrayerWidgetCopy.forLocale('ar').staticData.fajrLabel, 'الفجر');
    expect(PrayerWidgetCopy.forLocale('tr').staticData.fajrLabel, 'İmsak');
    expect(PrayerWidgetCopy.forLocale('de').locale, 'en');
  });
}

PrayerWidgetTimelineEntry _entryAt(
  Map<DateTime, PrayerWidgetTimelineEntry> timeline,
  DateTime instant,
) => timeline.entries
    .firstWhere((entry) => entry.key.isAtSameMomentAs(instant))
    .value;

PrayerSchedule _schedule(DateTime date, tz.Location zone) {
  const wallClock = <String, (int, int)>{
    'fajr': (5, 0),
    'dhuhr': (12, 30),
    'asr': (16, 15),
    'maghrib': (19, 20),
    'isha': (21, 0),
  };
  final times = <String, DateTime>{};
  final timesUtc = <String, DateTime>{};
  for (final item in wallClock.entries) {
    final local = tz.TZDateTime(
      zone,
      date.year,
      date.month,
      date.day,
      item.value.$1,
      item.value.$2,
    );
    times[item.key] = DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
    timesUtc[item.key] = local.toUtc();
  }
  return PrayerSchedule(
    date: DateTime(date.year, date.month, date.day),
    timezone: zone.name,
    times: times,
    timesUtc: timesUtc,
    methodName: 'test',
    warnings: const <String>[],
  );
}
