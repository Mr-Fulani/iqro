import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/sync/sync_remote.dart';
import 'package:iqro_mobile/core/sync/sync_service.dart';
import 'package:iqro_mobile/core/sync/sync_store.dart';

void main() {
  test('retries a rebased revision conflict in the same sync run', () async {
    final original = _entityOperation(
      operationId: 'operation-1',
      baseRevision: 2,
    );
    final store = _FakeStore(entities: <SyncOutboxEntry>[original]);
    var pushes = 0;
    final remote = _FakeRemote(
      onPost: (path, data) {
        expect(path, '/sync/push');
        pushes++;
        final operation = ((data! as Map)['operations']! as List).single as Map;
        final operationId = operation['operation_id']!.toString();
        if (pushes == 1) {
          return <String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'operation_id': operationId,
                'outcome': 'conflict',
                'conflict_reason': 'revision_mismatch',
                'entity': _readingPosition(revision: 3, page: 4),
              },
            ],
          };
        }
        return <String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'operation_id': operationId,
              'outcome': 'accepted',
              'entity': _readingPosition(revision: 4, page: 9),
            },
          ],
        };
      },
      onGet: (_, _) => _incremental(cursor: 4),
    );

    final report = await SyncService.withDependencies(
      remote: remote,
      store: store,
    ).synchronize();

    expect(report.status, SyncStatus.idle);
    expect(report.pushed, 1);
    expect(report.pending, 0);
    expect(report.shouldRetry, isFalse);
    expect(pushes, 2);
    expect(store.conflictsResolved, 1);
  });

  test(
    'cursor expiry replaces the snapshot and resumes incremental pull',
    () async {
      final store = _FakeStore();
      var incrementalCalls = 0;
      final remote = _FakeRemote(
        onGet: (path, query) {
          expect(path, '/sync/pull');
          if (query?['full_resync'] == true) {
            return <String, Object?>{
              'mode': 'full_resync',
              'entities': <Object?>[_readingPosition(revision: 5, page: 12)],
              'snapshot_cursor': 8,
              'next_page_token': null,
              'has_more': false,
            };
          }
          incrementalCalls++;
          if (incrementalCalls == 1) {
            throw const ApiException(
              message: 'Cursor expired',
              code: 'sync_cursor_expired',
              statusCode: 410,
            );
          }
          return _incremental(cursor: 8);
        },
      );

      final report = await SyncService.withDependencies(
        remote: remote,
        store: store,
      ).synchronize();

      expect(report.status, SyncStatus.idle);
      expect(report.pulled, 1);
      expect(store.snapshotReplacements, 1);
      expect(store.cursor, 8);
      expect(incrementalCalls, 3);
    },
  );

  test(
    'full resync failure becomes a retryable report and does not throw',
    () async {
      final store = _FakeStore();
      final remote = _FakeRemote(
        onGet: (_, query) {
          if (query?['full_resync'] == true) {
            throw const ApiException(
              message: 'Temporary server error',
              statusCode: 503,
            );
          }
          throw const ApiException(
            message: 'Cursor expired',
            code: 'sync_cursor_expired',
            statusCode: 410,
          );
        },
      );

      final report = await SyncService.withDependencies(
        remote: remote,
        store: store,
      ).synchronize();

      expect(report.status, SyncStatus.failed);
      expect(report.shouldRetry, isTrue);
      expect(store.snapshotReplacements, 0);
    },
  );

  test(
    'failed auxiliary delivery remains pending and requests retry',
    () async {
      final share = _auxiliaryOperation('share-1', 'share_event');
      final store = _FakeStore(auxiliary: <SyncOutboxEntry>[share]);
      final remote = _FakeRemote(
        onPost: (_, _) => throw const ApiException(
          message: 'Temporary server error',
          statusCode: 503,
        ),
        onGet: (_, _) => _incremental(cursor: 0),
      );

      final report = await SyncService.withDependencies(
        remote: remote,
        store: store,
      ).synchronize();

      expect(report.status, SyncStatus.failed);
      expect(report.pending, 1);
      expect(report.shouldRetry, isTrue);
      expect(store.failureCounts['share-1'], 1);
    },
  );

  test(
    'omitted push result fails safely without acknowledging outbox',
    () async {
      final operation = _entityOperation(
        operationId: 'operation-1',
        baseRevision: 0,
      );
      final store = _FakeStore(entities: <SyncOutboxEntry>[operation]);
      final remote = _FakeRemote(
        onPost: (_, _) => <String, Object?>{'results': const <Object?>[]},
      );

      final report = await SyncService.withDependencies(
        remote: remote,
        store: store,
      ).synchronize();

      expect(report.status, SyncStatus.failed);
      expect(report.pending, 1);
      expect(report.shouldRetry, isTrue);
      expect(store.failureCounts['operation-1'], 1);
    },
  );

  test('concurrent callers share one synchronization flight', () async {
    final gate = Completer<Object?>();
    final store = _FakeStore();
    var gets = 0;
    final remote = _FakeRemote(
      onGet: (_, _) {
        gets++;
        return gate.future;
      },
    );
    final service = SyncService.withDependencies(remote: remote, store: store);

    final first = service.synchronize();
    final second = service.synchronize();
    expect(identical(first, second), isTrue);
    gate.complete(_incremental(cursor: 0));
    await Future.wait(<Future<SyncReport>>[first, second]);

    expect(gets, 1);
  });
}

