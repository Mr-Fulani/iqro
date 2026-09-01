import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';

class PrayerSchedule {
  const PrayerSchedule({
    required this.date,
    required this.timezone,
    required this.times,
    required this.methodName,
    required this.warnings,
  });

  factory PrayerSchedule.fromJson(Map<String, Object?> json) {
    final method = json['method'] is Map
        ? Map<String, Object?>.from(json['method']! as Map)
        : const <String, Object?>{};
    final rawTimes = json['times'] is Map
        ? Map<String, Object?>.from(json['times']! as Map)
        : const <String, Object?>{};
    final times = <String, DateTime>{};
    for (final code in const <String>[
      'fajr',
      'sunrise',
      'dhuhr',
      'asr',
      'maghrib',
      'isha',
    ]) {
      final raw = rawTimes[code];
      if (raw is Map && raw['local'] != null) {
        times[code] = DateTime.parse(raw['local'].toString());
      }
    }
    return PrayerSchedule(
      date: DateTime.parse(json['date']!.toString()),
      timezone: json['timezone']?.toString() ?? '',
      times: times,
      methodName: method['code']?.toString() ?? '',
      warnings:
          (json['warnings'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[],
    );
  }

  final DateTime date;
  final String timezone;
  final Map<String, DateTime> times;
  final String methodName;
  final List<String> warnings;
}

class PrayerMethod {
  const PrayerMethod({
    required this.id,
    required this.code,
    required this.checksum,
    required this.names,
    required this.highLatitudeRule,
    required this.polarResolution,
  });

  factory PrayerMethod.fromJson(Map<String, Object?> json) {
    final names = json['name'] is Map
        ? Map<String, Object?>.from(json['name']! as Map)
        : const <String, Object?>{};
    final highLatitude = json['high_latitude_rules'] is Map
        ? Map<String, Object?>.from(json['high_latitude_rules']! as Map)
        : const <String, Object?>{};
    final polar = json['polar_resolutions'] is Map
        ? Map<String, Object?>.from(json['polar_resolutions']! as Map)
        : const <String, Object?>{};
    return PrayerMethod(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      checksum: json['checksum_sha256']?.toString() ?? '',
      names: names.map((key, value) => MapEntry(key, value.toString())),
      highLatitudeRule:
          highLatitude['default']?.toString() ?? 'middle_of_night',
      polarResolution: polar['default']?.toString() ?? 'unresolved',
    );
  }

  final String id;
  final String code;
  final String checksum;
  final Map<String, String> names;
  final String highLatitudeRule;
  final String polarResolution;

  String nameFor(String locale) => names[locale] ?? names['en'] ?? code;
}

class PrayerLocation {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });

  final double latitude;
  final double longitude;
  final String timezone;

  factory PrayerLocation.fromJson(Map<String, Object?> json) => PrayerLocation(
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    timezone: json['timezone']?.toString() ?? 'UTC',
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'latitude': latitude,
    'longitude': longitude,
    'timezone': timezone,
  };
}

