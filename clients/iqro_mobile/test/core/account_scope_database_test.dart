import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/sync/sync_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('schema v3 to v4 account migration', () {
    late Database database;

    setUp(() async {
      database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await _createCacheTable(database);
      await _createV3AccountTables(database);
      await _insertLegacyFixture(database);
    });

    tearDown(() => database.close());

    test('assigns every legacy row to the known cached owner', () async {
      const ownerId = 'guest:known-owner';

      await LocalDatabase.migrateLegacyAccountTablesForTesting(
        database,
        legacyOwnerId: ownerId,
      );

      for (final table in _accountTables) {
        final rows = await database.query(table);
        expect(rows, hasLength(1), reason: '$table must preserve its row');
        expect(rows.single['owner_id'], ownerId, reason: table);
      }
      expect(await _legacyTableNames(database), isEmpty);

      final primaryKeyColumns = await database.rawQuery(
        'PRAGMA table_info(app_state)',
      );
      expect(
        primaryKeyColumns
            .where((column) => (column['pk'] as int) > 0)
            .map((column) => column['name']),
        <Object?>['owner_id', 'state_key'],
      );
    });

    test(
      'quarantines legacy rows when no trustworthy owner is known',
      () async {
        await LocalDatabase.migrateLegacyAccountTablesForTesting(
          database,
          legacyOwnerId: '   ',
        );

        for (final table in _accountTables) {
          final rows = await database.query(table);
          expect(rows, hasLength(1), reason: '$table must preserve its row');
          expect(
            rows.single['owner_id'],
            LocalDatabase.quarantinedLegacyOwner,
            reason: table,
          );
        }

        final freshScope = AccountScope.forTesting('fresh-account');
        final local = LocalDatabase.forTesting(
          database,
          accountScope: freshScope,
        );
        expect(await local.readState('plan'), isNull);
        expect(await local.pendingOutbox(), isEmpty);
        expect(await local.readReminders(), isEmpty);
        for (final table in _accountTables) {
          expect(
            await database.query(
              table,
              where: 'owner_id = ?',
              whereArgs: const <Object?>['fresh-account'],
            ),
            isEmpty,
            reason: '$table quarantine must not leak into the fresh account',
          );
        }
      },
    );

    test(
      'extracts legacy OS notification IDs for cancellation without an owner',
      () async {
        await database.insert('app_state', <String, Object?>{
          'state_key': 'reminder_notification_plan',
          'payload': jsonEncode(const <String, Object?>{
            'ids': <int>[71, 72, 72],
          }),
          'updated_at': '2026-09-01T11:00:00.000Z',
        });

        await LocalDatabase.migrateLegacyAccountTablesForTesting(
          database,
          legacyOwnerId: null,
        );

        final local = LocalDatabase.forTesting(
          database,
          accountScope: AccountScope(),
        );
        final extracted = await local.readDeviceState(
          'managed_notification_ids_v1',
        );
        expect(extracted?['ids'], <Object?>[71, 72]);
        expect(extracted?['owner_id'], isNull);
        expect(extracted?['in_progress'], isTrue);
        final quarantinedPlan = await database.query(
          'app_state',
          where: 'owner_id = ? AND state_key = ?',
          whereArgs: const <Object?>[
            LocalDatabase.quarantinedLegacyOwner,
            'reminder_notification_plan',
          ],
        );
        expect(quarantinedPlan, hasLength(1));

        final cancelled = <int>[];
        await NotificationGateway(
          database: local,
          initializeForTesting: () async {},
          cancelForTesting: (id) async => cancelled.add(id),
        ).initialize();

        expect(cancelled, <int>[71, 72]);
        final cleared = await local.readDeviceState(
          'managed_notification_ids_v1',
        );
        expect(cleared?['ids'], isEmpty);
        expect(cleared?['in_progress'], isFalse);
      },
    );
  });

  group('account-owned SQLite state', () {
    late Database database;

    setUp(() async {
      database = await _openV4Database();
    });

    tearDown(() => database.close());

    test(
      'same logical keys remain isolated across every account-owned table',
      () async {
        await _insertOwnerFixture(database, ownerId: 'owner-a', marker: 11);
        await _insertOwnerFixture(database, ownerId: 'owner-b', marker: 22);

        for (final table in _accountTables) {
          final rows = await database.query(table);
          expect(rows.map((row) => row['owner_id']).toSet(), <Object?>{
            'owner-a',
            'owner-b',
          }, reason: table);
          expect(rows, hasLength(table == 'app_state' ? 4 : 2), reason: table);
        }

        final scope = AccountScope.forTesting('owner-a');
        final local = LocalDatabase.forTesting(database, accountScope: scope);
        expect((await local.readState('plan'))!['marker'], 11);
        expect((await local.readReminders()).single['marker'], 11);
        expect((await local.pendingOutbox()).single['entity_id'], 'entity-11');
        expect(
          await SqliteSyncStore(database, ownerId: 'owner-a').readCursor(),
          11,
        );

        scope.activate('owner-b');
        expect((await local.readState('plan'))!['marker'], 22);
        expect((await local.readReminders()).single['marker'], 22);
        expect((await local.pendingOutbox()).single['entity_id'], 'entity-22');
        expect(
          await SqliteSyncStore(database, ownerId: 'owner-b').readCursor(),
          22,
        );

        for (final table in <String>[
          'reading_positions',
          'bookmarks',
          'favorites',
        ]) {
          final a = await database.query(
            table,
            where: 'owner_id = ?',
            whereArgs: const <Object?>['owner-a'],
          );
          final b = await database.query(
            table,
            where: 'owner_id = ?',
            whereArgs: const <Object?>['owner-b'],
          );
          expect(_fixtureMarker(table, a.single), 11, reason: '$table A');
          expect(_fixtureMarker(table, b.single), 22, reason: '$table B');
        }
      },
    );

    test(
      'confirmed transfer is copy-first, preserves newer target rows, resets '
      'cursor, and finalizes source separately',
      () async {
        const source = 'guest-a';
        const target = 'verified-b';
        await _insertTransferFixtures(database, source: source, target: target);
        final local = LocalDatabase.forTesting(
          database,
          accountScope: AccountScope.forTesting(source),
        );

        await local.transferAccountData(source, target);

        for (final table in _accountTables) {
          expect(
            await _ownerRowCount(database, table, source),
            greaterThan(0),
            reason: '$table source must survive the copy phase',
          );
        }
        for (final fixture in _transferFixtures) {
          final shared = await database.query(
            fixture.table,
            where: 'owner_id = ? AND ${fixture.keyColumn} = ?',
            whereArgs: <Object?>[target, fixture.sharedKey],
          );
          expect(shared, hasLength(1), reason: fixture.table);
          expect(
            fixture.marker(shared.single),
            'target-newer',
            reason: '${fixture.table} must not overwrite newer target data',
          );

          final copied = await database.query(
            fixture.table,
            where: 'owner_id = ? AND ${fixture.keyColumn} = ?',
            whereArgs: <Object?>[target, fixture.sourceOnlyKey],
          );
          expect(copied, hasLength(1), reason: fixture.table);
          expect(
            fixture.marker(copied.single),
            'source-only',
            reason: '${fixture.table} source-only data must be copied',
          );
        }

        expect(
          await database.query(
            'app_state',
            where: 'owner_id = ? AND state_key = ?',
            whereArgs: const <Object?>[target, 'sync_cursor'],
          ),
          isEmpty,
          reason: 'a server cursor cannot be transferred between users',
        );
        expect(
          jsonDecode(
            (await database.query(
                  'cache_entries',
                  where: 'cache_key = ?',
                  whereArgs: const <Object?>['account:verified-b:profile'],
                )).single['payload']!
                as String,
          ),
          <String, Object?>{'marker': 'target-newer'},
        );
        expect(
          await database.query(
            'cache_entries',
            where: 'cache_key = ?',
            whereArgs: const <Object?>['account:verified-b:source-only-cache'],
          ),
          hasLength(1),
        );

        await local.finalizeAccountTransfer(source, target);

        for (final table in _accountTables) {
          expect(
            await _ownerRowCount(database, table, source),
            0,
            reason: '$table source is removed only by finalize',
          );
          expect(
            await _ownerRowCount(database, table, target),
            greaterThan(0),
            reason: '$table target must survive finalize',
          );
        }
        expect(
          await database.query(
            'cache_entries',
            where: 'cache_key LIKE ?',
            whereArgs: const <Object?>['account:guest-a:%'],
          ),
          isEmpty,
        );
        expect(
          await database.query(
            'cache_entries',
            where: 'cache_key LIKE ?',
            whereArgs: const <Object?>['account:verified-b:%'],
          ),
          isNotEmpty,
        );
      },
    );

    test(
      'a queued write captured by A rolls back after transition starts and is '
      'never copied into B',
      () async {
        final scope = AccountScope.forTesting('owner-a');
        final local = LocalDatabase.forTesting(database, accountScope: scope);
        final capturedA = await scope.capture();
        await local.writeState('stable', const <String, Object?>{
          'value': 'from-a',
        }, accountScope: capturedA);

        final transactionEntered = Completer<void>();
        final releaseTransaction = Completer<void>();
        final blocker = database.transaction((_) async {
          transactionEntered.complete();
          await releaseTransaction.future;
        });
        await transactionEntered.future;

        final staleWrite = local.writeState('late', const <String, Object?>{
          'value': 'must-not-land',
        }, accountScope: capturedA);
        final staleExpectation = expectLater(
          staleWrite,
          throwsA(isA<AccountScopeChanged>()),
        );
        await Future<void>.delayed(Duration.zero);
        final transition = scope.beginTransition(capturedA);
        final transfer = local.transferAccountData('owner-a', 'owner-b');

        releaseTransaction.complete();
        await blocker;
        await staleExpectation;
        await transfer;
        scope.completeTransition(transition, targetUserId: 'owner-b');

        expect((await local.readState('stable'))!['value'], 'from-a');
        expect(await local.readState('late'), isNull);
        expect(
          await database.query(
            'app_state',
            where: 'state_key = ?',
            whereArgs: const <Object?>['late'],
          ),
          isEmpty,
        );
      },
    );

    test('handoff drops stale source intent and a full snapshot keeps newer '
        'target intent', () async {
      const source = 'guest-a';
      const target = 'verified-b';
      const entityId = '01994f46-5fa6-7a20-b9ab-2a7bbcc79991';
      await database.insert('reading_positions', <String, Object?>{
        'owner_id': source,
        'edition': 'madani-hafs',
        'entity_id': entityId,
        'surah': 1,
        'ayah': 2,
        'page': 2,
        'server_revision': 5,
        'dirty': 1,
        'updated_at': '2026-09-01T10:00:00Z',
      });
      await database.insert('reading_positions', <String, Object?>{
        'owner_id': target,
        'edition': 'madani-hafs',
        'entity_id': entityId,
        'surah': 2,
        'ayah': 22,
        'page': 22,
        'server_revision': 5,
        'dirty': 1,
        'updated_at': '2026-09-01T12:00:00Z',
      });
      await _insertPositionOutbox(
        database,
        ownerId: source,
        operationId: 'source-position-operation',
        entityId: entityId,
        surah: 1,
        ayah: 2,
        page: 2,
        timestamp: '2026-09-01T10:00:00Z',
      );
      await _insertPositionOutbox(
        database,
        ownerId: target,
        operationId: 'target-position-operation',
        entityId: entityId,
        surah: 2,
        ayah: 22,
        page: 22,
        timestamp: '2026-09-01T12:00:00Z',
      );
      await database.insert('favorites', <String, Object?>{
        'owner_id': source,
        'item_key': 'dua:hisn:7',
        'kind': 'dua',
        'payload': jsonEncode(const <String, Object?>{'source_number': 7}),
        'updated_at': '2026-09-01T10:00:00Z',
      });
      await _insertDuaOutbox(
        database,
        ownerId: source,
        operationId: 'source-dua-operation',
        favorite: true,
        timestamp: '2026-09-01T10:00:00Z',
      );
      await _insertDuaOutbox(
        database,
        ownerId: target,
        operationId: 'target-dua-operation',
        favorite: false,
        timestamp: '2026-09-01T12:00:00Z',
      );

      final local = LocalDatabase.forTesting(
        database,
        accountScope: AccountScope.forTesting(source),
      );
      await local.transferAccountData(source, target);

      final transferred = await database.query(
        'outbox',
        where: 'owner_id = ?',
        whereArgs: const <Object?>[target],
        orderBy: 'operation_id',
      );
      expect(transferred.map((row) => row['operation_id']), <Object?>[
        'target-dua-operation',
        'target-position-operation',
      ]);
      expect(
        await database.query(
          'favorites',
          where: 'owner_id = ? AND item_key = ?',
          whereArgs: const <Object?>[target, 'dua:hisn:7'],
        ),
        isEmpty,
      );

      final store = SqliteSyncStore(database, ownerId: target);
      await store.replaceAuthoritativeSnapshot(<Object?>[
        <String, Object?>{
          'id': entityId,
          'entity_type': 'reading_position',
          'edition_code': 'madani-hafs',
          'page_number': 3,
          'ayah': const <String, Object?>{'surah_number': 1, 'ayah_number': 3},
          'revision': 6,
          'updated_at': '2026-09-01T13:00:00Z',
        },
      ], 1);

      final position = (await database.query(
        'reading_positions',
        where: 'owner_id = ?',
        whereArgs: const <Object?>[target],
      )).single;
      expect(position['surah'], 2);
      expect(position['ayah'], 22);
      expect(position['page'], 22);
      expect(position['dirty'], 1);
      expect(
        (await store.pendingEntities()).single.operationId,
        isNot('source-position-operation'),
      );
    });
  });
}

