import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_services.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_controller.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/features/reminders/reminder_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// A fresh install (the first Google Play build) reaches the onboarding
// before anything has created the guest account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Database sql;
  setUp(() async {
    sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() => sql.close());

  test('notifications are requested before any account exists', () async {
    final database = LocalDatabase.forTesting(
      sql,
      accountScope: AccountScope(),
    );
    final notifications = _Notifications(database);
    final controller = ReminderController(
      repository: _Reminders(database),
      notifications: notifications,
      prayerRepository: _UnusedPrayerRepository(),
      database: database,
      accountScope: null,
      locale: () => 'ru',
    );
    addTearDown(controller.dispose);

    final permission = await controller.requestPermission(exactAlarms: false);

    expect(permission, ReminderPermission.granted);
    expect(controller.state.permission, ReminderPermission.granted);
    expect(notifications.requests, 1);
    expect(notifications.reschedules, 0);
  });

  test('prayer reminders create the guest account first', () async {
    final accountScope = AccountScope();
    final database = LocalDatabase.forTesting(sql, accountScope: accountScope);
    final notifications = _Notifications(database);
    final reminders = _Reminders(database);
    final session = _GuestSessionController(
      AuthRepository(config: _config, accountScope: accountScope),
      notifications,
    );
    accountScope.configure(
      loader: () async {
        accountScope.activate('guest-a');
        session.signIn('guest-a');
      },
    );
    final container = ProviderContainer(
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(database),
        sessionProvider.overrideWith((ref) => session),
        reminderRepositoryProvider.overrideWithValue(reminders),
        notificationGatewayProvider.overrideWithValue(notifications),
        prayerRepositoryProvider.overrideWithValue(_UnusedPrayerRepository()),
      ],
    );
    addTearDown(container.dispose);
    final services = container.read(onboardingServicesProvider);

    expect(await services.requestNotifications(), ReminderPermission.granted);
    await services.enablePrayerReminders();

    expect(reminders.created, <String>[
      for (final event in onboardingPrayerEvents) 'guest-a:$event',
    ]);
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

class _GuestSessionController extends SessionController {
  _GuestSessionController(
    AuthRepository auth,
    NotificationGateway notifications,
  ) : super(auth, notifications, () => 'ru') {
    state = const AsyncValue<AuthSession?>.data(null);
  }

  @override
  Future<void> initialize() async {}

  void signIn(String userId) {
    state = AsyncValue<AuthSession?>.data(
      AuthSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessExpiresAt: DateTime.utc(2035),
        refreshExpiresAt: DateTime.utc(2036),
        bootstrapGeneration: 1,
        userId: userId,
        userStatus: 'guest',
        deviceId: 'device',
      ),
    );
  }
}

class _Reminders extends ReminderRepository {
  _Reminders(LocalDatabase database)
    : super(api: _UnusedApiClient(), database: database);

  final created = <String>[];

  @override
  Future<List<ReminderRule>> localRules({
    AccountScopeSnapshot? accountScope,
  }) async => const <ReminderRule>[];

  @override
  Future<({bool offline, List<ReminderRule> rules})> refresh({
    AccountScopeSnapshot? accountScope,
  }) async => (rules: const <ReminderRule>[], offline: true);

  @override
  Future<ReminderRule> create({
    required ReminderType type,
    required ReminderSchedule schedule,
    required int weekdaysMask,
    required ReminderSignal signal,
    required ReminderTimezoneMode timezoneMode,
    String? timezoneName,
    ReminderReviewTarget? reviewTarget,
    bool isEnabled = true,
    AccountScopeSnapshot? accountScope,
  }) async {
    created.add('${accountScope?.userId}:${schedule.prayerEvent}');
    return ReminderRule(
      id: '${created.length}',
      type: type,
      schedule: schedule,
      weekdaysMask: weekdaysMask,
      timezoneMode: timezoneMode,
      signal: signal,
      isEnabled: isEnabled,
      revision: 0,
      clientUpdatedAt: DateTime.utc(2026),
    );
  }
}

class _Notifications extends NotificationGateway {
  _Notifications(LocalDatabase database) : super(database: database);

  var requests = 0;
  var reschedules = 0;

  @override
  Future<ReminderPermission> permissionStatus() async =>
      requests > 0 ? ReminderPermission.granted : ReminderPermission.denied;

  @override
  Future<ReminderPermission> requestPermission({
    bool exactAlarms = true,
  }) async {
    requests++;
    return ReminderPermission.granted;
  }

  @override
  Future<ReminderSchedulingResult> reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) async {
    reschedules++;
    return ReminderSchedulingResult(
      permission: await permissionStatus(),
      exact: true,
      scheduled: rules.length,
    );
  }
}

class _UnusedApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPrayerRepository implements PrayerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
