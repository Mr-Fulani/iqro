import 'dart:math' as math;

class PrayerCity {
  const PrayerCity({
    required this.id,
    required this.names,
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });

  final String id;
  final Map<String, String> names;
  final double latitude;
  final double longitude;
  final String timezone;

  String nameFor(String locale) => names[locale] ?? names['en'] ?? id;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return names.values.any((name) => name.toLowerCase().contains(normalized));
  }
}

const prayerCities = <PrayerCity>[
  PrayerCity(
    id: 'makkah',
    names: <String, String>{
      'ar': 'مكة المكرمة',
      'en': 'Makkah',
      'ru': 'Мекка',
      'tr': 'Mekke',
    },
    latitude: 21.4225,
    longitude: 39.8262,
    timezone: 'Asia/Riyadh',
  ),
  PrayerCity(
    id: 'madinah',
    names: <String, String>{
      'ar': 'المدينة المنورة',
      'en': 'Madinah',
      'ru': 'Медина',
      'tr': 'Medine',
    },
    latitude: 24.4672,
    longitude: 39.6111,
    timezone: 'Asia/Riyadh',
  ),
  PrayerCity(
    id: 'istanbul',
    names: <String, String>{
      'ar': 'إسطنبول',
      'en': 'Istanbul',
      'ru': 'Стамбул',
      'tr': 'İstanbul',
    },
    latitude: 41.0082,
    longitude: 28.9784,
    timezone: 'Europe/Istanbul',
  ),
  PrayerCity(
    id: 'moscow',
    names: <String, String>{
      'ar': 'موسكو',
      'en': 'Moscow',
      'ru': 'Москва',
      'tr': 'Moskova',
    },
    latitude: 55.7558,
    longitude: 37.6173,
    timezone: 'Europe/Moscow',
  ),
  PrayerCity(
    id: 'kazan',
    names: <String, String>{
      'ar': 'قازان',
      'en': 'Kazan',
      'ru': 'Казань',
      'tr': 'Kazan',
    },
    latitude: 55.7887,
    longitude: 49.1221,
    timezone: 'Europe/Moscow',
  ),
  PrayerCity(
    id: 'tashkent',
    names: <String, String>{
      'ar': 'طشقند',
      'en': 'Tashkent',
      'ru': 'Ташкент',
      'tr': 'Taşkent',
    },
    latitude: 41.2995,
    longitude: 69.2401,
    timezone: 'Asia/Tashkent',
  ),
  PrayerCity(
    id: 'london',
    names: <String, String>{
      'ar': 'لندن',
      'en': 'London',
      'ru': 'Лондон',
      'tr': 'Londra',
    },
    latitude: 51.5074,
    longitude: -0.1278,
    timezone: 'Europe/London',
  ),
  PrayerCity(
    id: 'cairo',
    names: <String, String>{
      'ar': 'القاهرة',
      'en': 'Cairo',
      'ru': 'Каир',
      'tr': 'Kahire',
    },
    latitude: 30.0444,
    longitude: 31.2357,
    timezone: 'Africa/Cairo',
  ),
  PrayerCity(
    id: 'dubai',
    names: <String, String>{
      'ar': 'دبي',
      'en': 'Dubai',
      'ru': 'Дубай',
      'tr': 'Dubai',
    },
    latitude: 25.2048,
    longitude: 55.2708,
    timezone: 'Asia/Dubai',
  ),
  PrayerCity(
    id: 'jakarta',
    names: <String, String>{
      'ar': 'جاكرتا',
      'en': 'Jakarta',
      'ru': 'Джакарта',
      'tr': 'Cakarta',
    },
    latitude: -6.2088,
    longitude: 106.8456,
    timezone: 'Asia/Jakarta',
  ),
  PrayerCity(
    id: 'new-york',
    names: <String, String>{
      'ar': 'نيويورك',
      'en': 'New York',
      'ru': 'Нью-Йорк',
      'tr': 'New York',
    },
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
  ),
];

PrayerCity? prayerCityById(String? id) =>
    prayerCities.where((city) => city.id == id).firstOrNull;

double qiblaBearing({required double latitude, required double longitude}) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    throw const FormatException('Invalid coordinates');
  }
  const kaabaLatitude = 21.4225;
  const kaabaLongitude = 39.8262;
  final latitudeRadians = _radians(latitude);
  final kaabaLatitudeRadians = _radians(kaabaLatitude);
  final longitudeDelta = _radians(kaabaLongitude - longitude);
  final y = math.sin(longitudeDelta) * math.cos(kaabaLatitudeRadians);
  final x =
      math.cos(latitudeRadians) * math.sin(kaabaLatitudeRadians) -
      math.sin(latitudeRadians) *
          math.cos(kaabaLatitudeRadians) *
          math.cos(longitudeDelta);
  return (_degrees(math.atan2(y, x)) + 360) % 360;
}

double _radians(double value) => value * math.pi / 180;

double _degrees(double value) => value * 180 / math.pi;
