import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class SyncOutboxEntry {
  SyncOutboxEntry._({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.body,
    required this.attempts,
    required this.createdAt,
  });

  factory SyncOutboxEntry.fromRow(Map<String, Object?> row) {
    final rawBody = jsonDecode(row['payload']! as String);
    if (rawBody is! Map) {
      throw const FormatException('Outbox payload must be a JSON object');
    }
    return SyncOutboxEntry._(
      operationId: row['operation_id']! as String,
      entityType: row['entity_type']! as String,
      entityId: row['entity_id']?.toString(),
      body: Map<String, Object?>.from(rawBody),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    );
  }

  final String operationId;
  final String entityType;
  final String? entityId;
  final Map<String, Object?> body;
  final int attempts;
  final DateTime createdAt;

  String get action => body['action']?.toString() ?? 'upsert';
  int get baseRevision => (body['base_revision'] as num?)?.toInt() ?? 0;

  Map<String, Object?> get intent {
    final raw = body['payload'];
    return raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
  }

  String get logicalEntityKey {
    if (!const <String>{
      'reading_position',
      'bookmark',
      'reminder',
    }.contains(entityType)) {
      throw FormatException('Unsupported sync entity type: $entityType');
    }
    if (entityType == 'reading_position') {
      final edition = intent['edition_code']?.toString();
      if (edition == null || edition.isEmpty) {
        throw const FormatException('Reading position edition is missing');
      }
      return '$entityType:$edition';
    }
    final id = entityId;
    if (id == null || id.isEmpty) {
      throw const FormatException('Outbox entity identity is missing');
    }
    return '$entityType:$id';
  }

  void ensureMatchesRemoteEntity(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Remote sync entity must be an object');
    }
    late final Map<String, Object?> entity;
    try {
      entity = Map<String, Object?>.from(raw);
    } on Object {
      throw const FormatException('Remote sync entity must be an object');
    }
    final type = entity['entity_type']?.toString();
    if (!const <String>{
      'reading_position',
      'bookmark',
      'reminder',
    }.contains(type)) {
      throw FormatException('Unsupported sync entity type: $type');
    }
    final revision = (entity['revision'] as num?)?.toInt();
    if (revision == null || revision < 1) {
      throw const FormatException('Remote entity revision is invalid');
    }
    late final String remoteKey;
    if (type == 'reading_position') {
      final edition = entity['edition_code']?.toString();
      final id = entity['id']?.toString();
      if (edition == null || edition.isEmpty || id == null || id.isEmpty) {
        throw const FormatException('Reading position edition is missing');
      }
      remoteKey = '$type:$edition';
    } else {
      final id = entity['id']?.toString();
      if (id == null || id.isEmpty) {
        throw const FormatException('Remote entity identity is missing');
      }
      remoteKey = '$type:$id';
    }
    if (remoteKey != logicalEntityKey) {
      throw const FormatException(
        'Remote sync entity does not match its operation',
      );
    }
  }
}

enum SyncConflictResolution { rebased, satisfied, unresolved }

abstract interface class SyncStore {
  Future<List<SyncOutboxEntry>> pendingAuxiliary({int limit = 100});

  Future<List<SyncOutboxEntry>> pendingEntities({int? limit = 100});

  Future<int> pendingCount();

  Future<void> acknowledge(String operationId);

  Future<void> markFailure(String operationId, String error);

  Future<void> rejectDuaFavorite(SyncOutboxEntry operation);

  Future<int> readCursor();

  Future<void> writeCursor(int cursor);

  Future<void> acceptOperation(SyncOutboxEntry operation, Object? entity);

  Future<void> applyRemoteEntity(Object? entity);

  Future<void> replaceAuthoritativeSnapshot(
    List<Object?> entities,
    int snapshotCursor,
  );

  Future<SyncConflictResolution> resolveConflict(
    SyncOutboxEntry operation,
    Map<String, Object?> result,
  );
}

