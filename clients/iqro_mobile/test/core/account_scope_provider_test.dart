import 'dart:async';

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
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_controller.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/features/reminders/reminder_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'failed handoff rollback rebuilds account providers for the new epoch',
    () async {
      final sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(sql.close);
      await sql.execute('''
      CREATE TABLE app_state (
        owner_id TEXT NOT NULL,
        state_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, state_key)
      )
    ''');
      final accountScope = AccountScope.forTesting('owner-a');
      final database = LocalDatabase.forTesting(
        sql,
        accountScope: accountScope,
      );
      final notifications = _NoopNotifications(database);
      final auth = AuthRepository(config: _config, accountScope: accountScope);
      final session = _StaticSessionController(auth, notifications);
      final container = ProviderContainer(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(database),
          sessionProvider.overrideWith((ref) => session),
          reminderRepositoryProvider.overrideWithValue(
            _NoopReminderRepository(database),
          ),
          notificationGatewayProvider.overrideWithValue(notifications),
          prayerRepositoryProvider.overrideWithValue(_UnusedPrayerRepository()),
        ],
      );
      addTearDown(container.dispose);
      final keySubscription = container.listen<AccountScopeKey?>(
        activeAccountScopeKeyProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final reminderSubscription = container.listen<ReminderState>(
        reminderProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final audioSubscription = container.listen(
        audioControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(keySubscription.close);
      addTearDown(reminderSubscription.close);
      addTearDown(audioSubscription.close);
      await container.pump();

      final firstKey = container.read(activeAccountScopeKeyProvider)!;
      final firstReminder = container.read(reminderProvider.notifier);
      final firstAudio = container.read(audioControllerProvider.notifier);
      final source = accountScope.current!;
      expect(firstKey.epoch, source.epoch);

      final transition = accountScope.beginTransition(source);
      await container.pump();
      expect(container.read(activeAccountScopeKeyProvider), isNull);
      final transitionReminder = container.read(reminderProvider.notifier);
      final transitionAudio = container.read(audioControllerProvider.notifier);
      expect(transitionReminder, isNot(same(firstReminder)));
      expect(transitionAudio, isNot(same(firstAudio)));

      accountScope.rollbackTransition(transition);
      await container.pump();
      final recoveredKey = container.read(activeAccountScopeKeyProvider)!;
      final recoveredReminder = container.read(reminderProvider.notifier);
      final recoveredAudio = container.read(audioControllerProvider.notifier);
      expect(recoveredKey.userId, 'owner-a');
      expect(recoveredKey.epoch, greaterThan(firstKey.epoch));
      expect(recoveredReminder, isNot(same(transitionReminder)));
      expect(recoveredReminder, isNot(same(firstReminder)));
      expect(recoveredAudio, isNot(same(transitionAudio)));
      expect(recoveredAudio, isNot(same(firstAudio)));
    },
  );

  test(
    'delayed notification permission cannot update the next account',
    () async {
      final sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(sql.close);
      final accountScope = AccountScope.forTesting('owner-a');
      final database = LocalDatabase.forTesting(
        sql,
        accountScope: accountScope,
      );
      final notifications = _DelayedPermissionNotifications(database);
      final controller = ReminderController(
        repository: _NoopReminderRepository(database),
        notifications: notifications,
        prayerRepository: _UnusedPrayerRepository(),
        database: database,
        accountScope: accountScope.current,
        locale: () => 'ru',
      );
      addTearDown(controller.dispose);

      final request = controller.requestPermission();
      await notifications.started.future;
      accountScope.activate('owner-b');
      notifications.result.complete(ReminderPermission.granted);

      await request;
      expect(notifications.rescheduleCalls, 0);
      expect(controller.state.permission, isNot(ReminderPermission.granted));
    },
  );
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

class _StaticSessionController extends SessionController {
  _StaticSessionController(
    AuthRepository auth,
    NotificationGateway notifications,
  ) : super(auth, notifications, () => 'ru') {
    state = AsyncValue<AuthSession?>.data(
      AuthSession(
        accessToken: 'access-a',
        refreshToken: 'refresh-a',
        accessExpiresAt: DateTime.utc(2035),
        refreshExpiresAt: DateTime.utc(2036),
        bootstrapGeneration: 1,
        userId: 'owner-a',
        userStatus: 'guest',
        deviceId: 'device-a',
      ),
    );
  }

  @override
  Future<void> initialize() async {}
}

class _NoopReminderRepository extends ReminderRepository {
  _NoopReminderRepository(LocalDatabase database)
    : super(api: _UnusedApiClient(), database: database);

  @override
  Future<List<ReminderRule>> localRules({
    AccountScopeSnapshot? accountScope,
  }) async => const <ReminderRule>[];

  @override
  Future<({bool offline, List<ReminderRule> rules})> refresh({
    AccountScopeSnapshot? accountScope,
  }) async => (rules: const <ReminderRule>[], offline: true);
}

class _NoopNotifications extends NotificationGateway {
  _NoopNotifications(LocalDatabase database) : super(database: database);

  @override
  Future<ReminderPermission> permissionStatus() async =>
      ReminderPermission.denied;

  @override
  Future<ReminderSchedulingResult> reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) async => const ReminderSchedulingResult(
    permission: ReminderPermission.denied,
    exact: false,
    scheduled: 0,
  );
}

class _DelayedPermissionNotifications extends _NoopNotifications {
  _DelayedPermissionNotifications(super.database);

  final Completer<void> started = Completer<void>();
  final Completer<ReminderPermission> result = Completer<ReminderPermission>();
  var rescheduleCalls = 0;

  @override
  Future<ReminderPermission> requestPermission() {
    started.complete();
    return result.future;
  }

  @override
  Future<ReminderSchedulingResult> reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) async {
    rescheduleCalls++;
    return super.reschedule(
      rules: rules,
      prayerRepository: prayerRepository,
      locale: locale,
      accountScope: accountScope,
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
