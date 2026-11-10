import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// The home sky said «Prayer time is not calculated yet» on the first start
// of a new day: the stored schedule was yesterday's and only the prayer
// screen calculated a new one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting();
  });

  late Database sql;
  late LocalDatabase database;
  late AccountScopeSnapshot scope;
  setUp(() async {
    sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await sql.execute('''
      CREATE TABLE app_state (
        owner_id TEXT NOT NULL,
        state_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, state_key)
      )
    ''');
    database = LocalDatabase.forTesting(
      sql,
      accountScope: AccountScope.forTesting(),
    );
    scope = await database.captureAccount();
  });
  tearDown(() => sql.close());

  Future<void> store(DateTime date) => database.writeState(
    'prayer_schedule_today',
    _schedule(date).toJson(),
    accountScope: scope,
  );

  test('a new day calculates today from the stored place and method', () async {
    final now = DateTime.now();
    await store(DateTime(now.year, now.month, now.day - 1));
    final repository = _Repository(database, method: _Method());

    expect(await repository.cachedToday(accountScope: scope), isNull);
    final today = await repository.today(accountScope: scope);

    expect(repository.calculations, 1);
    expect(DateUtils.isSameDay(today?.date, now), isTrue);
  });

  test('today\'s stored schedule is shown without calculating', () async {
    await store(DateTime.now());
    final repository = _Repository(database, method: _Method());

    final today = await repository.today(accountScope: scope);

    expect(today, isNotNull);
    expect(repository.calculations, 0);
  });

  test('without a chosen method there is nothing to show yet', () async {
    final now = DateTime.now();
    await store(DateTime(now.year, now.month, now.day - 1));
    final repository = _Repository(database, method: null);

    expect(await repository.today(accountScope: scope), isNull);
    expect(repository.calculations, 0);
  });
}

abstract final class DateUtils {
  static bool isSameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

PrayerSchedule _schedule(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final times = <String, DateTime>{
    'fajr': day.add(const Duration(hours: 5)),
    'sunrise': day.add(const Duration(hours: 7)),
    'dhuhr': day.add(const Duration(hours: 12)),
    'asr': day.add(const Duration(hours: 15)),
    'maghrib': day.add(const Duration(hours: 17)),
    'isha': day.add(const Duration(hours: 19)),
  };
  return PrayerSchedule(
    date: day,
    timezone: 'Europe/Moscow',
    times: times,
    timesUtc: <String, DateTime>{
      for (final entry in times.entries) entry.key: entry.value.toUtc(),
    },
    methodName: 'mwl',
    warnings: const <String>[],
  );
}

class _Repository extends PrayerRepository {
  _Repository(LocalDatabase database, {required this.method})
    : super(api: _UnusedApiClient(), database: database);

  final PrayerMethod? method;
  var calculations = 0;

  @override
  Future<PrayerMethod?> selectedMethod({
    AccountScopeSnapshot? accountScope,
  }) async => method;

  @override
  Future<PrayerSchedule?> calculateForStoredLocation({
    required PrayerMethod method,
    AccountScopeSnapshot? accountScope,
  }) async {
    calculations++;
    return _schedule(DateTime.now());
  }
}

class _Method implements PrayerMethod {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
