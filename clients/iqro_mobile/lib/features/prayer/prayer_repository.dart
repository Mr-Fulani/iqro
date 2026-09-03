import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/timezone.dart' as tz;

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'prayer_local_engine.dart';
import 'prayer_location_gateway.dart';

class PrayerSchedule {
  const PrayerSchedule({
    required this.date,
    required this.timezone,
    required this.times,
    required this.timesUtc,
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
    final timesUtc = <String, DateTime>{};
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
        times[code] = _parseWallClock(raw['local'].toString());
        final utc = DateTime.tryParse(raw['utc']?.toString() ?? '');
        if (utc != null) timesUtc[code] = utc.toUtc();
      }
    }
    return PrayerSchedule(
      date: DateTime.parse(json['date']!.toString()),
      timezone: json['timezone']?.toString() ?? '',
      times: times,
      timesUtc: timesUtc,
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
  final Map<String, DateTime> timesUtc;
  final String methodName;
  final List<String> warnings;

  Map<String, Object?> toJson() => <String, Object?>{
    'date': DateFormat('yyyy-MM-dd').format(date),
    'timezone': timezone,
    'method': <String, Object?>{'code': methodName},
    'times': <String, Object?>{
      for (final code in times.keys)
        code: <String, Object?>{
          'local': times[code]!.toIso8601String(),
          'utc': timesUtc[code]?.toUtc().toIso8601String(),
        },
    },
    'warnings': warnings,
  };
}

class PrayerMethod {
  const PrayerMethod({
    required this.id,
    required this.code,
    required this.checksum,
    required this.names,
    required this.highLatitudeRule,
    required this.polarResolution,
    required this.fajrAngle,
    required this.ishaAngle,
    required this.ishaIntervalMinutes,
    required this.adjustments,
    required this.algorithmId,
    required this.algorithmVersion,
    required this.timezoneDatabaseVersion,
    required this.available,
  });

  factory PrayerMethod.fromJson(
    Map<String, Object?> json, {
    String algorithmId = '',
    String algorithmVersion = '',
    String timezoneDatabaseVersion = '',
  }) {
    final names = json['name'] is Map
        ? Map<String, Object?>.from(json['name']! as Map)
        : const <String, Object?>{};
    final highLatitude = json['high_latitude_rules'] is Map
        ? Map<String, Object?>.from(json['high_latitude_rules']! as Map)
        : const <String, Object?>{};
    final polar = json['polar_resolutions'] is Map
        ? Map<String, Object?>.from(json['polar_resolutions']! as Map)
        : const <String, Object?>{};
    final parameters = json['parameters'] is Map
        ? Map<String, Object?>.from(json['parameters']! as Map)
        : const <String, Object?>{};
    final isha = parameters['isha'] is Map
        ? Map<String, Object?>.from(parameters['isha']! as Map)
        : const <String, Object?>{};
    final rawAdjustments = parameters['method_adjustments'] is Map
        ? Map<String, Object?>.from(parameters['method_adjustments']! as Map)
        : const <String, Object?>{};
    return PrayerMethod(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      checksum: json['checksum_sha256']?.toString() ?? '',
      names: names.map((key, value) => MapEntry(key, value.toString())),
      highLatitudeRule:
          highLatitude['default']?.toString() ?? 'middle_of_night',
      polarResolution: polar['default']?.toString() ?? 'unresolved',
      fajrAngle:
          double.tryParse(parameters['fajr_angle']?.toString() ?? '') ?? 0,
      ishaAngle: double.tryParse(isha['angle']?.toString() ?? ''),
      ishaIntervalMinutes: (isha['interval_minutes'] as num?)?.toInt(),
      adjustments: <String, int>{
        for (final code in _prayerCodes)
          code: (rawAdjustments[code] as num?)?.toInt() ?? 0,
      },
      algorithmId: algorithmId,
      algorithmVersion: algorithmVersion,
      timezoneDatabaseVersion: timezoneDatabaseVersion,
      available: json['available'] != false,
    );
  }

  final String id;
  final String code;
  final String checksum;
  final Map<String, String> names;
  final String highLatitudeRule;
  final String polarResolution;
  final double fajrAngle;
  final double? ishaAngle;
  final int? ishaIntervalMinutes;
  final Map<String, int> adjustments;
  final String algorithmId;
  final String algorithmVersion;
  final String timezoneDatabaseVersion;
  final bool available;