class SqliteSyncStore implements SyncStore {
  SqliteSyncStore(
    this._database, {
    required String ownerId,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
    void Function()? guard,
  }) : _ownerId = ownerId,
       _uuid = uuid,
       _now = now ?? _utcNow,
       _guard = guard;

  static const _entityTypes = <String>{
    'reading_position',
    'bookmark',
    'reminder',
  };

  final Database _database;
  final String _ownerId;
  final Uuid _uuid;
  final DateTime Function() _now;
  final void Function()? _guard;

  @override
  Future<List<SyncOutboxEntry>> pendingAuxiliary({int limit = 100}) async {
    _guard?.call();
    final rows = await _database.query(
      'outbox',
      where:
          "owner_id = ? AND entity_type NOT IN "
          "('reading_position', 'bookmark', 'reminder')",
      whereArgs: <Object?>[_ownerId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    _guard?.call();
    return rows.map(SyncOutboxEntry.fromRow).toList(growable: false);
  }

  @override
  Future<List<SyncOutboxEntry>> pendingEntities({int? limit = 100}) async {
    _guard?.call();
    final rows = await _database.query(
      'outbox',
      where:
          "owner_id = ? AND entity_type IN "
          "('reading_position', 'bookmark', 'reminder')",
      whereArgs: <Object?>[_ownerId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    _guard?.call();
    return rows.map(SyncOutboxEntry.fromRow).toList(growable: false);
  }

  @override
  Future<int> pendingCount() async {
    _guard?.call();
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS pending_count FROM outbox WHERE owner_id = ?',
      <Object?>[_ownerId],
    );
    _guard?.call();
    return (rows.single['pending_count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> acknowledge(String operationId) async {
    await _database.transaction((transaction) async {
      _guard?.call();
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[_ownerId, operationId],
      );
    });
  }

  @override
  Future<void> markFailure(String operationId, String error) async {
    await _database.transaction((transaction) async {
      _guard?.call();
      await transaction.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
        'WHERE owner_id = ? AND operation_id = ?',
        <Object?>[error, _ownerId, operationId],
      );
    });
  }

  @override
  Future<void> rejectDuaFavorite(SyncOutboxEntry operation) async {
    if (operation.entityType != 'dua_favorite') {
      throw const FormatException('Expected a Dua favorite operation');
    }
    final favoriteKey = operation.entityId;
    if (favoriteKey == null || favoriteKey.isEmpty) {
      throw const FormatException('Dua favorite identity is missing');
    }
    await _database.transaction((transaction) async {
      _guard?.call();
      final current = await transaction.query(
        'outbox',
        columns: const <String>['operation_id'],
        where: 'owner_id = ? AND operation_id = ? AND entity_id = ?',
        whereArgs: <Object?>[_ownerId, operation.operationId, favoriteKey],
        limit: 1,
      );
      if (current.isEmpty) return;
      await transaction.delete(
        'favorites',
        where: 'owner_id = ? AND item_key = ?',
        whereArgs: <Object?>[_ownerId, favoriteKey],
      );
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[_ownerId, operation.operationId],
      );
    });
  }

  @override
  Future<int> readCursor() async {
    _guard?.call();
    final rows = await _database.query(
      'app_state',
      columns: const <String>['payload'],
      where: 'owner_id = ? AND state_key = ?',
      whereArgs: <Object?>[_ownerId, 'sync_cursor'],
      limit: 1,
    );
    _guard?.call();
    if (rows.isEmpty) return 0;
    final decoded = jsonDecode(rows.single['payload']! as String);
    return decoded is Map ? (decoded['value'] as num?)?.toInt() ?? 0 : 0;
  }

  @override
  Future<void> writeCursor(int cursor) async {
    await _database.transaction((transaction) async {
      _guard?.call();
      await _writeCursor(transaction, cursor);
    });
  }

  @override
  Future<void> acceptOperation(
    SyncOutboxEntry operation,
    Object? entity,
  ) async {
    final normalized = _entityMap(entity);
    final expectedKey = _operationKey(operation);
    operation.ensureMatchesRemoteEntity(normalized);
    await _database.transaction((transaction) async {
      _guard?.call();
      final currentRows = await transaction.query(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[_ownerId, operation.operationId],
        limit: 1,
      );
      if (currentRows.isNotEmpty &&
          _operationKey(SyncOutboxEntry.fromRow(currentRows.single)) !=
              expectedKey) {
        throw const FormatException('Accepted sync operation was replaced');
      }
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[_ownerId, operation.operationId],
      );
      await _applyRemoteWithPendingIntent(transaction, normalized);
    });
  }

  @override
  Future<void> applyRemoteEntity(Object? entity) async {
    await _database.transaction((transaction) async {
      _guard?.call();
      await _applyRemoteWithPendingIntent(transaction, entity);
    });
  }

  @override
  Future<void> replaceAuthoritativeSnapshot(
    List<Object?> entities,
    int snapshotCursor,
  ) async {
    if (snapshotCursor < 0) {
      throw const FormatException('Snapshot cursor must be non-negative');
    }
    final normalized = entities.map(_entityMap).toList(growable: false);
    final snapshotByKey = _uniqueSnapshotByKey(normalized);

    await _database.transaction((transaction) async {
      _guard?.call();
      final rows = await transaction.query(
        'outbox',
        where:
            "owner_id = ? AND entity_type IN "
            "('reading_position', 'bookmark', 'reminder')",
        whereArgs: <Object?>[_ownerId],
        orderBy: 'created_at ASC',
      );
      final latestOperations = <String, SyncOutboxEntry>{};
      for (final row in rows) {
        final operation = SyncOutboxEntry.fromRow(row);
        latestOperations[_operationKey(operation)] = operation;
      }
      final localDesiredByKey = <String, Map<String, Object?>?>{};
      for (final entry in latestOperations.entries) {
        localDesiredByKey[entry.key] = await _localEntityForOperation(
          transaction,
          entry.value,
        );
      }
      await transaction.delete(
        'reading_positions',
        where: 'owner_id = ?',
        whereArgs: <Object?>[_ownerId],
      );
      await transaction.delete(
        'bookmarks',
        where: 'owner_id = ?',
        whereArgs: <Object?>[_ownerId],
      );
      await transaction.delete(
        'reminders',
        where: 'owner_id = ?',
        whereArgs: <Object?>[_ownerId],
      );
      await transaction.delete(
        'outbox',
        where:
            "owner_id = ? AND entity_type IN "
            "('reading_position', 'bookmark', 'reminder')",
        whereArgs: <Object?>[_ownerId],
      );
      for (final entity in normalized) {
        await _applyRemoteRow(transaction, entity, authoritative: true);
      }
      for (final operation in latestOperations.values) {
        await _rebaseOperation(
          transaction,
          operation,
          snapshotByKey[_operationKey(operation)],
          localDesired: localDesiredByKey[_operationKey(operation)],
        );
      }
      await _writeCursor(transaction, snapshotCursor);
    });
  }

  Future<void> replaceAuthoritativeReminderSnapshot(
    List<Map<String, Object?>> reminders,
  ) async {
    final normalized = <Map<String, Object?>>[];
    for (final reminder in reminders) {
      final suppliedType = reminder['entity_type']?.toString();
      if (suppliedType != null && suppliedType != 'reminder') {
        throw const FormatException('Reminder snapshot contains another type');
      }
      normalized.add(
        _entityMap(<String, Object?>{...reminder, 'entity_type': 'reminder'}),
      );
    }
    final snapshotByKey = _uniqueSnapshotByKey(normalized);
    await _database.transaction((transaction) async {
      _guard?.call();
      final rows = await transaction.query(
        'outbox',
        where: 'owner_id = ? AND entity_type = ?',
        whereArgs: <Object?>[_ownerId, 'reminder'],
        orderBy: 'created_at ASC',
      );
      final latestOperations = <String, SyncOutboxEntry>{};
      for (final row in rows) {
        final operation = SyncOutboxEntry.fromRow(row);
        latestOperations[_operationKey(operation)] = operation;
      }
      final localDesiredByKey = <String, Map<String, Object?>?>{};
      for (final entry in latestOperations.entries) {
        localDesiredByKey[entry.key] = await _localEntityForOperation(
          transaction,
          entry.value,
        );
      }
      await transaction.delete(
        'reminders',
        where: 'owner_id = ?',
        whereArgs: <Object?>[_ownerId],
      );
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND entity_type = ?',
        whereArgs: <Object?>[_ownerId, 'reminder'],
      );
      for (final reminder in normalized) {
        await _applyRemoteRow(transaction, reminder, authoritative: true);
      }
      for (final operation in latestOperations.values) {
        await _rebaseOperation(
          transaction,
          operation,
          snapshotByKey[_operationKey(operation)],
          localDesired: localDesiredByKey[_operationKey(operation)],
        );
      }
    });
  }