const _accountTables = <String>[
  'reading_positions',
  'bookmarks',
  'favorites',
  'outbox',
  'app_state',
  'reminders',
];

Future<Database> _openV4Database() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await _createCacheTable(database);
  await _createV3AccountTables(database);
  await LocalDatabase.migrateLegacyAccountTablesForTesting(
    database,
    legacyOwnerId: LocalDatabase.quarantinedLegacyOwner,
  );
  return database;
}

Future<void> _createCacheTable(Database database) => database.execute('''
  CREATE TABLE cache_entries (
    cache_key TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    etag TEXT,
    updated_at TEXT NOT NULL,
    expires_at TEXT
  )
''');

Future<void> _createV3AccountTables(Database database) async {
  await database.execute('''
    CREATE TABLE reading_positions (
      edition TEXT PRIMARY KEY,
      entity_id TEXT NOT NULL,
      surah INTEGER NOT NULL,
      ayah INTEGER NOT NULL,
      page INTEGER,
      server_revision INTEGER NOT NULL DEFAULT 0,
      dirty INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE bookmarks (
      id TEXT PRIMARY KEY,
      edition TEXT NOT NULL,
      surah INTEGER NOT NULL,
      ayah INTEGER NOT NULL,
      server_revision INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE favorites (
      item_key TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE outbox (
      operation_id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_error TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE app_state (
      state_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE reminders (
      id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
  ''');
}

