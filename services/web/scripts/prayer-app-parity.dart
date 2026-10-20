// Generates lib/prayer-engine.app-parity.json with the app's local engine so the
// web port is checked against the app's own numbers. From services/web, after
// `flutter pub get` in clients/iqro_mobile:
//   dart run --packages=../../clients/iqro_mobile/.dart_tool/package_config.json \
//     scripts/prayer-app-parity.dart > /tmp/parity.json
// then reformat into lib/prayer-engine.app-parity.json (one day per line).
import 'dart:convert';
import 'dart:io';

import 'package:iqro_mobile/features/prayer/prayer_local_engine.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const methods = <String, LocalPrayerMethod>{
  'muslim-world-league': LocalPrayerMethod(code: 'muslim-world-league', fajrAngle: 18, ishaAngle: 17, ishaIntervalMinutes: null, adjustments: {'dhuhr': 1}),
  'egyptian': LocalPrayerMethod(code: 'egyptian', fajrAngle: 19.5, ishaAngle: 17.5, ishaIntervalMinutes: null, adjustments: {'dhuhr': 1}),
  'karachi': LocalPrayerMethod(code: 'karachi', fajrAngle: 18, ishaAngle: 18, ishaIntervalMinutes: null, adjustments: {'dhuhr': 1}),
  'umm-al-qura': LocalPrayerMethod(code: 'umm-al-qura', fajrAngle: 18.5, ishaAngle: null, ishaIntervalMinutes: 90, adjustments: {}),
  'dubai': LocalPrayerMethod(code: 'dubai', fajrAngle: 18.2, ishaAngle: 18.2, ishaIntervalMinutes: null, adjustments: {'sunrise': -3, 'dhuhr': 3, 'asr': 3, 'maghrib': 3}),
  'moonsighting-committee': LocalPrayerMethod(code: 'moonsighting-committee', fajrAngle: 18, ishaAngle: 18, ishaIntervalMinutes: null, adjustments: {'dhuhr': 5, 'maghrib': 3}),
  'north-america': LocalPrayerMethod(code: 'north-america', fajrAngle: 15, ishaAngle: 15, ishaIntervalMinutes: null, adjustments: {'dhuhr': 1}),
  'kuwait': LocalPrayerMethod(code: 'kuwait', fajrAngle: 18, ishaAngle: 17.5, ishaIntervalMinutes: null, adjustments: {}),
  'qatar': LocalPrayerMethod(code: 'qatar', fajrAngle: 18, ishaAngle: null, ishaIntervalMinutes: 90, adjustments: {}),
};

