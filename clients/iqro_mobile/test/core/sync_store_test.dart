import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/sync/sync_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteSyncStore store;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(database);
    store = SqliteSyncStore(database, now: () => DateTime.utc(2026, 9, 1, 12));
  });

  tearDown(() => database.close());

  test('full snapshot replaces stale rows and rebases local intent', () async {
    await database.insert('bookmarks', <String, Object?>{
      'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc70001',
      'edition': 'madani-hafs',
      'surah': 1,
      'ayah': 1,
      'server_revision': 2,
      'is_deleted': 0,
      'updated_at': '2026-08-31T10:00:00Z',
    });
    await _insertReadingOperation(database, baseRevision: 1);

    await store.replaceAuthoritativeSnapshot(<Object?>[
      _readingPosition(revision: 3, page: 4),
      _bookmark(id: '01994f46-5fa6-7a20-b9ab-2a7bbcc70002', revision: 1),
    ], 7);

    final bookmarks = await database.query('bookmarks', orderBy: 'id');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single['id'], '01994f46-5fa6-7a20-b9ab-2a7bbcc70002');
    final positions = await database.query('reading_positions');
    expect(positions.single['page'], 9);
    expect(positions.single['surah'], 2);
    expect(positions.single['ayah'], 5);
    expect(positions.single['server_revision'], 3);
    expect(positions.single['dirty'], 1);

    final pending = await store.pendingEntities();
    expect(pending, hasLength(1));
    expect(pending.single.operationId, isNot('operation-1'));
    expect(pending.single.baseRevision, 3);
    expect(await store.readCursor(), 7);
  });

  test(
    'incremental entity is monotonic and preserves pending intent',
    () async {
      await store.applyRemoteEntity(
        _bookmark(
          id: '01994f46-5fa6-7a20-b9ab-2a7bbcc70002',
          revision: 3,
          surah: 1,
          ayah: 2,
        ),
      );
      await _insertBookmarkOperation(database, baseRevision: 3);

      await store.applyRemoteEntity(
        _bookmark(
          id: '01994f46-5fa6-7a20-b9ab-2a7bbcc70002',
          revision: 4,
          surah: 1,
          ayah: 3,
        ),
      );
      await store.applyRemoteEntity(
        _bookmark(
          id: '01994f46-5fa6-7a20-b9ab-2a7bbcc70002',
          revision: 2,
          surah: 1,
          ayah: 1,
        ),
      );

      final bookmark = (await database.query('bookmarks')).single;
      expect(bookmark['server_revision'], 4);
      expect(bookmark['surah'], 2);
      expect(bookmark['ayah'], 5);
      final pending = (await store.pendingEntities()).single;
      expect(pending.baseRevision, 4);
      expect(pending.operationId, isNot('bookmark-operation-1'));
    },
  );

  test('unusable offline create is remapped without losing intent', () async {
    await _insertBookmarkOperation(database, baseRevision: 0);
    final original = (await store.pendingEntities()).single;

    final resolution = await store
        .resolveConflict(original, const <String, Object?>{
          'outcome': 'conflict',
          'conflict_reason': 'entity_id_not_reusable',
          'entity': null,
        });

    expect(resolution, SyncConflictResolution.rebased);
    final pending = (await store.pendingEntities()).single;
    expect(pending.operationId, isNot(original.operationId));
    expect(pending.entityId, isNot(original.entityId));
    expect(pending.baseRevision, 0);
    expect(pending.intent['surah_number'], 2);
    expect(pending.intent['ayah_number'], 5);
    final bookmark = (await database.query('bookmarks')).single;
    expect(bookmark['id'], pending.entityId);
    expect(bookmark['surah'], 2);
    expect(bookmark['ayah'], 5);
  });

  test('already deleted remote entity satisfies pending delete', () async {
    await _insertBookmarkOperation(database, baseRevision: 2, action: 'delete');
    final operation = (await store.pendingEntities()).single;

    final resolution = await store.resolveConflict(operation, <String, Object?>{
      'outcome': 'conflict',
      'conflict_reason': 'revision_mismatch',
      'entity': _bookmark(id: operation.entityId!, revision: 3, deleted: true),
    });

    expect(resolution, SyncConflictResolution.satisfied);
    expect(await store.pendingCount(), 0);
    final bookmark = (await database.query('bookmarks')).single;
    expect(bookmark['is_deleted'], 1);
    expect(bookmark['server_revision'], 3);
  });

  test(
    'reminder refresh rebases and preserves offline desired state',
    () async {
      await _insertReminderOperation(database, baseRevision: 1);

      await store.replaceAuthoritativeReminderSnapshot(<Map<String, Object?>>[
        _reminder(revision: 2, weekdaysMask: 127),
      ]);

      final local =
          jsonDecode(
                (await database.query('reminders')).single['payload']!
                    as String,
              )
              as Map;
      expect(local['revision'], 2);
      expect(local['weekdays_mask'], 31);
      expect(
        (local['review_target'] as Map)['start']['id'],
        '01994f46-5fa6-7a20-b9ab-2a7bbcc71001',
      );
      final pending = (await store.pendingEntities()).single;
      expect(pending.entityType, 'reminder');
      expect(pending.baseRevision, 2);
      expect(pending.operationId, isNot('reminder-operation-1'));
    },
  );

  test('a newer queued edit wins over an older in-flight conflict', () async {
    await _insertBookmarkOperation(database, baseRevision: 2);
    final inFlight = (await store.pendingEntities()).single;
    await database.delete('outbox');
    await _insertBookmarkOperation(
      database,
      operationId: 'bookmark-operation-2',
      baseRevision: 2,
      surah: 3,
      ayah: 7,
    );

    final resolution = await store.resolveConflict(inFlight, <String, Object?>{
      'outcome': 'conflict',
      'conflict_reason': 'revision_mismatch',
      'entity': _bookmark(
        id: inFlight.entityId!,
        revision: 3,
        surah: 1,
        ayah: 3,
      ),
    });

    expect(resolution, SyncConflictResolution.rebased);
    final pending = (await store.pendingEntities()).single;
    expect(pending.intent['surah_number'], 3);
    expect(pending.intent['ayah_number'], 7);
    expect(pending.baseRevision, 3);
    final local = (await database.query('bookmarks')).single;
    expect(local['surah'], 3);
    expect(local['ayah'], 7);
  });

  test('reminder optimistic state and replacement outbox are atomic', () async {
    final localDatabase = LocalDatabase.forTesting(database);
    final reminder = _reminder(revision: 0, weekdaysMask: 31);
    await localDatabase.upsertReminderWithOutbox(
      reminder: reminder,
      operationId: 'reminder-operation-1',
      operation: _reminderOperationBody('reminder-operation-1', 31),
    );
    await localDatabase.upsertReminderWithOutbox(
      reminder: <String, Object?>{...reminder, 'weekdays_mask': 63},
      operationId: 'reminder-operation-2',
      operation: _reminderOperationBody('reminder-operation-2', 63),
    );

    final storedReminder =
        jsonDecode(
              (await database.query('reminders')).single['payload']! as String,
            )
            as Map;
    expect(storedReminder['weekdays_mask'], 63);
    final rows = await database.query('outbox');
    expect(rows, hasLength(1));
    expect(rows.single['operation_id'], 'reminder-operation-2');
  });
}