Future<void> _insertLegacyFixture(Database database) async {
  const timestamp = '2026-09-01T10:00:00.000Z';
  await database.insert('reading_positions', <String, Object?>{
    'edition': 'madani-hafs',
    'entity_id': 'position-legacy',
    'surah': 2,
    'ayah': 3,
    'page': 4,
    'server_revision': 5,
    'dirty': 1,
    'updated_at': timestamp,
  });
  await database.insert('bookmarks', <String, Object?>{
    'id': 'bookmark-legacy',
    'edition': 'madani-hafs',
    'surah': 2,
    'ayah': 3,
    'server_revision': 5,
    'is_deleted': 0,
    'updated_at': timestamp,
  });
  await database.insert('favorites', <String, Object?>{
    'item_key': 'dua:legacy:1',
    'kind': 'dua',
    'payload': jsonEncode(const <String, Object?>{'marker': 'legacy'}),
    'updated_at': timestamp,
  });
  await database.insert('outbox', <String, Object?>{
    'operation_id': 'operation-legacy',
    'entity_type': 'dua_favorite',
    'entity_id': 'dua:legacy:1',
    'payload': jsonEncode(const <String, Object?>{'marker': 'legacy'}),
    'attempts': 2,
    'created_at': timestamp,
    'last_error': 'offline',
  });
  await database.insert('app_state', <String, Object?>{
    'state_key': 'plan',
    'payload': jsonEncode(const <String, Object?>{'marker': 'legacy'}),
    'updated_at': timestamp,
  });
  await database.insert('reminders', <String, Object?>{
    'id': 'reminder-legacy',
    'payload': jsonEncode(const <String, Object?>{
      'id': 'reminder-legacy',
      'marker': 'legacy',
    }),
    'revision': 3,
    'is_deleted': 0,
    'updated_at': timestamp,
  });
}