void main() {
  tz_data.initializeTimeZones();
  const engine = LocalPrayerEngine();
  final cases = <Map<String, Object?>>[
    {'id': 'makkah-umm-al-qura', 'lat': 21.4225, 'lng': 39.8262, 'tz': 'Asia/Riyadh', 'method': 'umm-al-qura', 'month': '2026-10'},
    {'id': 'moscow-mwl-hanafi', 'lat': 55.7558, 'lng': 37.6173, 'tz': 'Europe/Moscow', 'method': 'muslim-world-league', 'month': '2026-06', 'hanafi': true},
    {'id': 'kazan-mwl-seventh', 'lat': 55.7887, 'lng': 49.1221, 'tz': 'Europe/Moscow', 'method': 'muslim-world-league', 'month': '2026-06', 'rule': 'seventh_of_night'},
    {'id': 'kazan-mwl-twilight', 'lat': 55.7887, 'lng': 49.1221, 'tz': 'Europe/Moscow', 'method': 'muslim-world-league', 'month': '2026-06', 'rule': 'twilight_angle'},
    {'id': 'tashkent-egyptian', 'lat': 41.2995, 'lng': 69.2401, 'tz': 'Asia/Tashkent', 'method': 'egyptian', 'month': '2026-12'},
    {'id': 'istanbul-karachi-dst', 'lat': 41.0082, 'lng': 28.9784, 'tz': 'Europe/Istanbul', 'method': 'karachi', 'month': '2026-03'},
    {'id': 'london-moonsighting-dst', 'lat': 51.5074, 'lng': -0.1278, 'tz': 'Europe/London', 'method': 'moonsighting-committee', 'month': '2026-10'},
    {'id': 'oslo-moonsighting', 'lat': 59.9139, 'lng': 10.7522, 'tz': 'Europe/Oslo', 'method': 'moonsighting-committee', 'month': '2026-06'},
    {'id': 'newyork-isna-adjusted', 'lat': 40.7128, 'lng': -74.006, 'tz': 'America/New_York', 'method': 'north-america', 'month': '2026-11', 'adjustments': {'fajr': -3, 'isha': 4}},
    {'id': 'dubai-dubai', 'lat': 25.2048, 'lng': 55.2708, 'tz': 'Asia/Dubai', 'method': 'dubai', 'month': '2026-02'},
    {'id': 'doha-qatar', 'lat': 25.2854, 'lng': 51.531, 'tz': 'Asia/Qatar', 'method': 'qatar', 'month': '2026-09'},
    {'id': 'kuwait-kuwait-leap', 'lat': 29.3759, 'lng': 47.9774, 'tz': 'Asia/Kuwait', 'method': 'kuwait', 'month': '2028-02'},
    {'id': 'sydney-mwl-south', 'lat': -33.8688, 'lng': 151.2093, 'tz': 'Australia/Sydney', 'method': 'moonsighting-committee', 'month': '2026-10'},
    {'id': 'tromso-aqrab-balad', 'lat': 69.6492, 'lng': 18.9553, 'tz': 'Europe/Oslo', 'method': 'muslim-world-league', 'month': '2026-06', 'rule': 'seventh_of_night', 'polar': 'aqrab_balad'},
    {'id': 'tromso-aqrab-yaum', 'lat': 69.6492, 'lng': 18.9553, 'tz': 'Europe/Oslo', 'method': 'muslim-world-league', 'month': '2026-12', 'rule': 'seventh_of_night', 'polar': 'aqrab_yaum'},
    {'id': 'kiritimati-date-line', 'lat': 1.8721, 'lng': -157.4278, 'tz': 'Pacific/Kiritimati', 'method': 'muslim-world-league', 'month': '2026-08'},
  ];
  final output = <Map<String, Object?>>[];
  for (final item in cases) {
    final parts = (item['month']! as String).split('-');
    final month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final location = tz.getLocation(item['tz']! as String);
    final adjustments = Map<String, int>.from(
      (item['adjustments'] as Map?) ?? const <String, int>{},
    );
    final days = <List<int>>[];
    for (final date in prayerCalendarDates(month)) {
      final calc = engine.calculateForCivilDate(
        LocalPrayerInput(
          latitude: item['lat']! as double,
          longitude: item['lng']! as double,
          date: date,
          method: methods[item['method']]!,
          highLatitudeRule: (item['rule'] as String?) ?? 'middle_of_night',
          polarResolution: (item['polar'] as String?) ?? 'unresolved',
          hanafiAsr: item['hanafi'] == true,
          adjustments: adjustments,
        ),
        location,
      );
      days.add(<int>[
        for (final code in const ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'])
          calc.result.timesUtc[code]!.millisecondsSinceEpoch ~/ 60000,
      ]);
    }
    output.add(<String, Object?>{
      ...item,
      'qibla': double.parse(
        qiblaBearing(
          latitude: item['lat']! as double,
          longitude: item['lng']! as double,
        ).toStringAsFixed(6),
      ),
      'utc_minutes': days,
    });
  }
  stdout.write(jsonEncode(<String, Object?>{
    'source': 'clients/iqro_mobile/lib/features/prayer/prayer_local_engine.dart',
    'methods': methods.map((code, m) => MapEntry(code, <String, Object?>{
      'fajr_angle': m.fajrAngle,
      'isha_angle': m.ishaAngle,
      'isha_interval_minutes': m.ishaIntervalMinutes,
      'adjustments': m.adjustments,
    })),
    'cases': output,
  }));
}

// Copied from prayer_repository.dart, which depends on Flutter.
List<DateTime> prayerCalendarDates(DateTime month) {
  final dayCount = DateTime(month.year, month.month + 1, 0).day;
  return List<DateTime>.generate(
    dayCount,
    (index) => DateTime(month.year, month.month, index + 1),
    growable: false,
  );
}