  @override
  Future<SyncConflictResolution> resolveConflict(
    SyncOutboxEntry operation,
    Map<String, Object?> result,
  ) async {
    final reason = result['conflict_reason']?.toString() ?? 'sync_conflict';
    if (!const <String>{
      'revision_mismatch',
      'entity_missing',
      'entity_identity_mismatch',
      'entity_id_unavailable',
      'entity_id_not_reusable',
    }.contains(reason)) {
      await markFailure(operation.operationId, reason);
      return SyncConflictResolution.unresolved;
    }
    final rawEntity = result['entity'];
    final remote = rawEntity is Map ? _entityMap(rawEntity) : null;
    if (remote != null) operation.ensureMatchesRemoteEntity(remote);
    return _database.transaction((transaction) async {
      _guard?.call();
      final current = await _pendingOperationForOperation(
        transaction,
        operation,
      );
      if (current == null) {
        if (remote != null) {
          await _applyRemoteRow(transaction, remote, authoritative: false);
        }
        return SyncConflictResolution.satisfied;
      }
      final localDesired = await _localEntityForOperation(transaction, current);
      if (remote != null) {
        await _applyRemoteRow(transaction, remote, authoritative: false);
      }
      final remoteRevision = (remote?['revision'] as num?)?.toInt() ?? 0;
      final baseline = remote != null && current.baseRevision > remoteRevision
          ? <String, Object?>{
              ...remote,
              'id': current.entityId ?? remote['id'],
              'revision': current.baseRevision,
              'deleted_at': null,
            }
          : remote;
      final resolution = await _rebaseOperation(
        transaction,
        current,
        baseline,
        forceNewOperation: true,
        forceRemap:
            remote == null &&
            (reason == 'entity_id_unavailable' ||
                reason == 'entity_id_not_reusable'),
        localDesired: localDesired,
      );
      return resolution;
    });
  }