Future<List<String>> _legacyTableNames(Database database) async {
  final rows = await database.query(
    'sqlite_master',
    columns: const <String>['name'],
    where: "type = 'table' AND name LIKE ?",
    whereArgs: const <Object?>['%_legacy_v3'],
  );
  return rows.map((row) => row['name']! as String).toList(growable: false);
}

Future<void> _insertOwnerFixture(
  Database database, {
  required String ownerId,
  required int marker,
}) async {
  final timestamp = '2026-09-01T10:${marker.toString().padLeft(2, '0')}:00Z';
  await database.insert('reading_positions', <String, Object?>{
    'owner_id': ownerId,
    'edition': 'madani-hafs',
    'entity_id': 'position-$marker',
    'surah': marker,
    'ayah': 1,
    'page': marker,
    'server_revision': marker,
    'dirty': 1,
    'updated_at': timestamp,
  });
  await database.insert('bookmarks', <String, Object?>{
    'owner_id': ownerId,
    'id': 'shared-bookmark',
    'edition': 'madani-hafs',
    'surah': marker,
    'ayah': 1,
    'server_revision': marker,
    'is_deleted': 0,
    'updated_at': timestamp,
  });
  await database.insert('favorites', <String, Object?>{
    'owner_id': ownerId,
    'item_key': 'dua:shared:1',
    'kind': 'dua',
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'updated_at': timestamp,
  });
  await database.insert('outbox', <String, Object?>{
    'owner_id': ownerId,
    'operation_id': 'shared-operation',
    'entity_type': 'share_event',
    'entity_id': 'entity-$marker',
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'created_at': timestamp,
  });
  await database.insert('app_state', <String, Object?>{
    'owner_id': ownerId,
    'state_key': 'plan',
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'updated_at': timestamp,
  });
  await database.insert('app_state', <String, Object?>{
    'owner_id': ownerId,
    'state_key': 'sync_cursor',
    'payload': jsonEncode(<String, Object?>{'value': marker}),
    'updated_at': timestamp,
  });
  await database.insert('reminders', <String, Object?>{
    'owner_id': ownerId,
    'id': 'shared-reminder',
    'payload': jsonEncode(<String, Object?>{
      'id': 'shared-reminder',
      'marker': marker,
    }),
    'revision': marker,
    'is_deleted': 0,
    'updated_at': timestamp,
  });
}

