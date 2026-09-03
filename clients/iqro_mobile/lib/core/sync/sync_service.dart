import '../auth/account_scope.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/local_database.dart';
import '../utils/json_helpers.dart';
import 'sync_remote.dart';
import 'sync_store.dart';

enum SyncStatus { idle, syncing, offline, conflict, sessionExpired, failed }

class SyncReport {
  const SyncReport({
    required this.status,
    this.pushed = 0,
    this.pulled = 0,
    this.pending = 0,
    this.retryRecommended = false,
    this.message,
  });

  final SyncStatus status;
  final int pushed;
  final int pulled;
  final int pending;
  final bool retryRecommended;
  final String? message;

  bool get shouldRetry =>
      retryRecommended ||
      status == SyncStatus.offline ||
      status == SyncStatus.failed;
}

class SyncService {
  factory SyncService({
    required ApiClient api,
    required LocalDatabase database,
  }) => SyncService._scoped(api, database);

  SyncService._scoped(this._api, this._database)
    : _providedRemote = null,
      _providedStore = null;

  SyncService.withDependencies({
    required SyncRemote remote,
    required SyncStore store,
  }) : _providedRemote = remote,
       _providedStore = store,
       _api = null,
       _database = null;

  static const _maxPushBatches = 10;
  static const _maxFullResyncPages = 1000;
  static const _maxFullResyncEntities = 20000;

  final SyncRemote? _providedRemote;
  final SyncStore? _providedStore;
  final ApiClient? _api;
  final LocalDatabase? _database;
  SyncRemote? _activeRemote;
  SyncStore? _activeStore;
  AccountScopeSnapshot? _activeScope;
  Future<SyncReport>? _flight;
  AccountScopeSnapshot? _flightScope;

  SyncRemote get _remote => _activeRemote ?? _providedRemote!;
  SyncStore get _store => _activeStore ?? _providedStore!;

  Future<SyncReport> synchronize({AccountScopeSnapshot? accountScope}) async {
    final database = _database;
    final requestedScope = database == null
        ? null
        : accountScope ?? await database.captureAccount();
    if (database != null) database.ensureCurrent(requestedScope!);
    while (true) {
      final current = _flight;
      if (current != null) {
        final activeScope = _flightScope;
        if ((requestedScope == null && activeScope == null) ||
            (requestedScope != null &&
                activeScope != null &&
                requestedScope.userId == activeScope.userId &&
                requestedScope.epoch == activeScope.epoch)) {
          return current;
        }
        try {
          await current;
        } on Object {
          // A prior account's failure does not suppress this account's run.
        }
        database!.ensureCurrent(requestedScope!);
        continue;
      }
      return _startFlight(requestedScope);
    }
  }

  Future<SyncReport> _startFlight(AccountScopeSnapshot? scope) {
    late final Future<SyncReport> flight;
    flight = (scope == null ? _run() : _runScoped(scope)).whenComplete(() {
      if (identical(_flight, flight)) {
        _flight = null;
        _flightScope = null;
      }
    });
    _flight = flight;
    _flightScope = scope;
    return flight;
  }

  Future<SyncReport> _runScoped(AccountScopeSnapshot scope) async {
    final database = _database!;
    _activeScope = scope;
    _activeRemote = _ApiSyncRemote(_api!, scope);
    _activeStore = SqliteSyncStore(
      database.database,
      ownerId: scope.userId,
      guard: () => database.ensureCurrent(scope),
    );
    try {
      return await _run();
    } finally {
      _activeRemote = null;
      _activeStore = null;
      _activeScope = null;
    }
  }

  void _guardScope() {
    final scope = _activeScope;
    final database = _database;
    if (scope != null && database != null) database.ensureCurrent(scope);
  }

