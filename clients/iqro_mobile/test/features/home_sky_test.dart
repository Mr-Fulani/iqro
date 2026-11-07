import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/home/home_sky_card.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

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

  test('the sun and the moon share one orbit through the day and night', () {
    final timeline = SkyTimeline.fromSchedule(_moscow)!;
    expect(timeline.orbitAngle(461), 0);
    expect(timeline.orbitAngle((461 + 998) / 2), closeTo(math.pi / 2, 1e-9));
    expect(timeline.orbitAngle(998), closeTo(math.pi, 1e-9));
    // The middle of the night, between maghrib and the next sunrise, is the
    // moon's top.
    const midnight = 998 + (1440 - (998 - 461)) / 2;
    expect(timeline.orbitAngle(midnight), closeTo(1.5 * math.pi, 1e-9));
    expect(timeline.orbitAngle(midnight - 1440), closeTo(1.5 * math.pi, 1e-9));
    expect(timeline.orbitAngle(460), greaterThan(1.99 * math.pi));
  });

  test('the opening starts before the last sunrise or maghrib', () {
    final timeline = SkyTimeline.fromSchedule(_moscow)!;
    expect(timeline.startFor(788), 421);
    expect(timeline.startFor(1170), 958);
    expect(timeline.startFor(120), 958 - 1440);
    expect(timeline.startFor(461), 421);
    expect(timeline.startFor(998), 958);
  });

  test('the sky colours wrap around midnight', () {
    final timeline = SkyTimeline.fromSchedule(_moscow)!;
    final yesterday = timeline.paletteAt(958 - 1440);
    final today = timeline.paletteAt(958);
    expect(yesterday.top, today.top);
    expect(yesterday.middle, today.middle);
    expect(yesterday.horizon, today.horizon);
    expect(yesterday.darkness, today.darkness);
  });

  test('close times keep their marks but spread their labels', () {
    final spread = spreadSkyLabels([28, 60, 180, 240, 300, 330], 361, 46);
    expect(spread, [28, 74, 180, 240, 293, 339]);
  });

  testWidgets('the card keeps its height when the schedule arrives', (
    tester,
  ) async {
    Future<double> heightOf({required bool loading}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: IqroTheme.light(),
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: ListView(
              children: [
                HomePrayerSkyCard(
                  key: ValueKey(loading),
                  schedule: loading ? null : _moscow,
                  loading: loading,
                  clock: DateTime(2026, 11, 6, 10),
                  onTap: () {},
                  onQibla: () {},
                  onReminders: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .getSize(
            find
                .descendant(
                  of: find.byType(HomePrayerSkyCard),
                  matching: find.byType(ClipRRect),
                )
                .first,
          )
          .height;
    }

    final loading = await heightOf(loading: true);
    expect(await heightOf(loading: false), loading);
  });
}