class PrayerRepository {
  PrayerRepository({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;

  Future<List<PrayerMethod>> methods() async {
    const key = 'prayer:methods';
    final cached = await _database.readCache(key);
    try {
      final payload = cached?.isFresh == true
          ? cached!.value
          : await _api.get('/prayer/methods', public: true);
      if (cached?.isFresh != true) {
        await _database.writeCache(
          key,
          payload,
          maxAge: const Duration(days: 7),
        );
      }
      final catalog = jsonMap(payload);
      return (catalog['methods'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    PrayerMethod.fromJson(Map<String, Object?>.from(item)),
              )
              .where(
                (method) =>
                    method.id.isNotEmpty &&
                    method.code.isNotEmpty &&
                    method.checksum.isNotEmpty,
              )
              .toList(growable: false) ??
          const <PrayerMethod>[];
    } on Object {
      if (cached == null) rethrow;
      final catalog = jsonMap(cached.value);
      return (catalog['methods'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    PrayerMethod.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false) ??
          const <PrayerMethod>[];
    }
  }

  Future<String?> selectedMethodCode() async =>
      (await _database.readState('prayer_method'))?['code']?.toString();

  Future<void> selectMethod(String code) =>
      _database.writeState('prayer_method', <String, Object?>{'code': code});

  Future<PrayerMethod?> selectedMethod() async {
    final available = await methods();
    final code = await selectedMethodCode();
    return available.where((item) => item.code == code).firstOrNull;
  }

  Future<PrayerLocation?> storedLocation() async {
    final value = await _database.readState('prayer_location');
    return value == null ? null : PrayerLocation.fromJson(value);
  }

  Future<PrayerSchedule?> cachedToday() async {
    final data = await _database.readState('prayer_schedule_today');
    if (data == null) return null;
    final schedule = PrayerSchedule.fromJson(data);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return DateFormat('yyyy-MM-dd').format(schedule.date) == today
        ? schedule
        : null;
  }

  Future<PrayerSchedule> calculateForCurrentLocation({
    required PrayerMethod method,
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const ApiException(
        message: 'Location services are disabled',
        code: 'location_disabled',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ApiException(
        message: 'Location permission was denied',
        code: 'location_denied',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    final timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    final location = PrayerLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      timezone: timezone,
    );
    await _database.writeState('prayer_location', location.toJson());
    final schedule = await calculateForDate(
      method: method,
      location: location,
      date: DateTime.now(),
    );
    await _saveProfile(method);
    return schedule;
  }

  Future<PrayerSchedule> calculateForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
  }) async {
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final cacheKey =
        'prayer:schedule:$dateValue:${method.checksum}:${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}:${location.timezone}';
    final cached = await _database.readCache(cacheKey);
    Map<String, Object?> result;
    if (cached?.isFresh == true) {
      result = jsonMap(cached!.value);
    } else {
      try {
        result = jsonMap(
          await _api.post(
            '/prayer/calculate',
            public: true,
            data: <String, Object?>{
              'date': dateValue,
              'timezone': location.timezone,
              'location': <String, Object?>{
                'latitude': location.latitude.toStringAsFixed(6),
                'longitude': location.longitude.toStringAsFixed(6),
              },
              'method_config_id': method.id,
              'method_checksum_sha256': method.checksum,
              'asr_method': 'standard',
              'high_latitude_rule': method.highLatitudeRule,
              'polar_resolution': method.polarResolution,
              'adjustments': const <String, int>{
                'fajr': 0,
                'sunrise': 0,
                'dhuhr': 0,
                'asr': 0,
                'maghrib': 0,
                'isha': 0,
              },
            },
          ),
        );
        await _database.writeCache(
          cacheKey,
          result,
          maxAge: const Duration(hours: 18),
        );
      } on Object {
        if (cached == null) rethrow;
        result = jsonMap(cached.value);
      }
    }
    final schedule = PrayerSchedule.fromJson(result);
    if (DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateValue) {
      await _database.writeState('prayer_schedule_today', result);
    }
    return schedule;
  }

  Future<List<PrayerSchedule>> calculateHorizon({int days = 8}) async {
    final location = await storedLocation();
    final method = await selectedMethod();
    if (location == null || method == null) return const <PrayerSchedule>[];
    final today = DateTime.now();
    final schedules = <PrayerSchedule>[];
    for (var offset = 0; offset < days; offset++) {
      schedules.add(
        await calculateForDate(
          method: method,
          location: location,
          date: DateTime(today.year, today.month, today.day + offset),
        ),
      );
    }
    return schedules;
  }

  Future<void> _saveProfile(PrayerMethod method) async {
    var revision = 0;
    try {
      final current = jsonMap(await _api.get('/me/prayer-profile'));
      revision = (current['revision'] as num?)?.toInt() ?? 0;
    } on ApiException catch (error) {
      if (error.statusCode != 404 && !error.isOffline) rethrow;
      if (error.isOffline) return;
    }
    await _api.put(
      '/me/prayer-profile',
      data: <String, Object?>{
        'base_revision': revision,
        'method_config_id': method.id,
        'method_checksum_sha256': method.checksum,
        'asr_method': 'standard',
        'high_latitude_rule': method.highLatitudeRule,
        'polar_resolution': method.polarResolution,
        'adjustments': const <String, int>{
          'fajr': 0,
          'sunrise': 0,
          'dhuhr': 0,
          'asr': 0,
          'maghrib': 0,
          'isha': 0,
        },
        'timezone_mode': 'device_local',
        'client_updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
