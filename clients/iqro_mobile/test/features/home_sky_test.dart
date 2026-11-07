import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/home/home_sky_card.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';

// The cases mirror services/web/lib/sky-band.test.ts, so the sun and the
// sky stand alike on the site and in the app.
PrayerSchedule _schedule(Map<String, (int, int)> times) => PrayerSchedule(
  date: DateTime(2026, 11, 6),
  timezone: 'Europe/Moscow',
  times: {
    for (final MapEntry(:key, :value) in times.entries)
      key: DateTime(2026, 11, 6, value.$1, value.$2),
  },
  timesUtc: const {},
  methodName: 'test',
  warnings: const [],
);

final _moscow = _schedule({
  'fajr': (5, 52),
  'sunrise': (7, 41),
  'dhuhr': (12, 15),
  'asr': (14, 18),
  'maghrib': (16, 38),
  'isha': (18, 22),
});

void main() {
  test('the timeline reads the city wall clock in order', () {
    expect(SkyTimeline.fromSchedule(_moscow)!.stops, [
      352,
      461,
      735,
      858,
      998,
      1102,
    ]);
    expect(SkyTimeline.fromSchedule(null), isNull);
    expect(
      SkyTimeline.fromSchedule(
        _schedule({'fajr': (5, 52), 'sunrise': (7, 41)}),
      ),
      isNull,
    );
  });

  test('the sky is night, dawn, day and sunset at the right moments', () {
    final timeline = SkyTimeline.fromSchedule(_moscow)!;
    expect(timeline.paletteAt(100).top, const Color(0xFF060E23));
    expect(timeline.paletteAt(400).horizon, const Color(0xFFF0A06C));
    expect(timeline.paletteAt(788).darkness, 1);
    expect(timeline.paletteAt(965).middle, const Color(0xFFC7607A));
    expect(timeline.paletteAt(1300).stars, 1);
  });

  test('the sun starts below the horizon', () {
    final timeline = SkyTimeline.fromSchedule(_moscow)!;
    expect(timeline.startFor(788), 400);
    expect(timeline.startFor(120), 30);
  });

  test('close times keep their marks but spread their labels', () {
    final spread = spreadSkyLabels([28, 60, 180, 240, 300, 330], 361, 46);
    expect(spread, [28, 74, 180, 240, 293, 339]);
  });
}