Future<void> _createSchema(Database database) async {
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
    CREATE TABLE reminders (
      id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
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
}

Future<void> _insertReadingOperation(
  Database database, {
  required int baseRevision,
}) async {
  const entityId = '01994f46-5fa6-7a20-b9ab-2a7bbcc79991';
  const operationId = 'operation-1';
  await database.insert('outbox', <String, Object?>{
    'operation_id': operationId,
    'entity_type': 'reading_position',
    'entity_id': entityId,
    'payload': jsonEncode(<String, Object?>{
      'operation_id': operationId,
      'entity_type': 'reading_position',
      'entity_id': entityId,
      'action': 'upsert',
      'base_revision': baseRevision,
      'client_updated_at': '2026-09-01T10:00:00Z',
      'payload': const <String, Object?>{
        'edition_code': 'madani-hafs',
        'page_number': 9,
        'surah_number': 2,
        'ayah_number': 5,
        'progress_percent': '1.49',
        'last_read_at': '2026-09-01T10:00:00Z',
      },
    }),
    'attempts': 0,
    'created_at': '2026-09-01T10:00:00Z',
  });
}

Future<void> _insertBookmarkOperation(
  Database database, {
  required int baseRevision,
  String action = 'upsert',
  String operationId = 'bookmark-operation-1',
  int surah = 2,
  int ayah = 5,
}) async {
  const entityId = '01994f46-5fa6-7a20-b9ab-2a7bbcc70002';
  await database.insert('outbox', <String, Object?>{
    'operation_id': operationId,
    'entity_type': 'bookmark',
    'entity_id': entityId,
    'payload': jsonEncode(<String, Object?>{
      'operation_id': operationId,
      'entity_type': 'bookmark',
      'entity_id': entityId,
      'action': action,
      'base_revision': baseRevision,
      'client_updated_at': '2026-09-01T10:00:00Z',
      'payload': action == 'delete'
          ? const <String, Object?>{}
          : <String, Object?>{
              'edition_code': 'madani-hafs',
              'page_number': 9,
              'surah_number': surah,
              'ayah_number': ayah,
              'color_key': 'emerald',
            },
    }),
    'attempts': 0,
    'created_at': '2026-09-01T10:00:00Z',
  });
}

Future<void> _insertReminderOperation(
  Database database, {
  required int baseRevision,
}) async {
  const entityId = '01994f46-5fa6-7a20-b9ab-2a7bbcc70003';
  const operationId = 'reminder-operation-1';
  await database.insert('reminders', <String, Object?>{
    'id': entityId,
    'payload': jsonEncode(<String, Object?>{
      'id': entityId,
      'reminder_type': 'quran_review',
      'schedule': const <String, Object?>{
        'kind': 'local_time',
        'local_time': '09:00:00',
      },
      'review_target': const <String, Object?>{
        'start': <String, Object?>{
          'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc71001',
          'surah_number': 2,
          'ayah_number': 5,
        },
        'end': <String, Object?>{
          'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc71002',
          'surah_number': 2,
          'ayah_number': 7,
        },
      },
      'weekdays_mask': 31,
      'timezone': const <String, Object?>{'mode': 'device_local'},
      'signal': 'sound',
      'is_enabled': true,
      'revision': baseRevision,
      'client_updated_at': '2026-09-01T10:00:00Z',
      'deleted_at': null,
      'updated_at': '2026-09-01T10:00:00Z',
    }),
    'revision': baseRevision,
    'is_deleted': 0,
    'updated_at': '2026-09-01T10:00:00Z',
  });
  await database.insert('outbox', <String, Object?>{
    'operation_id': operationId,
    'entity_type': 'reminder',
    'entity_id': entityId,
    'payload': jsonEncode(<String, Object?>{
      'operation_id': operationId,
      'entity_type': 'reminder',
      'entity_id': entityId,
      'action': 'upsert',
      'base_revision': baseRevision,
      'client_updated_at': '2026-09-01T10:00:00Z',
      'payload': const <String, Object?>{
        'reminder_type': 'quran_review',
        'schedule': <String, Object?>{
          'kind': 'local_time',
          'local_time': '09:00:00',
        },
        'review_target': <String, Object?>{
          'start_ayah_id': '01994f46-5fa6-7a20-b9ab-2a7bbcc71001',
          'end_ayah_id': '01994f46-5fa6-7a20-b9ab-2a7bbcc71002',
        },
        'weekdays_mask': 31,
        'timezone': <String, Object?>{'mode': 'device_local'},
        'signal': 'sound',
        'is_enabled': true,
      },
    }),
    'attempts': 0,
    'created_at': '2026-09-01T10:00:00Z',
  });
}

Map<String, Object?> _readingPosition({
  required int revision,
  required int page,
}) => <String, Object?>{
  'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc79991',
  'entity_type': 'reading_position',
  'edition_code': 'madani-hafs',
  'page_number': page,
  'ayah': const <String, Object?>{'surah_number': 1, 'ayah_number': 1},
  'revision': revision,
  'updated_at': '2026-09-01T10:00:00Z',
};

Map<String, Object?> _bookmark({
  required String id,
  required int revision,
  int surah = 1,
  int ayah = 1,
  bool deleted = false,
}) => <String, Object?>{
  'id': id,
  'entity_type': 'bookmark',
  'edition_code': 'madani-hafs',
  'page_number': 1,
  'ayah': <String, Object?>{'surah_number': surah, 'ayah_number': ayah},
  'revision': revision,
  'deleted_at': deleted ? '2026-09-01T11:00:00Z' : null,
  'updated_at': '2026-09-01T11:00:00Z',
};

Map<String, Object?> _reminder({
  required int revision,
  required int weekdaysMask,
}) => <String, Object?>{
  'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc70003',
  'reminder_type': 'quran_review',
  'schedule': const <String, Object?>{
    'kind': 'local_time',
    'local_time': '08:00:00',
  },
  'weekdays_mask': weekdaysMask,
  'review_target': const <String, Object?>{
    'start': <String, Object?>{
      'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc72001',
      'surah_number': 1,
      'ayah_number': 1,
    },
    'end': <String, Object?>{
      'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc72002',
      'surah_number': 1,
      'ayah_number': 2,
    },
  },
  'timezone': const <String, Object?>{'mode': 'device_local'},
  'signal': 'sound',
  'is_enabled': true,
  'revision': revision,
  'client_updated_at': '2026-09-01T08:00:00Z',
  'deleted_at': null,
  'updated_at': '2026-09-01T08:00:00Z',
};

Map<String, Object?> _reminderOperationBody(
  String operationId,
  int weekdaysMask,
) => <String, Object?>{
  'operation_id': operationId,
  'entity_type': 'reminder',
  'entity_id': '01994f46-5fa6-7a20-b9ab-2a7bbcc70003',
  'action': 'upsert',
  'base_revision': 0,
  'client_updated_at': '2026-09-01T10:00:00Z',
  'payload': <String, Object?>{
    'reminder_type': 'quran_reading',
    'schedule': const <String, Object?>{
      'kind': 'local_time',
      'local_time': '09:00:00',
    },
    'weekdays_mask': weekdaysMask,
    'timezone': const <String, Object?>{'mode': 'device_local'},
    'signal': 'sound',
    'is_enabled': true,
  },
};