  String nameFor(String locale) => names[locale] ?? names['en'] ?? code;

  bool get supportsLocalCalculation =>
      available &&
      algorithmId == localPrayerEngineId &&
      algorithmVersion == localPrayerEngineVersion &&
      fajrAngle > 0 &&
      ((ishaAngle != null) != (ishaIntervalMinutes != null));

  LocalPrayerMethod get localMethod => LocalPrayerMethod(
    code: code,
    fajrAngle: fajrAngle,
    ishaAngle: ishaAngle,
    ishaIntervalMinutes: ishaIntervalMinutes,
    adjustments: adjustments,
  );
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
  PrayerRepository({
    required ApiClient api,
    required LocalDatabase database,
    PrayerLocationGateway locationGateway = const DevicePrayerLocationGateway(),
  }) : _api = api,
       _database = database,
       _locationGateway = locationGateway;

  final ApiClient _api;
  final LocalDatabase _database;
  final PrayerLocationGateway _locationGateway;
  final LocalPrayerEngine _localEngine = const LocalPrayerEngine();

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
      return _parseMethods(payload);
    } on Object {
      if (cached == null) rethrow;
      return _parseMethods(cached.value);
    }
  }

  Future<String?> selectedMethodCode({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return (await _database.readState(
      'prayer_method',
      accountScope: scope,
    ))?['code']?.toString();
  }

  Future<void> selectMethod(
    String code, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    await _database.writeState('prayer_method', <String, Object?>{
      'code': code,
    }, accountScope: scope);
  }

  Future<PrayerMethod?> selectedMethod() async {
    final scope = await _database.captureAccount();
    return _selectedMethodFor(scope);
  }

  Future<PrayerMethod?> _selectedMethodFor(AccountScopeSnapshot scope) async {
    final available = await methods();
    _database.ensureCurrent(scope);
    final code = (await _database.readState(
      'prayer_method',
      accountScope: scope,
    ))?['code']?.toString();
    return available.where((item) => item.code == code).firstOrNull;
  }

  Future<PrayerLocation?> storedLocation({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _storedLocationFor(scope);
  }

  Future<PrayerLocation?> _storedLocationFor(AccountScopeSnapshot scope) async {
    final value = await _database.readState(
      'prayer_location',
      accountScope: scope,
    );
    return value == null ? null : PrayerLocation.fromJson(value);
  }

  Future<PrayerSchedule?> cachedToday({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final data = await _database.readState(
      'prayer_schedule_today',
      accountScope: scope,
    );
    if (data == null) return null;
    final schedule = PrayerSchedule.fromJson(data);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return DateFormat('yyyy-MM-dd').format(schedule.date) == today
        ? schedule
        : null;
  }

  Future<PrayerSchedule> calculateForCurrentLocation({
    required PrayerMethod method,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final deviceLocation = await acquirePrayerDeviceLocation(_locationGateway);
    _database.ensureCurrent(scope);
    final location = PrayerLocation(
      latitude: deviceLocation.latitude,
      longitude: deviceLocation.longitude,
      timezone: deviceLocation.timezone,
    );
    await _database.writeState(
      'prayer_location',
      location.toJson(),
      accountScope: scope,
    );
    final schedule = await _calculateLocallyForDate(
      method: method,
      location: location,
      date: DateTime.now(),
      scope: scope,
    );
    await _saveProfile(method, scope);
    return schedule;
  }

  Future<PrayerSchedule> calculateForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _calculateForDate(
      method: method,
      location: location,
      date: date,
      scope: scope,
    );
  }

  Future<PrayerSchedule> _calculateForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    required AccountScopeSnapshot scope,
  }) async {
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final cacheKey =
        'prayer:schedule:$dateValue:${method.checksum}:${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}:${location.timezone}';
    final cached = await _database.readAccountCache(
      cacheKey,
      accountScope: scope,
    );
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
        await _database.writeAccountCache(
          cacheKey,
          result,
          maxAge: const Duration(hours: 18),
          accountScope: scope,
        );
      } on ApiException catch (error) {
        if (!error.isOffline) rethrow;
        if (cached != null) {
          result = jsonMap(cached.value);
        } else {
          return _calculateLocallyForDate(
            method: method,
            location: location,
            date: date,
            scope: scope,
          );
        }
      }
    }
    final schedule = PrayerSchedule.fromJson(result);
    if (DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateValue) {
      await _database.writeState(
        'prayer_schedule_today',
        result,
        accountScope: scope,
      );
    }
    return schedule;
  }

  Future<List<PrayerSchedule>> calculateHorizon({
    int days = 8,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final location = await _storedLocationFor(scope);
    final method = await _selectedMethodFor(scope);
    if (location == null ||
        method == null ||
        !method.supportsLocalCalculation) {
      return const <PrayerSchedule>[];
    }
    final today = DateTime.now();
    final schedules = <PrayerSchedule>[];
    for (var offset = 0; offset < days; offset++) {
      final date = DateTime(today.year, today.month, today.day + offset);
      schedules.add(
        await _calculateLocallyForDate(
          method: method,
          location: location,
          date: date,
          scope: scope,
        ),
      );
    }
    return schedules;
  }

  Future<PrayerSchedule> calculateLocallyForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _calculateLocallyForDate(
      method: method,
      location: location,
      date: date,
      scope: scope,
    );
  }

  Future<PrayerSchedule> _calculateLocallyForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    required AccountScopeSnapshot scope,
  }) async {
    _database.ensureCurrent(scope);
    if (!method.supportsLocalCalculation) {
      throw const LocalPrayerCalculationUnavailable(
        'backend_engine_version_unsupported',
      );
    }
    late final tz.Location timezone;
    try {
      timezone = tz.getLocation(location.timezone);
    } on Object {
      throw const LocalPrayerCalculationUnavailable('timezone_unavailable');
    }
    final calculation = _localEngine.calculateForCivilDate(
      LocalPrayerInput(
        latitude: location.latitude,
        longitude: location.longitude,
        date: date,
        method: method.localMethod,
        highLatitudeRule: method.highLatitudeRule,
        polarResolution: method.polarResolution,
      ),
      timezone,
    );
    final times = <String, DateTime>{};
    for (final entry in calculation.result.timesUtc.entries) {
      final local = tz.TZDateTime.from(entry.value, timezone);
      times[entry.key] = DateTime(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
      );
    }
    final warnings = <String>[
      'local_calculation',
      if (calculation.result.fallback.applied) 'polar_resolution_applied',
    ];
    final schedule = PrayerSchedule(
      date: DateTime(date.year, date.month, date.day),
      timezone: location.timezone,
      times: times,
      timesUtc: calculation.result.timesUtc,
      methodName: method.code,
      warnings: warnings,
    );
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final cacheKey =
        'prayer:schedule:$dateValue:${method.checksum}:${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}:${location.timezone}';
    await _database.writeAccountCache(
      cacheKey,
      schedule.toJson(),
      maxAge: const Duration(days: 35),
      accountScope: scope,
    );
    if (DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateValue) {
      await _database.writeState(
        'prayer_schedule_today',
        schedule.toJson(),
        accountScope: scope,
      );
    }
    return schedule;
  }

  Future<void> _saveProfile(
    PrayerMethod method,
    AccountScopeSnapshot scope,
  ) async {
    var revision = 0;
    try {
      final current = jsonMap(
        await _api.get('/me/prayer-profile', accountScope: scope),
      );
      _database.ensureCurrent(scope);
      revision = (current['revision'] as num?)?.toInt() ?? 0;
    } on ApiException catch (error) {
      if (error.code == 'account_scope_changed') rethrow;
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
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
  }
}

const _prayerCodes = <String>[
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

List<PrayerMethod> _parseMethods(Object? payload) {
  final catalog = jsonMap(payload);
  final algorithm = jsonMap(catalog['algorithm']);
  final methods =
      (catalog['methods'] as List?)
          ?.whereType<Map>()
          .map(
            (item) => PrayerMethod.fromJson(
              Map<String, Object?>.from(item),
              algorithmId: algorithm['id']?.toString() ?? '',
              algorithmVersion: algorithm['version']?.toString() ?? '',
              timezoneDatabaseVersion:
                  catalog['timezone_database_version']?.toString() ?? '',
            ),
          )
          .where(
            (method) =>
                method.id.isNotEmpty &&
                method.code.isNotEmpty &&
                method.checksum.isNotEmpty &&
                method.available,
          )
          .toList(growable: false) ??
      const <PrayerMethod>[];
  return methods;
}

DateTime _parseWallClock(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (match == null) return DateTime.parse(value).toLocal();
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
