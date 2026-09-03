import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'cold start cancels a completed notification plan owned by A for B',
    () async {
      final database = await _databaseWithManagedPlan(<String, Object?>{
        'ids': <int>[11, 12],
        'owner_id': 'owner-a',
        'generation': 4,
        'in_progress': false,
      });
      addTearDown(database.close);
      final local = LocalDatabase.forTesting(
        database,
        accountScope: AccountScope.forTesting('owner-b'),
      );
      final cancelled = <int>[];

      await NotificationGateway(
        database: local,
        initializeForTesting: () async {},
        cancelForTesting: (id) async => cancelled.add(id),
      ).initialize();

      expect(cancelled, <int>[11, 12]);
      expect(
        (await local.readDeviceState('managed_notification_ids_v1'))?['ids'],
        isEmpty,
      );
    },
  );

  test(
    'cold start cancels the entire two-phase union after a scheduling crash',
    () async {
      final database = await _databaseWithManagedPlan(<String, Object?>{
        // This is old(A) union new(B), persisted before OS mutations.
        'ids': <int>[31, 32, 41, 42],
        'owner_id': 'owner-b',
        'generation': 9,
        'in_progress': true,
      });
      addTearDown(database.close);
      final local = LocalDatabase.forTesting(
        database,
        accountScope: AccountScope.forTesting('owner-b'),
      );
      final cancelled = <int>[];

      await NotificationGateway(
        database: local,
        initializeForTesting: () async {},
        cancelForTesting: (id) async => cancelled.add(id),
      ).initialize();

      expect(cancelled, <int>[31, 32, 41, 42]);
      final state = await local.readDeviceState('managed_notification_ids_v1');
      expect(state?['ids'], isEmpty);
      expect(state?['owner_id'], isNull);
      expect(state?['in_progress'], isFalse);
      expect(state?['generation'], 10);
    },
  );

  test('cold start retains a completed plan for the same owner', () async {
    final database = await _databaseWithManagedPlan(<String, Object?>{
      'ids': <int>[51, 52],
      'owner_id': 'owner-b',
      'generation': 2,
      'in_progress': false,
    });
    addTearDown(database.close);
    final local = LocalDatabase.forTesting(
      database,
      accountScope: AccountScope.forTesting('owner-b'),
    );
    final cancelled = <int>[];

    await NotificationGateway(
      database: local,
      initializeForTesting: () async {},
      cancelForTesting: (id) async => cancelled.add(id),
    ).initialize();

    expect(cancelled, isEmpty);
    expect(
      (await local.readDeviceState('managed_notification_ids_v1'))?['ids'],
      <Object?>[51, 52],
    );
  });

  test(
    'cold-start cleanup attempts every ID and retains only cancellation failures',
    () async {
      final database = await _databaseWithManagedPlan(<String, Object?>{
        'ids': <int>[61, 62, 63],
        'owner_id': 'owner-a',
        'generation': 5,
        'in_progress': true,
      });
      addTearDown(database.close);
      final local = LocalDatabase.forTesting(
        database,
        accountScope: AccountScope.forTesting('owner-b'),
      );
      final attempted = <int>[];

      await NotificationGateway(
        database: local,
        initializeForTesting: () async {},
        cancelForTesting: (id) async {
          attempted.add(id);
          if (id == 61) throw StateError('injected cancellation failure');
        },
      ).initialize();

      expect(attempted, <int>[61, 62, 63]);
      final state = await local.readDeviceState('managed_notification_ids_v1');
      expect(state?['ids'], <Object?>[61]);
      expect(state?['in_progress'], isTrue);
      expect(state?['generation'], 6);
    },
  );

  test(
    'notification routes require the current owner and plan generation',
    () async {
      final database = await _databaseWithManagedPlan(<String, Object?>{
        'ids': <int>[81],
        'owner_id': 'owner-b',
        'generation': 7,
        'in_progress': false,
      });
      addTearDown(database.close);
      final local = LocalDatabase.forTesting(
        database,
        accountScope: AccountScope.forTesting('owner-b'),
      );
      final gateway = NotificationGateway(
        database: local,
        initializeForTesting: () async {},
      );
      await gateway.initialize();
      final routes = <String>[];
      final subscription = gateway.routeRequests.listen(routes.add);
      addTearDown(subscription.cancel);

      String payload(String owner, int generation) =>
          jsonEncode(<String, Object?>{
            'version': 1,
            'owner_id': owner,
            'generation': generation,
            'route': '/reader/2?ayah=3',
          });

      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-a', 7),
        notificationId: 81,
        initial: true,
      );
      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 6),
        notificationId: 81,
        initial: true,
      );
      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 7),
        notificationId: 999,
        initial: true,
      );
      await gateway.acceptNotificationPayloadForTesting(
        '/reader/2?ayah=3',
        notificationId: 81,
        initial: true,
      );
      expect(gateway.takeInitialRoute(), isNull);

      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-a', 7),
        notificationId: 81,
      );
      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 6),
        notificationId: 81,
      );
      await Future<void>.delayed(Duration.zero);
      expect(routes, isEmpty);

      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 7),
        notificationId: 81,
        initial: true,
      );
      local.accountScope.activate('owner-c');
      expect(gateway.takeInitialRoute(), isNull);
      local.accountScope.activate('owner-b');
      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 7),
        notificationId: 81,
        initial: true,
      );
      expect(gateway.takeInitialRoute(), '/reader/2?ayah=3');
      await gateway.acceptNotificationPayloadForTesting(
        payload('owner-b', 7),
        notificationId: 81,
      );
      await Future<void>.delayed(Duration.zero);
      expect(routes, <String>['/reader/2?ayah=3']);
    },
  );
}

Future<Database> _databaseWithManagedPlan(Map<String, Object?> plan) async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('''
    CREATE TABLE device_state (
      state_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  final local = LocalDatabase.forTesting(database);
  await local.writeDeviceState('managed_notification_ids_v1', plan);
  return database;
}
