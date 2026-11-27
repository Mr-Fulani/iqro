import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/prayer/prayer_local_engine.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:timezone/timezone.dart' as tz;

// Clock changes of 2026 that the app's zone database (IANA 2026e, package
// timezone 0.11.2) knows and the former one (2025c) did not: Morocco and
// Western Sahara stay on +00 from 2026-09-20; British Columbia, Alberta,
// Manitoba and Inuvik keep summer time from 2026-11-01; Moldova changes its
// clocks at 01:00 UTC, as the EU does. The database is the one the app loads
// at startup, through the reminders gateway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
          call,
        ) async {
          // What a phone in Casablanca reports.
          if (call.method == 'getLocalTimezone') return 'Africa/Casablanca';
          return null;
        });
    await NotificationGateway(
      database: _MemoryDatabase(),
      initializeForTesting: () async {},
    ).initialize();
  });

  test('zones keep the offsets their countries chose in 2026', () {
    final december = DateTime.utc(2026, 12, 15, 12);
    // Zone, moment, offset. The 2025c offset is in the comment.
    final cases = <(String, DateTime, Duration)>[
      ('Africa/Casablanca', december, Duration.zero), // +01
      ('Africa/El_Aaiun', december, Duration.zero), // +01
      ('America/Vancouver', december, const Duration(hours: -7)), // -08
      ('America/Edmonton', december, const Duration(hours: -6)), // -07
      ('America/Winnipeg', december, const Duration(hours: -5)), // -06
      ('America/Inuvik', december, const Duration(hours: -6)), // -07
      // Half an hour before the EU spring change of 2027.
      (
        'Europe/Chisinau',
        DateTime.utc(2027, 3, 28, 0, 30),
        const Duration(hours: 2), // +03
      ),
    ];
    for (final (zone, moment, offset) in cases) {
      expect(
        tz.TZDateTime.from(moment, tz.getLocation(zone)).timeZoneOffset,
        offset,
        reason: '$zone at $moment',
      );
    }
  });

  for (final place in _places) {
    test('prayer times in ${place.name} follow its clock', () async {
      final repository = PrayerRepository(
        api: _MethodsApi(),
        database: _MemoryDatabase(),
      );

      final schedule = await repository.calculateLocallyForDate(
        method: (await repository.methods()).single,
        location: PrayerLocation(
          latitude: place.latitude,
          longitude: place.longitude,
          timezone: place.timezone,
        ),
        date: DateTime(2026, 12, 15),
      );

      expect(schedule.times, hasLength(6));
      for (final code in schedule.times.keys) {
        // The screen, the widgets and the month show these times, and Android
        // rings prayer reminders at them.
        expect(
          schedule.times[code],
          _wallClock(schedule.timesUtc[code]!.add(place.offset)),
          reason: code,
        );
      }
    });
  }

  test('a weekly reminder at 20:00 in Casablanca rings at 20:00 UTC', () {
    expect(tz.local.name, 'Africa/Casablanca');

    final monday = nextWeeklyOccurrence(
      location: tz.local,
      weekday: DateTime.monday,
      hour: 20,
      minute: 0,
      now: tz.TZDateTime(tz.local, 2026, 11, 30, 9),
    );

    // iPhone rings at this moment.
    expect(monday.toUtc(), DateTime.utc(2026, 11, 30, 20));
  });
}

class _Place {
  const _Place(
    this.name,
    this.timezone,
    this.latitude,
    this.longitude,
    this.offset,
  );

  final String name;
  final String timezone;
  final double latitude;
  final double longitude;
  final Duration offset;
}

const _places = <_Place>[
  _Place('Casablanca', 'Africa/Casablanca', 33.58831, -7.61138, Duration.zero),
  _Place(
    'Vancouver',
    'America/Vancouver',
    49.24966,
    -123.11934,
    Duration(hours: -7),
  ),
  _Place(
    'Calgary',
    'America/Edmonton',
    51.05011,
    -114.08529,
    Duration(hours: -6),
  ),
  _Place(
    'Winnipeg',
    'America/Winnipeg',
    49.8844,
    -97.14704,
    Duration(hours: -5),
  ),
];

DateTime _wallClock(DateTime utc) =>
    DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);

final _catalog = <String, Object?>{
  'algorithm': <String, Object?>{
    'id': localPrayerEngineId,
    'version': localPrayerEngineVersion,
  },
  'timezone_database_version': '2026.3',
  'methods': <Object?>[
    <String, Object?>{
      'id': '00000000-0000-4000-8000-000000000001',
      'code': 'muslim-world-league',
      'checksum_sha256': 'a' * 64,
      'name': <String, Object?>{'en': 'Muslim World League'},
      'parameters': <String, Object?>{
        'fajr_angle': 18,
        'isha': <String, Object?>{'angle': 17},
      },
    },
  ],
};

class _MethodsApi implements ApiClient {
  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (path != '/prayer/methods') throw StateError('Unexpected $path');
    return _catalog;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryDatabase implements LocalDatabase {
  static const _scope = AccountScopeSnapshot(userId: 'owner', epoch: 1);
  final _state = <String, Map<String, Object?>>{};
  final _cache = <String, CachedValue>{};

  @override
  final AccountScope accountScope = AccountScope();

  @override
  Future<AccountScopeSnapshot> captureAccount() async => _scope;

  @override
  void ensureCurrent(AccountScopeSnapshot scope) {}

  @override
  Future<Map<String, Object?>?> readDeviceState(String key) async => null;

  @override
  Future<Map<String, Object?>?> readState(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async => _state[key];

  @override
  Future<void> writeState(
    String key,
    Map<String, Object?> value, {
    AccountScopeSnapshot? accountScope,
  }) async {
    _state[key] = value;
  }

  @override
  Future<CachedValue?> readCache(String key) async => _cache[key];

  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    _cache[key] = _fresh(value, maxAge);
  }

  @override
  Future<CachedValue?> readAccountCache(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async => _cache['account:$key'];

  @override
  Future<void> writeAccountCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
    AccountScopeSnapshot? accountScope,
  }) async {
    _cache['account:$key'] = _fresh(value, maxAge);
  }

  CachedValue _fresh(Object? value, Duration maxAge) {
    final now = DateTime.now().toUtc();
    return CachedValue(
      value: value,
      updatedAt: now,
      expiresAt: now.add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