class _FakeRemote implements SyncRemote {
  _FakeRemote({this.onGet, this.onPost});

  final FutureOr<Object?> Function(String path, Map<String, Object?>? query)?
  onGet;
  final FutureOr<Object?> Function(String path, Object? data)? onPost;

  @override
  Future<Object?> get(String path, {Map<String, Object?>? query}) async =>
      onGet?.call(path, query) ?? _incremental(cursor: 0);

  @override
  Future<Object?> post(String path, {Object? data}) async =>
      onPost?.call(path, data);

  @override
  Future<Object?> put(String path, {Object? data}) async => null;
}

class _FakeStore implements SyncStore {
  _FakeStore({
    List<SyncOutboxEntry>? auxiliary,
    List<SyncOutboxEntry>? entities,
  }) : auxiliary = auxiliary ?? <SyncOutboxEntry>[],
       entities = entities ?? <SyncOutboxEntry>[];

  final List<SyncOutboxEntry> auxiliary;
  final List<SyncOutboxEntry> entities;
  final Map<String, int> failureCounts = <String, int>{};
  int cursor = 0;
  int snapshotReplacements = 0;
  int conflictsResolved = 0;

  @override
  Future<void> acknowledge(String operationId) async {
    auxiliary.removeWhere((row) => row.operationId == operationId);
    entities.removeWhere((row) => row.operationId == operationId);
  }

  @override
  Future<void> acceptOperation(String operationId, Object? entity) =>
      acknowledge(operationId);

  @override
  Future<void> applyRemoteEntity(Object? entity) async {}

  @override
  Future<void> markFailure(String operationId, String error) async {
    failureCounts.update(operationId, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  Future<List<SyncOutboxEntry>> pendingAuxiliary({int limit = 100}) async =>
      auxiliary.take(limit).toList(growable: false);

  @override
  Future<int> pendingCount() async => auxiliary.length + entities.length;

  @override
  Future<List<SyncOutboxEntry>> pendingEntities({int? limit = 100}) async =>
      limit == null
      ? List<SyncOutboxEntry>.unmodifiable(entities)
      : entities.take(limit).toList(growable: false);

  @override
  Future<int> readCursor() async => cursor;

  @override
  Future<void> replaceAuthoritativeSnapshot(
    List<Object?> entities,
    int snapshotCursor,
  ) async {
    snapshotReplacements++;
    cursor = snapshotCursor;
  }

  @override
  Future<SyncConflictResolution> resolveConflict(
    SyncOutboxEntry operation,
    Map<String, Object?> result,
  ) async {
    conflictsResolved++;
    final replacement = _entityOperation(
      operationId: 'rebased-operation',
      baseRevision: 3,
    );
    entities
      ..removeWhere((row) => row.operationId == operation.operationId)
      ..add(replacement);
    return SyncConflictResolution.rebased;
  }

  @override
  Future<void> writeCursor(int cursor) async {
    this.cursor = cursor;
  }
}

SyncOutboxEntry _entityOperation({
  required String operationId,
  required int baseRevision,
}) => SyncOutboxEntry.fromRow(<String, Object?>{
  'operation_id': operationId,
  'entity_type': 'reading_position',
  'entity_id': '01994f46-5fa6-7a20-b9ab-2a7bbcc79991',
  'payload':
      '{"operation_id":"$operationId","entity_type":"reading_position",'
      '"entity_id":"01994f46-5fa6-7a20-b9ab-2a7bbcc79991",'
      '"action":"upsert","base_revision":$baseRevision,'
      '"client_updated_at":"2026-09-01T10:00:00Z",'
      '"payload":{"edition_code":"madani-hafs","page_number":9,'
      '"surah_number":2,"ayah_number":5,"progress_percent":"1.49",'
      '"last_read_at":"2026-09-01T10:00:00Z"}}',
  'attempts': 0,
  'created_at': '2026-09-01T10:00:00Z',
});

SyncOutboxEntry _auxiliaryOperation(String id, String type) =>
    SyncOutboxEntry.fromRow(<String, Object?>{
      'operation_id': id,
      'entity_type': type,
      'entity_id': null,
      'payload': '{"event":"share_sheet_opened"}',
      'attempts': 0,
      'created_at': '2026-09-01T10:00:00Z',
    });

Map<String, Object?> _incremental({required int cursor}) => <String, Object?>{
  'mode': 'incremental',
  'changes': const <Object?>[],
  'next_cursor': cursor,
  'has_more': false,
};

Map<String, Object?> _readingPosition({
  required int revision,
  required int page,
}) => <String, Object?>{
  'id': '01994f46-5fa6-7a20-b9ab-2a7bbcc79991',
  'entity_type': 'reading_position',
  'edition_code': 'madani-hafs',
  'page_number': page,
  'ayah': <String, Object?>{
    'surah_number': page == 9 ? 2 : 1,
    'ayah_number': page == 9 ? 5 : 1,
  },
  'revision': revision,
  'updated_at': '2026-09-01T10:00:00Z',
};