  Future<SyncReport> _run() async {
    final progress = _SyncProgress();
    _SyncIssue? auxiliaryIssue;
    try {
      _guardScope();
      auxiliaryIssue = await _pushAuxiliary(progress);
      var push = await _pushEntities(progress);
      if (push.conflict != null) {
        return _report(
          progress,
          status: SyncStatus.conflict,
          message: push.conflict,
        );
      }
      try {
        progress.pulled += await _pullIncremental();
      } on ApiException catch (error) {
        if (error.code != 'sync_cursor_expired') rethrow;
        progress.pulled += await _fullResync();
        progress.pulled += await _pullIncremental();

        // Full resync rebases pending local intent. Submit it immediately and
        // pull once more so this run ends on a server-confirmed state.
        push = await _pushEntities(progress);
        if (push.conflict != null) {
          return _report(
            progress,
            status: SyncStatus.conflict,
            message: push.conflict,
          );
        }
        progress.pulled += await _pullIncremental();
      }

      final pending = await _store.pendingCount();
      _guardScope();
      final issue = auxiliaryIssue;
      return SyncReport(
        status: issue?.status ?? SyncStatus.idle,
        pushed: progress.pushed,
        pulled: progress.pulled,
        pending: pending,
        retryRecommended:
            issue?.status == SyncStatus.offline ||
            issue?.status == SyncStatus.failed ||
            (pending > 0 && issue == null),
        message: issue?.message,
      );
    } on AccountScopeChanged {
      return _report(
        progress,
        status: SyncStatus.sessionExpired,
        message: 'account_scope_changed',
      );
    } on ApiException catch (error) {
      return _report(
        progress,
        status: error.statusCode == 401 || error.code == 'account_scope_changed'
            ? SyncStatus.sessionExpired
            : error.isOffline
            ? SyncStatus.offline
            : SyncStatus.failed,
        message: error.message,
      );
    } on Object catch (error) {
      return _report(
        progress,
        status: SyncStatus.failed,
        message: error.toString(),
      );
    }
  }

  Future<_SyncIssue?> _pushAuxiliary(_SyncProgress progress) async {
    _SyncIssue? issue;
    final rows = await _store.pendingAuxiliary();
    for (final row in rows) {
      _guardScope();
      try {
        if (row.entityType == 'share_event') {
          await _remote.post('/share/events', data: row.body);
        } else if (row.entityType == 'dua_favorite') {
          await _remote.put(
            '/me/dua-favorites/'
            '${row.body['collection']}/${row.body['source_number']}',
            data: <String, Object?>{
              'is_favorite': row.body['is_favorite'] == true,
            },
          );
        } else {
          await _store.markFailure(row.operationId, 'unsupported_outbox_type');
          issue ??= const _SyncIssue(
            SyncStatus.failed,
            'unsupported_outbox_type',
          );
          continue;
        }
        _guardScope();
        await _store.acknowledge(row.operationId);
        progress.pushed++;
      } on ApiException catch (error) {
        if (row.entityType == 'dua_favorite' &&
            (error.statusCode == 400 || error.statusCode == 404)) {
          await _store.rejectDuaFavorite(row);
          continue;
        }
        if (row.entityType == 'share_event' &&
            (error.statusCode == 400 || error.statusCode == 409)) {
          // The server made a terminal decision; retrying an invalid analytics
          // or favorite payload forever would permanently block the queue.
          await _store.acknowledge(row.operationId);
          continue;
        }
        await _store.markFailure(row.operationId, error.toString());
        if (error.statusCode == 401) rethrow;
        issue ??= _SyncIssue(
          error.isOffline ? SyncStatus.offline : SyncStatus.failed,
          error.message,
        );
      } on Object catch (error) {
        await _store.markFailure(row.operationId, error.toString());
        issue ??= _SyncIssue(SyncStatus.failed, error.toString());
      }
    }
    return issue;
  }