  Future<void> _applyRemoteWithPendingIntent(
    DatabaseExecutor transaction,
    Object? raw,
  ) async {
    final entity = _entityMap(raw);
    final pending = await _pendingOperationForEntity(transaction, entity);
    final localDesired = pending == null
        ? null
        : await _localEntityForOperation(transaction, pending);
    final applied = await _applyRemoteRow(
      transaction,
      entity,
      authoritative: false,
    );
    if (pending != null && applied) {
      await _rebaseOperation(
        transaction,
        pending,
        entity,
        localDesired: localDesired,
      );
    }
  }

  Future<SyncOutboxEntry?> _pendingOperationForEntity(
    DatabaseExecutor transaction,
    Map<String, Object?> entity,
  ) async {
    final type = entity['entity_type']!.toString();
    final rows = await transaction.query(
      'outbox',
      where: 'owner_id = ? AND entity_type = ?',
      whereArgs: <Object?>[_ownerId, type],
      orderBy: 'created_at DESC',
    );
    final key = _entityKey(entity);
    for (final row in rows) {
      final operation = SyncOutboxEntry.fromRow(row);
      if (_operationKey(operation) == key) return operation;
    }
    return null;
  }

  Future<SyncOutboxEntry?> _pendingOperationForOperation(
    DatabaseExecutor transaction,
    SyncOutboxEntry operation,
  ) async {
    final rows = await transaction.query(
      'outbox',
      where: 'owner_id = ? AND entity_type = ?',
      whereArgs: <Object?>[_ownerId, operation.entityType],
      orderBy: 'created_at DESC, rowid DESC',
    );
    final key = _operationKey(operation);
    for (final row in rows) {
      final current = SyncOutboxEntry.fromRow(row);
      if (_operationKey(current) == key) return current;
    }
    return null;
  }

