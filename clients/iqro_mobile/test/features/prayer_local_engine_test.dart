import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/prayer/prayer_local_engine.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  const engine = LocalPrayerEngine();
  const method = LocalPrayerMethod(
    code: 'muslim-world-league',
    fajrAngle: 18,
    ishaAngle: 17,
    ishaIntervalMinutes: null,
    adjustments: <String, int>{'dhuhr': 1},
  );

  setUpAll(tz_data.initializeTimeZones);

  for (final testCase in _goldenCases) {
    test('matches pinned Adhan 4.4.4: ${testCase.id}', () {
      final result = engine.calculate(
        LocalPrayerInput(
          latitude: testCase.latitude,
          longitude: testCase.longitude,
          date: DateTime.parse(testCase.date),
          method: method,
          highLatitudeRule: testCase.highLatitudeRule,
          polarResolution: testCase.polarResolution,
        ),
      );

      for (final entry in testCase.expectedUtc.entries) {
        final expected = DateTime.parse(entry.value);
        final delta = result.timesUtc[entry.key]!.difference(expected).abs();
        expect(
          delta,
          lessThanOrEqualTo(const Duration(seconds: 1)),
          reason: entry.key,
        );
      }
      expect(result.fallback.applied, testCase.fallbackDate != null);
      expect(
        result.fallback.referenceDate,
        testCase.fallbackDate == null
            ? null
            : DateTime.parse('${testCase.fallbackDate!}T00:00:00Z'),
      );
    });
  }

  test('aligns the astronomical date to the requested civil date', () {
    final result = engine.calculateForCivilDate(
      LocalPrayerInput(
        latitude: 1.8721,
        longitude: -157.4278,
        date: _kiritimatiDate,
        method: method,
        highLatitudeRule: 'middle_of_night',
        polarResolution: 'unresolved',
      ),
      tz.getLocation('Pacific/Kiritimati'),
    );
    final localNoon = tz.TZDateTime.from(
      result.result.timesUtc['dhuhr']!,
      tz.getLocation('Pacific/Kiritimati'),
    );

    expect(localNoon.year, 2026);
    expect(localNoon.month, 8);
    expect(localNoon.day, 9);
    expect(result.astronomicalDate, DateTime.utc(2026, 8, 8));
  });

  test('rejects an unresolved polar day without leaking coordinates', () {
    expect(
      () => engine.calculate(
        LocalPrayerInput(
          latitude: 69.6492,
          longitude: 18.9553,
          date: DateTime.utc(2026, 6, 21),
          method: method,
          highLatitudeRule: 'seventh_of_night',
          polarResolution: 'unresolved',
        ),
      ),
      throwsA(
        isA<LocalPrayerCalculationUnavailable>().having(
          (error) => error.reason,
          'reason',
          'polar_sunrise_or_sunset_unresolved',
        ),
      ),
    );
  });

  test('applies Hanafi Asr and manual minute adjustments independently', () {
    final standard = engine.calculate(
      LocalPrayerInput(
        latitude: 41.0082,
        longitude: 28.9784,
        date: DateTime.utc(2026, 8, 9),
        method: method,
        highLatitudeRule: 'middle_of_night',
        polarResolution: 'unresolved',
      ),
    );
    final customized = engine.calculate(
      LocalPrayerInput(
        latitude: 41.0082,
        longitude: 28.9784,
        date: DateTime.utc(2026, 8, 9),
        method: method,
        highLatitudeRule: 'middle_of_night',
        polarResolution: 'unresolved',
        hanafiAsr: true,
        adjustments: const <String, int>{'fajr': 7},
      ),
    );

    expect(
      customized.timesUtc['fajr']!.difference(standard.timesUtc['fajr']!),
      const Duration(minutes: 7),
    );
    expect(
      customized.timesUtc['asr']!.isAfter(standard.timesUtc['asr']!),
      isTrue,
    );
    expect(customized.timesUtc['dhuhr'], standard.timesUtc['dhuhr']);
  });
}

