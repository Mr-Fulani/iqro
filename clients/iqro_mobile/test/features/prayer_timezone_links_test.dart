import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_widget_service.dart';
import 'package:iqro_mobile/features/prayer/prayer_local_engine.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_widget_service.dart';
import 'package:timezone/timezone.dart' as tz;

// Phones and the city search name many places by IANA links: Kuwait is a link
// to Riyadh, Kuala Lumpur to Singapore, Sarajevo to Belgrade. The zone
// database here is the one the app loads at startup, through the reminders
// gateway, not one a test picks for itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
          call,
        ) async {
          // What a phone in Kuala Lumpur reports.
          if (call.method == 'getLocalTimezone') return 'Asia/Kuala_Lumpur';
          return null;
        });
    await NotificationGateway(
      database: _MemoryDatabase(),
      initializeForTesting: () async {},
    ).initialize();
  });

  test('reminders keep the phone zone and ring at its wall-clock time', () {
    expect(tz.local.name, 'Asia/Kuala_Lumpur');

    final monday = nextWeeklyOccurrence(
      location: tz.local,
      weekday: DateTime.monday,
      hour: 20,
      minute: 0,
      now: tz.TZDateTime(tz.local, 2026, 11, 30, 9),
    );

    expect(monday.toUtc(), DateTime.utc(2026, 11, 30, 12));
  });

  test(
    'choosing a city in a linked zone calculates its prayer times',
    () async {
      final repository = _repository();

      final schedule = await repository.calculateForLocation(
        method: await _method(repository),
        location: const PrayerLocation(
          latitude: 29.36972,
          longitude: 47.97833,
          timezone: 'Asia/Kuwait',
          cityName: 'Kuwait City',
        ),
      );

      expect(schedule.timezone, 'Asia/Kuwait');
      expect(schedule.times, hasLength(6));
      for (final code in schedule.times.keys) {
        expect(
          schedule.times[code],
          _wallClock(schedule.timesUtc[code]!.add(const Duration(hours: 3))),
          reason: code,
        );
      }
    },
  );

  for (final place in _places) {
    test('${place.link} counts prayers as ${place.canonical} does', () async {
      final repository = _repository();
      final method = await _method(repository);

      Future<PrayerSchedule> calculate(String timezone) =>
          repository.calculateLocallyForDate(
            method: method,
            location: PrayerLocation(
              latitude: place.latitude,
              longitude: place.longitude,
              timezone: timezone,
            ),
            date: place.date,
          );

      final linked = await calculate(place.link);
      final canonical = await calculate(place.canonical);

      expect(linked.timezone, place.link);
      expect(linked.times, canonical.times);
      expect(linked.timesUtc, canonical.timesUtc);
      expect(
        linked.times['dhuhr'],
        _wallClock(linked.timesUtc['dhuhr']!.add(place.offset)),
      );
    });
  }

  test('the prayer widget fills its eight days in a linked zone', () async {
    final database = _MemoryDatabase();
    final repository = _repository(database);
    await repository.selectMethod('muslim-world-league');
    await database.writeState(
      'prayer_location',
      const PrayerLocation(
        latitude: 3.1412,
        longitude: 101.68653,
        timezone: 'Asia/Kuala_Lumpur',
        cityName: 'Kuala Lumpur',
      ).toJson(),
    );
    final gateway = _RecordingWidgetGateway();

    final result = await PrayerWidgetService(
      prayer: repository,
      database: database,
      gateway: gateway,
    ).update(locale: 'en');

    expect(result.hasSchedule, isTrue);
    final timeline = gateway.timeline!;
    expect(timeline, hasLength(prayerWidgetVisibleDays * 6));
    final today = DateTime.now();
    final midnight = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(hours: 8)).millisecondsSinceEpoch;
    final first = timeline.entries.firstWhere(
      (entry) => entry.key.millisecondsSinceEpoch == midnight,
    );
    expect(first.value.dateLocation, contains('Kuala Lumpur'));
    final fajr = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.getLocation('Asia/Singapore'),
      int.parse(first.value.nextEpoch),
    );
    expect(first.value.fajrTime, DateFormat.Hm('en').format(fajr));
  });

  test('the plan widget shows the day of a plan kept in a linked zone', () {
    final snapshot = buildPlanWidgetSnapshot(
      plan: const DailyPlan(
        metric: ReadingGoalMetric.pages,
        target: 6,
        achieved: 3,
        prayerPages: <String, int>{'fajr': 2},
        streak: 1,
        localDate: '2026-09-14',
        timezoneName: 'Asia/Kuwait',
      ),
      locale: 'ru',
      now: DateTime.utc(2026, 9, 14, 10),
    );

    expect(snapshot['isCurrent'], true);
    expect(
      snapshot['validUntil'],
      DateTime.utc(2026, 9, 14, 21).millisecondsSinceEpoch,
    );
  });

  test('every link the audit found has the offsets of its target', () {
    const links = <String, String>{
      'Asia/Kuwait': 'Asia/Riyadh',
      'Asia/Aden': 'Asia/Riyadh',
      'Asia/Muscat': 'Asia/Dubai',
      'Asia/Bahrain': 'Asia/Qatar',
      'Asia/Kuala_Lumpur': 'Asia/Singapore',
      'Asia/Brunei': 'Asia/Kuching',
      'Asia/Calcutta': 'Asia/Kolkata',
      'Asia/Istanbul': 'Europe/Istanbul',
      'Africa/Dakar': 'Africa/Abidjan',
      'Africa/Bamako': 'Africa/Abidjan',
      'Africa/Conakry': 'Africa/Abidjan',
      'Africa/Mogadishu': 'Africa/Nairobi',
      'Africa/Addis_Ababa': 'Africa/Nairobi',
      'Africa/Dar_es_Salaam': 'Africa/Nairobi',
      'Africa/Kampala': 'Africa/Nairobi',
      'Africa/Djibouti': 'Africa/Nairobi',
      'Africa/Asmara': 'Africa/Nairobi',
      'Indian/Comoro': 'Africa/Nairobi',
      'Europe/Sarajevo': 'Europe/Belgrade',
      'Europe/Zagreb': 'Europe/Belgrade',
      'Europe/Skopje': 'Europe/Belgrade',
      'Europe/Ljubljana': 'Europe/Belgrade',
      'Europe/Kiev': 'Europe/Kyiv',
      'Europe/Amsterdam': 'Europe/Brussels',
      'Europe/Stockholm': 'Europe/Berlin',
      'Europe/Oslo': 'Europe/Berlin',
      'Europe/Copenhagen': 'Europe/Berlin',
      'UTC': 'Etc/UTC',
    };
    final winter = DateTime.utc(2026, 1, 15, 12);
    final summer = DateTime.utc(2026, 7, 15, 12);
    for (final link in links.entries) {
      for (final instant in [winter, summer]) {
        expect(
          tz.TZDateTime.from(instant, tz.getLocation(link.key)).timeZoneOffset,
          tz.TZDateTime.from(
            instant,
            tz.getLocation(link.value),
          ).timeZoneOffset,
          reason: '${link.key} at $instant',
        );
      }
    }
  });
}