int _fixtureMarker(String table, Map<String, Object?> row) {
  if (table == 'reading_positions' || table == 'bookmarks') {
    return row['surah']! as int;
  }
  return (jsonDecode(row['payload']! as String) as Map)['marker']! as int;
}

typedef _RowMarker = String Function(Map<String, Object?> row);

class _TransferFixture {
  const _TransferFixture({
    required this.table,
    required this.keyColumn,
    required this.sharedKey,
    required this.sourceOnlyKey,
    required this.marker,
  });

  final String table;
  final String keyColumn;
  final Object sharedKey;
  final Object sourceOnlyKey;
  final _RowMarker marker;
}

final _transferFixtures = <_TransferFixture>[
  _TransferFixture(
    table: 'reading_positions',
    keyColumn: 'edition',
    sharedKey: 'shared-edition',
    sourceOnlyKey: 'source-only-edition',
    marker: (row) => row['entity_id']! as String,
  ),
  _TransferFixture(
    table: 'bookmarks',
    keyColumn: 'id',
    sharedKey: 'shared-bookmark',
    sourceOnlyKey: 'source-only-bookmark',
    marker: (row) => jsonDecode(row['edition']! as String) as String,
  ),
  _TransferFixture(
    table: 'favorites',
    keyColumn: 'item_key',
    sharedKey: 'shared-favorite',
    sourceOnlyKey: 'source-only-favorite',
    marker: _jsonMarker,
  ),
  _TransferFixture(
    table: 'outbox',
    keyColumn: 'operation_id',
    sharedKey: 'shared-operation',
    sourceOnlyKey: 'source-only-operation',
    marker: _jsonMarker,
  ),
  _TransferFixture(
    table: 'app_state',
    keyColumn: 'state_key',
    sharedKey: 'shared-state',
    sourceOnlyKey: 'source-only-state',
    marker: _jsonMarker,
  ),
  _TransferFixture(
    table: 'reminders',
    keyColumn: 'id',
    sharedKey: 'shared-reminder',
    sourceOnlyKey: 'source-only-reminder',
    marker: _jsonMarker,
  ),
];