final _kiritimatiDate = DateTime.utc(2026, 8, 9);

class _GoldenCase {
  const _GoldenCase({
    required this.id,
    required this.date,
    required this.latitude,
    required this.longitude,
    required this.highLatitudeRule,
    required this.polarResolution,
    required this.expectedUtc,
    this.fallbackDate,
  });

  final String id;
  final String date;
  final double latitude;
  final double longitude;
  final String highLatitudeRule;
  final String polarResolution;
  final Map<String, String> expectedUtc;
  final String? fallbackDate;
}

const _goldenCases = <_GoldenCase>[
  _GoldenCase(
    id: 'raleigh',
    date: '2026-08-09',
    latitude: 35.78056,
    longitude: -78.6389,
    highLatitudeRule: 'middle_of_night',
    polarResolution: 'unresolved',
    expectedUtc: <String, String>{
      'fajr': '2026-08-09T08:53:00Z',
      'sunrise': '2026-08-09T10:29:00Z',
      'dhuhr': '2026-08-09T17:21:00Z',
      'asr': '2026-08-09T21:05:00Z',
      'maghrib': '2026-08-10T00:11:00Z',
      'isha': '2026-08-10T01:40:00Z',
    },
  ),
  _GoldenCase(
    id: 'istanbul',
    date: '2026-08-09',
    latitude: 41.0082,
    longitude: 28.9784,
    highLatitudeRule: 'middle_of_night',
    polarResolution: 'unresolved',
    expectedUtc: <String, String>{
      'fajr': '2026-08-09T01:20:00Z',
      'sunrise': '2026-08-09T03:08:00Z',
      'dhuhr': '2026-08-09T10:11:00Z',
      'asr': '2026-08-09T14:01:00Z',
      'maghrib': '2026-08-09T17:11:00Z',
      'isha': '2026-08-09T18:51:00Z',
    },
  ),
  _GoldenCase(
    id: 'polar aqrab yaum',
    date: '2020-06-21',
    latitude: 66.313,
    longitude: 17.886,
    highLatitudeRule: 'seventh_of_night',
    polarResolution: 'aqrab_yaum',
    fallbackDate: '2020-07-04',
    expectedUtc: <String, String>{
      'fajr': '2020-06-20T22:44:00Z',
      'sunrise': '2020-06-20T22:55:00Z',
      'dhuhr': '2020-06-21T10:54:00Z',
      'asr': '2020-06-21T15:49:00Z',
      'maghrib': '2020-06-21T21:58:00Z',
      'isha': '2020-06-21T22:09:00Z',
    },
  ),
  _GoldenCase(
    id: 'kiritimati date line',
    date: '2026-08-09',
    latitude: 1.8721,
    longitude: -157.4278,
    highLatitudeRule: 'middle_of_night',
    polarResolution: 'unresolved',
    expectedUtc: <String, String>{
      'fajr': '2026-08-09T15:18:00Z',
      'sunrise': '2026-08-09T16:30:00Z',
      'dhuhr': '2026-08-09T22:36:00Z',
      'asr': '2026-08-10T01:56:00Z',
      'maghrib': '2026-08-10T04:41:00Z',
      'isha': '2026-08-10T05:48:00Z',
    },
  ),
  _GoldenCase(
    id: 'pago pago date line',
    date: '2026-08-09',
    latitude: -14.2756,
    longitude: -170.702,
    highLatitudeRule: 'middle_of_night',
    polarResolution: 'unresolved',
    expectedUtc: <String, String>{
      'fajr': '2026-08-09T16:28:00Z',
      'sunrise': '2026-08-09T17:41:00Z',
      'dhuhr': '2026-08-09T23:29:00Z',
      'asr': '2026-08-10T02:48:00Z',
      'maghrib': '2026-08-10T05:16:00Z',
      'isha': '2026-08-10T06:24:00Z',
    },
  ),
];
