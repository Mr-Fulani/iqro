import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_controller.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/features/reminders/reminder_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'a replan before the stored rules are read uses them, not none',
    () async {
      // On iOS the plan is also renewed when the app leaves the screen, which
      // can come before the controller has read its rules.
      final sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(sql.close);
      final accountScope = AccountScope.forTesting('owner-a');
      final database = LocalDatabase.forTesting(
        sql,
        accountScope: accountScope,
      );
      final repository = _HeldReminders(database);
      final notifications = _RecordedNotifications(database);
      final controller = ReminderController(
        repository: repository,
        notifications: notifications,
        prayerRepository: _UnusedPrayerRepository(),
        database: database,
        accountScope: accountScope.current,
        locale: () => 'ru',
      );
      addTearDown(controller.dispose);

      final replan = controller.replan();
      await Future<void>.delayed(Duration.zero);
      expect(notifications.planned, isEmpty);
      repository.stored.complete(<ReminderRule>[_fajr]);
      await replan;

      expect(notifications.planned, <List<ReminderRule>>[
        <ReminderRule>[_fajr],
      ]);
    },
  );
}

final _fajr = ReminderRule(
  id: '01900000-0000-7000-8000-000000000009',
  type: ReminderType.prayer,
  schedule: const ReminderSchedule.prayer(prayerEvent: 'fajr'),
  weekdaysMask: 127,
  timezoneMode: ReminderTimezoneMode.deviceLocal,
  signal: ReminderSignal.sound,
  isEnabled: true,
  revision: 0,
  clientUpdatedAt: DateTime.utc(2026, 11, 27),
);

/// The stored rules arrive only when [stored] completes.
class _HeldReminders extends ReminderRepository {
  _HeldReminders(LocalDatabase database)
    : super(api: _UnusedApiClient(), database: database);

  final stored = Completer<List<ReminderRule>>();

  @override
  Future<List<ReminderRule>> localRules({AccountScopeSnapshot? accountScope}) =>
      stored.future;

  @override
  Future<({bool offline, List<ReminderRule> rules})> refresh({
    AccountScopeSnapshot? accountScope,
  }) async => (rules: await stored.future, offline: true);
}

class _RecordedNotifications extends NotificationGateway {
  _RecordedNotifications(LocalDatabase database) : super(database: database);

  final planned = <List<ReminderRule>>[];

  @override
  Future<ReminderPermission> permissionStatus() async =>
      ReminderPermission.granted;

  @override
  Future<ReminderSchedulingResult> reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) async {
    planned.add(rules);
    return ReminderSchedulingResult(
      permission: ReminderPermission.granted,
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