  Future<SyncConflictResolution> _rebaseOperation(
    DatabaseExecutor transaction,
    SyncOutboxEntry operation,
    Map<String, Object?>? remote, {
    bool forceNewOperation = false,
    bool forceRemap = false,
    Map<String, Object?>? localDesired,
  }) async {
    var entityId =
        operation.entityId ?? operation.body['entity_id']?.toString();
    if (entityId == null || entityId.isEmpty) {
      await _markFailure(
        transaction,
        operation.operationId,
        'missing_entity_id',
      );
      return SyncConflictResolution.unresolved;
    }
    final remoteRevision = (remote?['revision'] as num?)?.toInt() ?? 0;
    final remoteDeleted = remote?['deleted_at'] != null;
    if (operation.action == 'delete' && (remote == null || remoteDeleted)) {
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[_ownerId, operation.operationId],
      );
      await _removeLocalEntity(transaction, operation.entityType, entityId);
      if (remote != null) {
        await _applyRemoteRow(transaction, remote, authoritative: true);
      }
      return SyncConflictResolution.satisfied;
    }

    var baseRevision = remoteRevision;
    var remapped = false;
    if (forceRemap) {
      entityId = operation.entityType == 'reading_position'
          ? _uuid.v4()
          : _uuid.v7();
      baseRevision = 0;
      remapped = true;
    } else if (remote != null) {
      entityId = remote['id']?.toString() ?? entityId;
      if (remoteDeleted && operation.entityType == 'reminder') {
        entityId = _uuid.v7();
        baseRevision = 0;
        remapped = true;
      }
    } else if (operation.baseRevision > 0) {
      entityId = operation.entityType == 'reading_position'
          ? _uuid.v4()
          : _uuid.v7();
      baseRevision = 0;
      remapped = true;
    }

    final baseChanged = operation.baseRevision != baseRevision;
    final identityChanged = entityId != operation.entityId;
    final operationId = forceNewOperation || baseChanged || identityChanged
        ? _uuid.v4()
        : operation.operationId;
    final body = <String, Object?>{
      ...operation.body,
      'operation_id': operationId,
      'entity_type': operation.entityType,
      'entity_id': entityId,
      'base_revision': baseRevision,
    };
    if (remapped && operation.action == 'upsert') {
      body['action'] = 'upsert';
    }