String _jsonMarker(Map<String, Object?> row) =>
    (jsonDecode(row['payload']! as String) as Map)['marker']! as String;

Future<void> _insertTransferFixtures(
  Database database, {
  required String source,
  required String target,
}) async {
  const older = '2026-09-01T10:00:00.000Z';
  const newer = '2026-09-02T10:00:00.000Z';

  Future<void> reading(
    String owner,
    String edition,
    String marker,
    String updatedAt,
  ) => database.insert('reading_positions', <String, Object?>{
    'owner_id': owner,
    'edition': edition,
    'entity_id': marker,
    'surah': 1,
    'ayah': 1,
    'page': 1,
    'updated_at': updatedAt,
  });

  Future<void> bookmark(
    String owner,
    String id,
    String marker,
    String updatedAt,
  ) => database.insert('bookmarks', <String, Object?>{
    'owner_id': owner,
    'id': id,
    'edition': jsonEncode(marker),
    'surah': 1,
    'ayah': 1,
    'updated_at': updatedAt,
  });

  Future<void> favorite(
    String owner,
    String key,
    String marker,
    String updatedAt,
  ) => database.insert('favorites', <String, Object?>{
    'owner_id': owner,
    'item_key': key,
    'kind': 'dua',
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'updated_at': updatedAt,
  });

  Future<void> outbox(
    String owner,
    String operationId,
    String marker,
    String createdAt,
  ) => database.insert('outbox', <String, Object?>{
    'owner_id': owner,
    'operation_id': operationId,
    'entity_type': 'share_event',
    'entity_id': marker,
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'created_at': createdAt,
  });

  Future<void> state(
    String owner,
    String key,
    String marker,
    String updatedAt,
  ) => database.insert('app_state', <String, Object?>{
    'owner_id': owner,
    'state_key': key,
    'payload': jsonEncode(<String, Object?>{'marker': marker}),
    'updated_at': updatedAt,
  });

  Future<void> reminder(
    String owner,
    String id,
    String marker,
    String updatedAt,
  ) => database.insert('reminders', <String, Object?>{
    'owner_id': owner,
    'id': id,
    'payload': jsonEncode(<String, Object?>{'id': id, 'marker': marker}),
    'updated_at': updatedAt,
  });

  Future<void> cache(String key, String marker, String updatedAt) =>
      database.insert('cache_entries', <String, Object?>{
        'cache_key': key,
        'payload': jsonEncode(<String, Object?>{'marker': marker}),
        'updated_at': updatedAt,
      });

  await reading(source, 'shared-edition', 'source-older', older);
  await reading(target, 'shared-edition', 'target-newer', newer);
  await reading(source, 'source-only-edition', 'source-only', newer);
  await bookmark(source, 'shared-bookmark', 'source-older', older);
  await bookmark(target, 'shared-bookmark', 'target-newer', newer);
  await bookmark(source, 'source-only-bookmark', 'source-only', newer);
  await favorite(source, 'shared-favorite', 'source-older', older);
  await favorite(target, 'shared-favorite', 'target-newer', newer);
  await favorite(source, 'source-only-favorite', 'source-only', newer);
  await outbox(source, 'shared-operation', 'source-older', older);
  await outbox(target, 'shared-operation', 'target-newer', newer);
  await outbox(source, 'source-only-operation', 'source-only', newer);
  await state(source, 'shared-state', 'source-older', older);
  await state(target, 'shared-state', 'target-newer', newer);
  await state(source, 'source-only-state', 'source-only', newer);
  await state(source, 'sync_cursor', 'source-cursor', newer);
  await state(target, 'sync_cursor', 'target-cursor', newer);
  await reminder(source, 'shared-reminder', 'source-older', older);
  await reminder(target, 'shared-reminder', 'target-newer', newer);
  await reminder(source, 'source-only-reminder', 'source-only', newer);
  await cache('account:$source:profile', 'source-older', older);
  await cache('account:$target:profile', 'target-newer', newer);
  await cache('account:$source:source-only-cache', 'source-only', newer);
}

