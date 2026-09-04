import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('curated city fallback has unique IDs and valid timezones', () {
    expect(
      prayerCities.map((city) => city.id).toSet(),
      hasLength(prayerCities.length),
    );
    for (final city in prayerCities) {
      expect(city.names.keys, containsAll(<String>['ar', 'en', 'ru', 'tr']));
      expect(() => tz.getLocation(city.timezone), returnsNormally);
    }
  });

  test('city search matches every localized name', () {
    final istanbul = prayerCityById('istanbul')!;

    expect(istanbul.matches('istan'), isTrue);
    expect(istanbul.matches('стам'), isTrue);
    expect(istanbul.matches('إسطن'), isTrue);
    expect(istanbul.matches('unknown'), isFalse);
  });

  test('Qibla bearing is a normalized geographic bearing', () {
    final london = qiblaBearing(latitude: 51.5074, longitude: -0.1278);
    final newYork = qiblaBearing(latitude: 40.7128, longitude: -74.006);

    expect(london, closeTo(118.99, .15));
    expect(newYork, closeTo(58.48, .15));
    expect(london, inInclusiveRange(0, 360));
    expect(
      () => qiblaBearing(latitude: 100, longitude: 0),
      throwsFormatException,
    );
  });
}
