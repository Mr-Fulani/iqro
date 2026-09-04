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
    required this.supportedHighLatitudeRules,
    required this.polarResolution,
    required this.supportedPolarResolutions,
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
      supportedHighLatitudeRules:
          (highLatitude['supported'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>['middle_of_night'],
      polarResolution: polar['default']?.toString() ?? 'unresolved',
      supportedPolarResolutions:
          (polar['supported'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>['unresolved'],
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
  final List<String> supportedHighLatitudeRules;
  final String polarResolution;
  final List<String> supportedPolarResolutions;
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

class PrayerPreferences {
  const PrayerPreferences({
    required this.asrMethod,
    required this.highLatitudeRule,
    required this.polarResolution,
    required this.adjustments,
    required this.timezoneMode,
    required this.revision,
    this.fixedTimezone,
    this.syncPending = false,
  });

  factory PrayerPreferences.defaultsFor(PrayerMethod method) =>
      PrayerPreferences(
        asrMethod: 'standard',
        highLatitudeRule: method.highLatitudeRule,
        polarResolution: method.polarResolution,
        adjustments: const <String, int>{
          'fajr': 0,
          'sunrise': 0,
          'dhuhr': 0,
          'asr': 0,
          'maghrib': 0,
          'isha': 0,
        },
        timezoneMode: 'device_local',
        revision: 0,
      );

  factory PrayerPreferences.fromJson(
    Map<String, Object?> json, {
    required PrayerMethod method,
  }) {
    final rawAdjustments = json['adjustments'] is Map
        ? Map<String, Object?>.from(json['adjustments']! as Map)
        : const <String, Object?>{};
    final defaults = PrayerPreferences.defaultsFor(method);
    final asrMethod = json['asr_method']?.toString();
    final highLatitudeRule = json['high_latitude_rule']?.toString();
    final polarResolution = json['polar_resolution']?.toString();
    final timezoneMode = json['timezone_mode']?.toString();
    final fixedTimezone = json['fixed_timezone']?.toString();
    return PrayerPreferences(
      asrMethod: asrMethod == 'hanafi' ? 'hanafi' : 'standard',
      highLatitudeRule:
          method.supportedHighLatitudeRules.contains(highLatitudeRule)
          ? highLatitudeRule!
          : defaults.highLatitudeRule,
      polarResolution:
          method.supportedPolarResolutions.contains(polarResolution)
          ? polarResolution!
          : defaults.polarResolution,
      adjustments: <String, int>{
        for (final code in _prayerCodes)
          code: ((rawAdjustments[code] as num?)?.toInt() ?? 0).clamp(-120, 120),
      },
      timezoneMode: timezoneMode == 'fixed' ? 'fixed' : 'device_local',
      fixedTimezone: fixedTimezone == null || fixedTimezone.isEmpty
          ? null
          : fixedTimezone,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      syncPending: json['sync_pending'] == true,
    );
  }

  final String asrMethod;
  final String highLatitudeRule;
  final String polarResolution;
  final Map<String, int> adjustments;
  final String timezoneMode;
  final String? fixedTimezone;
  final int revision;
  final bool syncPending;

  bool get hanafiAsr => asrMethod == 'hanafi';

  PrayerPreferences copyWith({
    String? asrMethod,
    String? highLatitudeRule,
    String? polarResolution,
    Map<String, int>? adjustments,
    String? timezoneMode,
    String? fixedTimezone,
    bool clearFixedTimezone = false,
    int? revision,
    bool? syncPending,
  }) => PrayerPreferences(
    asrMethod: asrMethod ?? this.asrMethod,
    highLatitudeRule: highLatitudeRule ?? this.highLatitudeRule,
    polarResolution: polarResolution ?? this.polarResolution,
    adjustments: Map<String, int>.unmodifiable(adjustments ?? this.adjustments),
    timezoneMode: timezoneMode ?? this.timezoneMode,
    fixedTimezone: clearFixedTimezone
        ? null
        : (fixedTimezone ?? this.fixedTimezone),
    revision: revision ?? this.revision,
    syncPending: syncPending ?? this.syncPending,
  );

  PrayerPreferences forMethod(PrayerMethod method) => copyWith(
    highLatitudeRule:
        method.supportedHighLatitudeRules.contains(highLatitudeRule)
        ? highLatitudeRule
        : method.highLatitudeRule,
    polarResolution: method.supportedPolarResolutions.contains(polarResolution)
        ? polarResolution
        : method.polarResolution,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'asr_method': asrMethod,
    'high_latitude_rule': highLatitudeRule,
    'polar_resolution': polarResolution,
    'adjustments': adjustments,
    'timezone_mode': timezoneMode,
    if (timezoneMode == 'fixed' && fixedTimezone != null)
      'fixed_timezone': fixedTimezone,
    'revision': revision,
    'sync_pending': syncPending,
  };
}

class PrayerProfileSelection {
  const PrayerProfileSelection({
    required this.method,
    required this.preferences,
    required this.offline,
  });

  final PrayerMethod method;
  final PrayerPreferences preferences;
  final bool offline;
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

  Future<PrayerPreferences> storedPreferences({
    required PrayerMethod method,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _storedPreferencesFor(method, scope);
  }

  Future<PrayerPreferences> _storedPreferencesFor(
    PrayerMethod method,
    AccountScopeSnapshot scope,
  ) async {
    final raw = await _database.readState(
      'prayer_preferences',
      accountScope: scope,
    );
    return raw == null
        ? PrayerPreferences.defaultsFor(method)
        : PrayerPreferences.fromJson(raw, method: method).forMethod(method);
  }

  Future<PrayerProfileSelection> loadProfile({
    required List<PrayerMethod> methods,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (methods.isEmpty) throw StateError('Prayer method catalog is empty');
    final scope = accountScope ?? await _database.captureAccount();
    final selectedCode = await selectedMethodCode(accountScope: scope);
    var method =
        methods.where((item) => item.code == selectedCode).firstOrNull ??
        methods.first;
    var preferences = await _storedPreferencesFor(method, scope);
    try {
      if (preferences.syncPending) {
        return _saveProfile(
          method: method,
          preferences: preferences,
          scope: scope,
        );
      }
      final response = jsonMap(
        await _api.get('/me/prayer-profile', accountScope: scope),
      );
      _database.ensureCurrent(scope);
      final remoteMethod = jsonMap(response['method_config']);
      final remoteCode = remoteMethod['code']?.toString();
      method =
          methods.where((item) => item.code == remoteCode).firstOrNull ??
          method;
      preferences = PrayerPreferences.fromJson(
        response,
        method: method,
      ).copyWith(syncPending: false);
      await _persistProfile(method, preferences, scope);
      return PrayerProfileSelection(
        method: method,
        preferences: preferences,
        offline: false,
      );
    } on ApiException catch (error) {
      if (error.code == 'account_scope_changed') rethrow;
      if (error.statusCode != 404 && !error.isOffline) rethrow;
      return PrayerProfileSelection(
        method: method,
        preferences: preferences,
        offline: error.isOffline,
      );
    }
  }

  Future<PrayerProfileSelection> saveProfile({
    required PrayerMethod method,
    required PrayerPreferences preferences,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final pending = preferences.forMethod(method).copyWith(syncPending: true);
    await _persistProfile(method, pending, scope);
    try {
      return await _saveProfile(
        method: method,
        preferences: pending,
        scope: scope,
      );
    } on ApiException catch (error) {
      if (error.code == 'account_scope_changed') rethrow;
      if (!error.isOffline) rethrow;
      return PrayerProfileSelection(
        method: method,
        preferences: pending,
        offline: true,
      );
    }
  }

  Future<void> _persistProfile(
    PrayerMethod method,
    PrayerPreferences preferences,
    AccountScopeSnapshot scope,
  ) async {
    await _database.writeState('prayer_method', <String, Object?>{
      'code': method.code,
    }, accountScope: scope);
    await _database.writeState(
      'prayer_preferences',
      preferences.toJson(),
      accountScope: scope,
    );
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
    final preferences = await _storedPreferencesFor(method, scope);
    final schedule = await _calculateLocallyForDate(
      method: method,
      location: location,
      date: DateTime.now(),
      preferences: preferences,
      scope: scope,
    );
    return schedule;
  }

  Future<PrayerSchedule?> calculateForStoredLocation({
    required PrayerMethod method,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final location = await _storedLocationFor(scope);
    if (location == null) return null;
    final preferences = await _storedPreferencesFor(method, scope);
    return _calculateForDate(
      method: method,
      location: location,
      date: DateTime.now(),
      preferences: preferences,
      scope: scope,
    );
  }

  Future<PrayerSchedule> calculateForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    PrayerPreferences? preferences,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _calculateForDate(
      method: method,
      location: location,
      date: date,
      preferences: preferences ?? await _storedPreferencesFor(method, scope),
      scope: scope,
    );
  }

  Future<PrayerSchedule> _calculateForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    required PrayerPreferences preferences,
    required AccountScopeSnapshot scope,
  }) async {
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final cacheKey =
        'prayer:schedule:$dateValue:${method.checksum}:${_preferenceCacheKey(preferences)}:${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}:${location.timezone}';
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
              'asr_method': preferences.asrMethod,
              'high_latitude_rule': preferences.highLatitudeRule,
              'polar_resolution': preferences.polarResolution,
              'adjustments': preferences.adjustments,
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
            preferences: preferences,
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
    final preferences = await _storedPreferencesFor(method, scope);
    final schedules = <PrayerSchedule>[];
    for (var offset = 0; offset < days; offset++) {
      final date = DateTime(today.year, today.month, today.day + offset);
      schedules.add(
        await _calculateLocallyForDate(
          method: method,
          location: location,
          date: date,
          preferences: preferences,
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
    PrayerPreferences? preferences,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _calculateLocallyForDate(
      method: method,
      location: location,
      date: date,
      preferences: preferences ?? await _storedPreferencesFor(method, scope),
      scope: scope,
    );
  }

  Future<PrayerSchedule> _calculateLocallyForDate({
    required PrayerMethod method,
    required PrayerLocation location,
    required DateTime date,
    required PrayerPreferences preferences,
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
        highLatitudeRule: preferences.highLatitudeRule,
        polarResolution: preferences.polarResolution,
        hanafiAsr: preferences.hanafiAsr,
        adjustments: preferences.adjustments,
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
        'prayer:schedule:$dateValue:${method.checksum}:${_preferenceCacheKey(preferences)}:${location.latitude.toStringAsFixed(4)}:${location.longitude.toStringAsFixed(4)}:${location.timezone}';
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

  Future<PrayerProfileSelection> _saveProfile({
    required PrayerMethod method,
    required PrayerPreferences preferences,
    required AccountScopeSnapshot scope,
  }) async {
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
      if (error.isOffline) rethrow;
    }
    final result = jsonMap(
      await _api.put(
        '/me/prayer-profile',
        data: <String, Object?>{
          'base_revision': revision,
          'method_config_id': method.id,
          'method_checksum_sha256': method.checksum,
          'asr_method': preferences.asrMethod,
          'high_latitude_rule': preferences.highLatitudeRule,
          'polar_resolution': preferences.polarResolution,
          'adjustments': preferences.adjustments,
          'timezone_mode': preferences.timezoneMode,
          if (preferences.timezoneMode == 'fixed')
            'fixed_timezone': preferences.fixedTimezone,
          'client_updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        accountScope: scope,
      ),
    );
    _database.ensureCurrent(scope);
    final saved = PrayerPreferences.fromJson(
      result,
      method: method,
    ).copyWith(syncPending: false);
    await _persistProfile(method, saved, scope);
    return PrayerProfileSelection(
      method: method,
      preferences: saved,
      offline: false,
    );
  }
}

String _preferenceCacheKey(PrayerPreferences value) => <String>[
  value.asrMethod,
  value.highLatitudeRule,
  value.polarResolution,
  for (final code in _prayerCodes) '${value.adjustments[code] ?? 0}',
].join(':');

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