class _Place {
  const _Place(
    this.link,
    this.canonical,
    this.latitude,
    this.longitude,
    this.date,
    this.offset,
  );

  final String link;
  final String canonical;
  final double latitude;
  final double longitude;
  final DateTime date;
  final Duration offset;
}

final _places = <_Place>[
  _Place(
    'Asia/Kuala_Lumpur',
    'Asia/Singapore',
    3.1412,
    101.68653,
    DateTime(2026, 12, 1),
    const Duration(hours: 8),
  ),
  _Place(
    'Europe/Sarajevo',
    'Europe/Belgrade',
    43.84864,
    18.35644,
    DateTime(2026, 7, 15),
    const Duration(hours: 2),
  ),
  _Place(
    'Europe/Amsterdam',
    'Europe/Brussels',
    52.37403,
    4.88969,
    DateTime(2026, 1, 15),
    const Duration(hours: 1),
  ),
  _Place(
    'Africa/Dar_es_Salaam',
    'Africa/Nairobi',
    -6.82349,
    39.26951,
    DateTime(2026, 3, 1),
    const Duration(hours: 3),
  ),
];

DateTime _wallClock(DateTime utc) =>
    DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);

PrayerRepository _repository([_MemoryDatabase? database]) => PrayerRepository(
  api: _MethodsApi(),
  database: database ?? _MemoryDatabase(),
);

Future<PrayerMethod> _method(PrayerRepository repository) async =>
    (await repository.methods()).single;

final _catalog = <String, Object?>{
  'algorithm': <String, Object?>{
    'id': localPrayerEngineId,
    'version': localPrayerEngineVersion,
  },
  'timezone_database_version': '2025c',
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

class _RecordingWidgetGateway implements PrayerWidgetGateway {
  Map<DateTime, PrayerWidgetTimelineEntry>? timeline;

  @override
  Future<void> write({
    required PrayerWidgetStaticData labels,
    required Map<DateTime, PrayerWidgetTimelineEntry> timeline,
  }) async {
    this.timeline = timeline;
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