    await transaction.delete(
      'outbox',
      where:
          'owner_id = ? AND entity_type = ? '
          'AND (entity_id = ? OR operation_id = ?)',
      whereArgs: <Object?>[
        _ownerId,
        operation.entityType,
        operation.entityId,
        operation.operationId,
      ],
    );
    if (identityChanged && operation.entityId != null) {
      await _removeLocalEntity(
        transaction,
        operation.entityType,
        operation.entityId!,
      );
    }
    await transaction.insert('outbox', <String, Object?>{
      'owner_id': _ownerId,
      'operation_id': operationId,
      'entity_type': operation.entityType,
      'entity_id': entityId,
      'payload': jsonEncode(body),
      'attempts': 0,
      'created_at': _now().toUtc().toIso8601String(),
      'last_error': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _applyLocalIntent(
      transaction,
      operation.entityType,
      entityId,
      body,
      remote,
      baseRevision,
      localDesired,
    );
    return SyncConflictResolution.rebased;
  }

  Future<void> _applyLocalIntent(
    DatabaseExecutor transaction,
    String type,
    String entityId,
    Map<String, Object?> body,
    Map<String, Object?>? remote,
    int baseRevision,
    Map<String, Object?>? localDesired,
  ) async {
    final rawIntent = body['payload'];
    final intent = rawIntent is Map
        ? Map<String, Object?>.from(rawIntent)
        : const <String, Object?>{};
    final clientUpdatedAt =
        body['client_updated_at']?.toString() ??
        _now().toUtc().toIso8601String();
    if (type == 'reading_position') {
      final remoteAyah = _ayahMap(remote?['ayah']);
      final edition =
          intent['edition_code']?.toString() ??
          localDesired?['edition_code']?.toString() ??
          remote?['edition_code']?.toString() ??
          'madani-hafs';
      await transaction.insert('reading_positions', <String, Object?>{
        'owner_id': _ownerId,
        'edition': edition,
        'entity_id': entityId,
        'surah':
            (intent['surah_number'] as num?)?.toInt() ??
            (localDesired?['surah_number'] as num?)?.toInt() ??
            (remoteAyah['surah_number'] as num?)?.toInt() ??
            1,
        'ayah':
            (intent['ayah_number'] as num?)?.toInt() ??
            (localDesired?['ayah_number'] as num?)?.toInt() ??
            (remoteAyah['ayah_number'] as num?)?.toInt() ??
            1,
        'page':
            (intent['page_number'] as num?)?.toInt() ??
            (localDesired?['page_number'] as num?)?.toInt() ??
            (remote?['page_number'] as num?)?.toInt() ??
            1,
        'server_revision': baseRevision,
        'dirty': 1,
        'updated_at': clientUpdatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
    if (type == 'bookmark') {
      final remoteAyah = _ayahMap(remote?['ayah']);
      await transaction.insert('bookmarks', <String, Object?>{
        'owner_id': _ownerId,
        'id': entityId,
        'edition':
            intent['edition_code']?.toString() ??
            localDesired?['edition_code']?.toString() ??
            remote?['edition_code']?.toString() ??
            'madani-hafs',
        'surah':
            (intent['surah_number'] as num?)?.toInt() ??
            (localDesired?['surah_number'] as num?)?.toInt() ??
            (remoteAyah['surah_number'] as num?)?.toInt() ??
            1,
        'ayah':
            (intent['ayah_number'] as num?)?.toInt() ??
            (localDesired?['ayah_number'] as num?)?.toInt() ??
            (remoteAyah['ayah_number'] as num?)?.toInt() ??
            1,
        'server_revision': baseRevision,
        'is_deleted':
            body['action'] == 'delete' || localDesired?['deleted_at'] != null
            ? 1
            : 0,
        'updated_at': clientUpdatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }
    if (type == 'reminder') {
      final desired = localDesired ?? intent;
      final merged = <String, Object?>{
        ...?remote,
        ...desired,
        'id': entityId,
        'entity_type': 'reminder',
        'revision': baseRevision,
        'client_updated_at': clientUpdatedAt,
        'deleted_at': desired['deleted_at'] != null
            ? clientUpdatedAt
            : desired['deleted_at'],
      };
      await transaction.insert('reminders', <String, Object?>{
        'owner_id': _ownerId,
        'id': entityId,
        'payload': jsonEncode(merged),
        'revision': baseRevision,
        'is_deleted': desired['deleted_at'] != null ? 1 : 0,
        'updated_at': clientUpdatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, Object?>?> _localEntityForOperation(
    DatabaseExecutor executor,
    SyncOutboxEntry operation,
  ) async {
    if (operation.entityType == 'reading_position') {
      final edition = operation.intent['edition_code']?.toString();
      if (edition == null || edition.isEmpty) return null;
      final rows = await executor.query(
        'reading_positions',
        where: 'owner_id = ? AND edition = ?',
        whereArgs: <Object?>[_ownerId, edition],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return <String, Object?>{
        'id': row['entity_id'],
        'entity_type': 'reading_position',
        'edition_code': row['edition'],
        'page_number': row['page'],
        'surah_number': row['surah'],
        'ayah_number': row['ayah'],
        'revision': row['server_revision'],
        'updated_at': row['updated_at'],
      };
    }
    final id = operation.entityId;
    if (id == null || id.isEmpty) return null;
    if (operation.entityType == 'bookmark') {
      final rows = await executor.query(
        'bookmarks',
        where: 'owner_id = ? AND id = ?',
        whereArgs: <Object?>[_ownerId, id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return <String, Object?>{
        'id': row['id'],
        'entity_type': 'bookmark',
        'edition_code': row['edition'],
        'surah_number': row['surah'],
        'ayah_number': row['ayah'],
        'revision': row['server_revision'],
        'deleted_at': (row['is_deleted'] as num?)?.toInt() == 1
            ? row['updated_at']
            : null,
        'updated_at': row['updated_at'],
      };
    }
    if (operation.entityType == 'reminder') {
      final rows = await executor.query(
        'reminders',
        columns: const <String>['payload'],
        where: 'owner_id = ? AND id = ?',
        whereArgs: <Object?>[_ownerId, id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final decoded = jsonDecode(rows.single['payload']! as String);
      if (decoded is! Map) return null;
      return <String, Object?>{
        ...Map<String, Object?>.from(decoded),
        'id': id,
        'entity_type': 'reminder',
      };
    }
    return null;
  }

  Future<bool> _applyRemoteRow(
    DatabaseExecutor executor,
    Map<String, Object?> entity, {
    required bool authoritative,
  }) async {
    final type = entity['entity_type']!.toString();
    final revision = (entity['revision'] as num?)?.toInt();
    if (revision == null || revision < 1) {
      throw const FormatException('Remote entity revision is invalid');
    }
    if (type == 'reading_position') {
      final edition = entity['edition_code']?.toString();
      final id = entity['id']?.toString();
      if (edition == null || edition.isEmpty || id == null || id.isEmpty) {
        throw const FormatException('Reading position identity is invalid');
      }
      if (!authoritative &&
          !await _isNewer(
            executor,
            table: 'reading_positions',
            keyColumn: 'edition',
            key: edition,
            revisionColumn: 'server_revision',
            revision: revision,
          )) {
        return false;
      }
      final ayah = _ayahMap(entity['ayah']);
      await executor.insert('reading_positions', <String, Object?>{
        'owner_id': _ownerId,
        'edition': edition,
        'entity_id': id,
        'surah': (ayah['surah_number'] as num?)?.toInt() ?? 1,
        'ayah': (ayah['ayah_number'] as num?)?.toInt() ?? 1,
        'page': (entity['page_number'] as num?)?.toInt() ?? 1,
        'server_revision': revision,
        'dirty': 0,
        'updated_at':
            entity['updated_at']?.toString() ??
            _now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
    final id = entity['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Remote entity identity is invalid');
    }
    if (type == 'bookmark') {
      if (!authoritative &&
          !await _isNewer(
            executor,
            table: 'bookmarks',
            keyColumn: 'id',
            key: id,
            revisionColumn: 'server_revision',
            revision: revision,
          )) {
        return false;
      }
      final ayah = _ayahMap(entity['ayah']);
      await executor.insert('bookmarks', <String, Object?>{
        'owner_id': _ownerId,
        'id': id,
        'edition': entity['edition_code']?.toString() ?? 'madani-hafs',
        'surah': (ayah['surah_number'] as num?)?.toInt() ?? 1,
        'ayah': (ayah['ayah_number'] as num?)?.toInt() ?? 1,
        'server_revision': revision,
        'is_deleted': entity['deleted_at'] == null ? 0 : 1,
        'updated_at':
            entity['updated_at']?.toString() ??
            _now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
    if (type == 'reminder') {
      if (!authoritative &&
          !await _isNewer(
            executor,
            table: 'reminders',
            keyColumn: 'id',
            key: id,
            revisionColumn: 'revision',
            revision: revision,
          )) {
        return false;
      }
      await executor.insert('reminders', <String, Object?>{
        'owner_id': _ownerId,
        'id': id,
        'payload': jsonEncode(entity),
        'revision': revision,
        'is_deleted': entity['deleted_at'] == null ? 0 : 1,
        'updated_at':
            entity['updated_at']?.toString() ??
            _now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
    throw FormatException('Unsupported sync entity type: $type');
  }

  Future<bool> _isNewer(
    DatabaseExecutor executor, {
    required String table,
    required String keyColumn,
    required String key,
    required String revisionColumn,
    required int revision,
  }) async {
    final rows = await executor.query(
      table,
      columns: <String>[revisionColumn],
      where: 'owner_id = ? AND $keyColumn = ?',
      whereArgs: <Object?>[_ownerId, key],
      limit: 1,
    );
    return rows.isEmpty ||
        revision > ((rows.single[revisionColumn] as num?)?.toInt() ?? 0);
  }

  Future<void> _removeLocalEntity(
    DatabaseExecutor executor,
    String type,
    String entityId,
  ) async {
    if (type == 'reading_position') {
      await executor.delete(
        'reading_positions',
        where: 'owner_id = ? AND entity_id = ?',
        whereArgs: <Object?>[_ownerId, entityId],
      );
    } else if (type == 'bookmark') {
      await executor.delete(
        'bookmarks',
        where: 'owner_id = ? AND id = ?',
        whereArgs: <Object?>[_ownerId, entityId],
      );
    } else if (type == 'reminder') {
      await executor.delete(
        'reminders',
        where: 'owner_id = ? AND id = ?',
        whereArgs: <Object?>[_ownerId, entityId],
      );
    }
  }

  Future<void> _writeCursor(DatabaseExecutor executor, int cursor) async {
    await executor.insert('app_state', <String, Object?>{
      'owner_id': _ownerId,
      'state_key': 'sync_cursor',
      'payload': jsonEncode(<String, Object?>{'value': cursor}),
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _markFailure(
    DatabaseExecutor executor,
    String operationId,
    String error,
  ) async {
    await executor.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
      'WHERE owner_id = ? AND operation_id = ?',
      <Object?>[error, _ownerId, operationId],
    );
  }

  String _operationKey(SyncOutboxEntry operation) {
    return operation.logicalEntityKey;
  }

  String _entityKey(Map<String, Object?> entity) {
    final type = entity['entity_type']?.toString();
    if (!_entityTypes.contains(type)) {
      throw FormatException('Unsupported sync entity type: $type');
    }
    if (type == 'reading_position') {
      final edition = entity['edition_code']?.toString();
      if (edition == null || edition.isEmpty) {
        throw const FormatException('Reading position edition is missing');
      }
      return '$type:$edition';
    }
    final id = entity['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Remote entity identity is missing');
    }
    return '$type:$id';
  }

  Map<String, Object?> _entityMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Remote sync entity must be an object');
    }
    final entity = Map<String, Object?>.from(raw);
    _entityKey(entity);
    return entity;
  }

  Map<String, Map<String, Object?>> _uniqueSnapshotByKey(
    List<Map<String, Object?>> entities,
  ) {
    final result = <String, Map<String, Object?>>{};
    for (final entity in entities) {
      final key = _entityKey(entity);
      if (result.containsKey(key)) {
        throw FormatException('Sync snapshot contains duplicate entity: $key');
      }
      result[key] = entity;
    }
    return result;
  }

  Map<String, Object?> _ayahMap(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : const <String, Object?>{};

  static DateTime _utcNow() => DateTime.now().toUtc();
}