  Future<_PushResult> _pushEntities(_SyncProgress progress) async {
    for (var batchNumber = 0; batchNumber < _maxPushBatches; batchNumber++) {
      final rows = await _store.pendingEntities();
      if (rows.isEmpty) return const _PushResult();
      Object? rawResponse;
      try {
        _guardScope();
        rawResponse = await _remote.post(
          '/sync/push',
          data: <String, Object?>{
            'operations': rows.map((row) => row.body).toList(growable: false),
          },
        );
        _guardScope();
      } on Object catch (error) {
        for (final row in rows) {
          await _store.markFailure(row.operationId, error.toString());
        }
        rethrow;
      }
      final response = jsonMap(rawResponse);
      final rawResults = response['results'];
      if (rawResults is! List) {
        for (final row in rows) {
          await _store.markFailure(row.operationId, 'missing_sync_results');
        }
        throw const FormatException('Sync response has no results array');
      }
      final resultsById = <String, Map<String, Object?>>{};
      for (final raw in rawResults.whereType<Map>()) {
        final result = Map<String, Object?>.from(raw);
        final operationId = result['operation_id']?.toString();
        if (operationId == null || operationId.isEmpty) continue;
        resultsById[operationId] = result;
      }
      final expectedIds = rows.map((row) => row.operationId).toSet();
      if (resultsById.length != rawResults.length ||
          resultsById.keys.toSet().difference(expectedIds).isNotEmpty ||
          expectedIds.difference(resultsById.keys.toSet()).isNotEmpty) {
        for (final row in rows) {
          await _store.markFailure(row.operationId, 'invalid_sync_results');
        }
        throw const FormatException(
          'Sync results do not match the input operations',
        );
      }

      var bindingsAreValid = true;
      for (final row in rows) {
        final result = resultsById[row.operationId]!;
        final outcome = result['outcome'];
        final entity = result['entity'];
        try {
          if (outcome == 'accepted') {
            row.ensureMatchesRemoteEntity(entity);
          } else if (outcome == 'conflict') {
            if (entity != null) row.ensureMatchesRemoteEntity(entity);
          } else {
            bindingsAreValid = false;
          }
        } on Object {
          bindingsAreValid = false;
        }
      }
      if (!bindingsAreValid) {
        // Validate the complete response before acknowledging any row. A
        // swapped operation_id/entity pair must not partially commit a batch.
        for (final row in rows) {
          await _store.markFailure(row.operationId, 'invalid_sync_results');
        }
        throw const FormatException(
          'Sync result entity does not match its operation',
        );
      }

      var rebased = false;
      for (final row in rows) {
        final result = resultsById[row.operationId];
        if (result == null) {
          await _store.markFailure(row.operationId, 'missing_sync_result');
          throw const FormatException(
            'Sync response omitted an input operation',
          );
        }
        if (result['outcome'] == 'accepted') {
          if (result['entity'] is! Map) {
            await _store.markFailure(row.operationId, 'missing_sync_entity');
            throw const FormatException(
              'Accepted sync result has no entity snapshot',
            );
          }
          await _store.acceptOperation(row, result['entity']);
          progress.pushed++;
          continue;
        }
        if (result['outcome'] != 'conflict') {
          await _store.markFailure(row.operationId, 'unknown_sync_outcome');
          throw const FormatException('Sync outcome is invalid');
        }
        final resolution = await _store.resolveConflict(row, result);
        if (resolution == SyncConflictResolution.unresolved) {
          return _PushResult(
            conflict: result['conflict_reason']?.toString() ?? 'sync_conflict',
          );
        }
        rebased = rebased || resolution == SyncConflictResolution.rebased;
      }
      if (!rebased && rows.length < 100) {
        final remaining = await _store.pendingEntities(limit: 1);
        if (remaining.isEmpty) return const _PushResult();
      }
    }
    return const _PushResult();
  }