Future<int> _ownerRowCount(
  Database database,
  String table,
  String ownerId,
) async {
  final rows = await database.rawQuery(
    'SELECT COUNT(*) AS row_count FROM $table WHERE owner_id = ?',
    <Object?>[ownerId],
  );
  return (rows.single['row_count'] as num).toInt();
}

Future<void> _insertPositionOutbox(
  Database database, {
  required String ownerId,
  required String operationId,
  required String entityId,
  required int surah,
  required int ayah,
  required int page,
  required String timestamp,
}) => database.insert('outbox', <String, Object?>{
  'owner_id': ownerId,
  'operation_id': operationId,
  'entity_type': 'reading_position',
  'entity_id': entityId,
  'payload': jsonEncode(<String, Object?>{
    'operation_id': operationId,
    'entity_type': 'reading_position',
    'entity_id': entityId,
    'action': 'upsert',
    'base_revision': 5,
    'client_updated_at': timestamp,
    'payload': <String, Object?>{
      'edition_code': 'madani-hafs',
      'surah_number': surah,
      'ayah_number': ayah,
      'page_number': page,
    },
  }),
  'created_at': timestamp,
});

Future<void> _insertDuaOutbox(
  Database database, {
  required String ownerId,
  required String operationId,
  required bool favorite,
  required String timestamp,
}) => database.insert('outbox', <String, Object?>{
  'owner_id': ownerId,
  'operation_id': operationId,
  'entity_type': 'dua_favorite',
  'entity_id': 'dua:hisn:7',
  'payload': jsonEncode(<String, Object?>{
    'collection': 'hisn',
    'source_number': 7,
    'is_favorite': favorite,
  }),
  'created_at': timestamp,
});