  Future<int> _pullIncremental() async {
    var cursor = await _store.readCursor();
    var pulled = 0;
    var hasMore = true;
    while (hasMore) {
      final response = jsonMap(
        await _remote.get(
          '/sync/pull',
          query: <String, Object?>{'cursor': cursor, 'limit': 100},
        ),
      );
      _guardScope();
      if (response['mode'] != 'incremental') {
        throw const FormatException('Expected an incremental sync response');
      }
      final rawChanges = response['changes'];
      if (rawChanges is! List) {
        throw const FormatException('Sync response has no changes array');
      }
      var lastChangeCursor = cursor;
      for (final raw in rawChanges) {
        if (raw is! Map) {
          throw const FormatException('Sync change must be an object');
        }
        final change = Map<String, Object?>.from(raw);
        final changeCursor = (change['cursor'] as num?)?.toInt();
        if (changeCursor == null || changeCursor <= lastChangeCursor) {
          throw const FormatException('Sync changes are not cursor ordered');
        }
        await _store.applyRemoteEntity(change['entity']);
        _guardScope();
        lastChangeCursor = changeCursor;
        pulled++;
      }
      final nextCursor = (response['next_cursor'] as num?)?.toInt();
      if (nextCursor == null ||
          nextCursor < lastChangeCursor ||
          nextCursor < cursor) {
        throw const FormatException('Sync next cursor is invalid');
      }
      hasMore = response['has_more'] == true;
      if (hasMore && nextCursor == cursor) {
        throw const FormatException('Sync pagination made no progress');
      }
      cursor = nextCursor;
      await _store.writeCursor(cursor);
    }
    return pulled;
  }

  Future<int> _fullResync() async {
    var token = '';
    var hasMore = true;
    int? snapshotCursor;
    final entities = <Object?>[];
    final seenTokens = <String>{};
    var pages = 0;
    while (hasMore) {
      if (++pages > _maxFullResyncPages) {
        throw const FormatException('Full resync exceeded the page limit');
      }
      final response = jsonMap(
        await _remote.get(
          '/sync/pull',
          query: <String, Object?>{
            'full_resync': true,
            'limit': 200,
            if (token.isNotEmpty) 'page_token': token,
          },
        ),
      );
      _guardScope();
      if (response['mode'] != 'full_resync') {
        throw const FormatException('Expected a full resync response');
      }
      final pageCursor = (response['snapshot_cursor'] as num?)?.toInt();
      if (pageCursor == null || pageCursor < 0) {
        throw const FormatException('Full resync cursor is invalid');
      }
      snapshotCursor ??= pageCursor;
      if (snapshotCursor != pageCursor) {
        throw const FormatException('Full resync snapshot changed mid-stream');
      }
      final pageEntities = response['entities'];
      if (pageEntities is! List) {
        throw const FormatException('Full resync has no entities array');
      }
      entities.addAll(pageEntities);
      if (entities.length > _maxFullResyncEntities) {
        throw const FormatException('Full resync exceeded the entity limit');
      }
      hasMore = response['has_more'] == true;
      final nextToken = response['next_page_token']?.toString() ?? '';
      if (hasMore &&
          (nextToken.isEmpty ||
              nextToken == token ||
              !seenTokens.add(nextToken))) {
        throw const FormatException('Full resync page token is invalid');
      }
      token = nextToken;
    }
    await _store.replaceAuthoritativeSnapshot(entities, snapshotCursor ?? 0);
    _guardScope();
    return entities.length;
  }

  Future<SyncReport> _report(
    _SyncProgress progress, {
    required SyncStatus status,
    String? message,
  }) async {
    var pending = 0;
    try {
      pending = await _store.pendingCount();
    } on Object {
      // Preserve the original failure; inability to count cannot make it safe.
    }
    return SyncReport(
      status: status,
      pushed: progress.pushed,
      pulled: progress.pulled,
      pending: pending,
      retryRecommended:
          status == SyncStatus.offline || status == SyncStatus.failed,
      message: message,
    );
  }
}

class _ApiSyncRemote implements SyncRemote {
  const _ApiSyncRemote(this._api, this._scope);

  final ApiClient _api;
  final AccountScopeSnapshot _scope;

  @override
  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _api.get(path, query: query, accountScope: _scope);

  @override
  Future<Object?> post(String path, {Object? data}) =>
      _api.post(path, data: data, accountScope: _scope);

  @override
  Future<Object?> put(String path, {Object? data}) =>
      _api.put(path, data: data, accountScope: _scope);
}

class _SyncProgress {
  int pushed = 0;
  int pulled = 0;
}

class _SyncIssue {
  const _SyncIssue(this.status, this.message);

  final SyncStatus status;
  final String message;
}

class _PushResult {
  const _PushResult({this.conflict});

  final String? conflict;
}
