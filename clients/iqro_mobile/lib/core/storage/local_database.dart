import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../auth/account_scope.dart';

class CachedValue {
  const CachedValue({
    required this.value,
    required this.updatedAt,
    this.etag,
    this.expiresAt,
  });

  final Object? value;
  final DateTime updatedAt;
  final String? etag;
  final DateTime? expiresAt;

  bool get isFresh =>
      expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc());
}

class LocalDatabase {
  LocalDatabase._(this.database, this.accountScope);

  @visibleForTesting
  LocalDatabase.forTesting(this.database, {AccountScope? accountScope})
    : accountScope = accountScope ?? AccountScope.forTesting();

  static const schemaVersion = 4;
  static const quarantinedLegacyOwner = '__legacy_unscoped__';
  final Database database;
  final AccountScope accountScope;

  static Future<LocalDatabase> open({
    required AccountScope accountScope,
    String? legacyOwnerId,
  }) async {
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, 'iqro_mobile.db'),
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // journal_mode returns a result row, so Android requires the query API.
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache_entries (
            cache_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            etag TEXT,
            updated_at TEXT NOT NULL,
            expires_at TEXT
          )
        ''');
        await _createAccountTables(db);
        await _createDeviceStateTable(db);
        await _createOfflinePackageTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createReminderTable(db);
        if (oldVersion < 3) await _createOfflinePackageTables(db);
        if (oldVersion < 4) {
          await _migrateAccountTables(db, _safeLegacyOwner(legacyOwnerId));
          await _createDeviceStateTable(db);
        }
      },
    );
    return LocalDatabase._(database, accountScope);
  }

  Future<AccountScopeSnapshot> captureAccount() => accountScope.capture();

  void ensureCurrent(AccountScopeSnapshot scope) =>
      accountScope.ensureCurrent(scope);

  Future<void> transferAccountData(
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    if (sourceOwnerId == targetOwnerId) return;
    await database.transaction((transaction) async {
      final logicalStates = await _accountTransferLogicalStates(
        transaction,
        sourceOwnerId,
        targetOwnerId,
      );
      for (final table in _accountTables) {
        if (table == 'outbox') continue;
        final key = _accountTableKeys[table]!;
        final timestamp = _accountTableTimestamps[table]!;
        final sourceRows = await transaction.query(
          table,
          where: table == 'app_state'
              ? 'owner_id = ? AND state_key <> ?'
              : 'owner_id = ?',
          whereArgs: table == 'app_state'
              ? <Object?>[sourceOwnerId, 'sync_cursor']
              : <Object?>[sourceOwnerId],
        );
        for (final sourceRow in sourceRows) {
          final keyValue = sourceRow[key];
          final targetRows = await transaction.query(
            table,
            columns: <String>[timestamp],
            where: 'owner_id = ? AND $key = ?',
            whereArgs: <Object?>[targetOwnerId, keyValue],
            limit: 1,
          );
          final logicalKey = _accountEntityLogicalKey(table, sourceRow);
          final logicalState = logicalKey == null
              ? null
              : logicalStates[logicalKey];
          final shouldCopy =
              logicalState?.sourceWins ??
              (targetRows.isEmpty ||
                  _isAfter(sourceRow[timestamp], targetRows.single[timestamp]));
          if (shouldCopy) {
            await transaction.insert(table, <String, Object?>{
              ...sourceRow,
              'owner_id': targetOwnerId,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      await _transferReconciledOutbox(
        transaction,
        sourceOwnerId,
        targetOwnerId,
        logicalStates,
      );
      await _transferAccountCache(transaction, sourceOwnerId, targetOwnerId);
      // Sync cursors are issued per server-side user and are never portable,
      // even when the server confirms a guest-to-account data merge.
      await transaction.delete(
        'app_state',
        where: 'owner_id = ? AND state_key = ?',
        whereArgs: <Object?>[targetOwnerId, 'sync_cursor'],
      );
    });
  }

  Future<void> finalizeAccountTransfer(
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    if (sourceOwnerId == targetOwnerId) return;
    await database.transaction((transaction) async {
      for (final table in _accountTables) {
        await transaction.delete(
          table,
          where: 'owner_id = ?',
          whereArgs: <Object?>[sourceOwnerId],
        );
      }
      final sourcePrefix = _accountCacheKey(sourceOwnerId, '');
      await transaction.delete(
        'cache_entries',
        where: 'cache_key LIKE ? ESCAPE \'\\\'',
        whereArgs: <Object?>['${_escapeLike(sourcePrefix)}%'],
      );
    });
  }

  Future<CachedValue?> readCache(String key) async {
    final rows = await database.query(
      'cache_entries',
      where: 'cache_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CachedValue(
      value: jsonDecode(row['payload']! as String),
      etag: row['etag'] as String?,
      updatedAt: DateTime.parse(row['updated_at']! as String),
      expiresAt: row['expires_at'] == null
          ? null
          : DateTime.parse(row['expires_at']! as String),
    );
  }

  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final now = DateTime.now().toUtc();
    await database.insert('cache_entries', <String, Object?>{
      'cache_key': key,
      'payload': jsonEncode(value),
      'etag': etag,
      'updated_at': now.toIso8601String(),
      'expires_at': now.add(maxAge).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CachedValue?> readAccountCache(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    final value = await readCache(_accountCacheKey(scope.userId, key));
    ensureCurrent(scope);
    return value;
  }

  Future<void> writeAccountCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    final now = DateTime.now().toUtc();
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.insert('cache_entries', <String, Object?>{
        'cache_key': _accountCacheKey(scope.userId, key),
        'payload': jsonEncode(value),
        'etag': etag,
        'updated_at': now.toIso8601String(),
        'expires_at': now.add(maxAge).toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, Object?>?> readState(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    final rows = await database.query(
      'app_state',
      where: 'owner_id = ? AND state_key = ?',
      whereArgs: <Object?>[scope.userId, key],
      limit: 1,
    );
    ensureCurrent(scope);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['payload']! as String);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<void> writeState(
    String key,
    Map<String, Object?> value, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.insert('app_state', <String, Object?>{
        'owner_id': scope.userId,
        'state_key': key,
        'payload': jsonEncode(value),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteState(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.delete(
        'app_state',
        where: 'owner_id = ? AND state_key = ?',
        whereArgs: <Object?>[scope.userId, key],
      );
    });
  }

  Future<Map<String, Object?>?> readDeviceState(String key) async {
    final rows = await database.query(
      'device_state',
      columns: const <String>['payload'],
      where: 'state_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['payload']! as String);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<void> writeDeviceState(String key, Map<String, Object?> value) async {
    await database.insert('device_state', <String, Object?>{
      'state_key': key,
      'payload': jsonEncode(value),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> enqueue({
    required String operationId,
    required String entityType,
    String? entityId,
    required Map<String, Object?> payload,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.insert('outbox', <String, Object?>{
        'owner_id': scope.userId,
        'operation_id': operationId,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> replaceOutboxOperation({
    required String operationId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
  }) async {
    final scope = await captureAccount();
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>[scope.userId, entityType, entityId],
      );
      await transaction.insert('outbox', <String, Object?>{
        'owner_id': scope.userId,
        'operation_id': operationId,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    ensureCurrent(scope);
  }

  Future<List<Map<String, Object?>>> readReminders({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    final rows = await database.query(
      'reminders',
      where: 'owner_id = ?',
      whereArgs: <Object?>[scope.userId],
      orderBy: 'updated_at DESC',
    );
    ensureCurrent(scope);
    return rows
        .map((row) {
          final decoded = jsonDecode(row['payload']! as String);
          return decoded is Map
              ? Map<String, Object?>.from(decoded)
              : <String, Object?>{};
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsertReminder(
    Map<String, Object?> reminder, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.insert(
        'reminders',
        _reminderRow(reminder, id, scope.userId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> upsertReminderWithOutbox({
    required Map<String, Object?> reminder,
    required String operationId,
    required Map<String, Object?> operation,
    AccountScopeSnapshot? accountScope,
  }) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Reminder identity is required');
    }
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.insert(
        'reminders',
        _reminderRow(reminder, id, scope.userId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>[scope.userId, 'reminder', id],
      );
      await transaction.insert('outbox', <String, Object?>{
        'owner_id': scope.userId,
        'operation_id': operationId,
        'entity_type': 'reminder',
        'entity_id': id,
        'payload': jsonEncode(operation),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    ensureCurrent(scope);
  }

  Future<void> discardLocalReminder(
    String id, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.delete(
        'reminders',
        where: 'owner_id = ? AND id = ?',
        whereArgs: <Object?>[scope.userId, id],
      );
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>[scope.userId, 'reminder', id],
      );
    });
    ensureCurrent(scope);
  }

  Future<List<Map<String, Object?>>> pendingOutbox({int limit = 100}) async {
    final scope = await captureAccount();
    final rows = await database.query(
      'outbox',
      where: 'owner_id = ?',
      whereArgs: <Object?>[scope.userId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    ensureCurrent(scope);
    return rows;
  }

  Future<void> acknowledgeOutbox(
    String operationId, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[scope.userId, operationId],
      );
    });
  }

  Future<void> markOutboxFailure(
    String operationId,
    String error, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await captureAccount();
    ensureCurrent(scope);
    await database.transaction((transaction) async {
      ensureCurrent(scope);
      await transaction.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? '
        'WHERE owner_id = ? AND operation_id = ?',
        <Object?>[error, scope.userId, operationId],
      );
    });
  }

  Future<void> close() => database.close();

  static Map<String, Object?> _reminderRow(
    Map<String, Object?> reminder,
    String id,
    String ownerId,
  ) => <String, Object?>{
    'owner_id': ownerId,
    'id': id,
    'payload': jsonEncode(reminder),
    'revision': (reminder['revision'] as num?)?.toInt() ?? 0,
    'is_deleted': reminder['deleted_at'] == null ? 0 : 1,
    'updated_at':
        reminder['updated_at']?.toString() ??
        reminder['client_updated_at']?.toString() ??
        DateTime.now().toUtc().toIso8601String(),
  };

  static const _accountTables = <String>[
    'reading_positions',
    'bookmarks',
    'favorites',
    'outbox',
    'app_state',
    'reminders',
  ];

  static const _accountTableKeys = <String, String>{
    'reading_positions': 'edition',
    'bookmarks': 'id',
    'favorites': 'item_key',
    'outbox': 'operation_id',
    'app_state': 'state_key',
    'reminders': 'id',
  };

  static const _accountTableTimestamps = <String, String>{
    'reading_positions': 'updated_at',
    'bookmarks': 'updated_at',
    'favorites': 'updated_at',
    'outbox': 'created_at',
    'app_state': 'updated_at',
    'reminders': 'updated_at',
  };

  static String _accountCacheKey(String ownerId, String key) =>
      'account:${Uri.encodeComponent(ownerId)}:$key';

  static bool _isAfter(Object? candidate, Object? baseline) {
    final candidateTime = DateTime.tryParse(candidate?.toString() ?? '');
    final baselineTime = DateTime.tryParse(baseline?.toString() ?? '');
    if (candidateTime == null) return false;
    return baselineTime == null || candidateTime.isAfter(baselineTime);
  }

  static Future<Map<String, _TransferLogicalState>>
  _accountTransferLogicalStates(
    DatabaseExecutor db,
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    final states = <String, _TransferLogicalState>{};
    for (final table in const <String>[
      'reading_positions',
      'bookmarks',
      'favorites',
      'reminders',
    ]) {
      final rows = await db.query(
        table,
        where: 'owner_id IN (?, ?)',
        whereArgs: <Object?>[sourceOwnerId, targetOwnerId],
      );
      for (final row in rows) {
        final key = _accountEntityLogicalKey(table, row);
        if (key == null) continue;
        final state = states.putIfAbsent(key, _TransferLogicalState.new);
        state.observeEntity(
          source: row['owner_id'] == sourceOwnerId,
          timestamp: row['updated_at'],
        );
      }
    }

    final operations = await db.query(
      'outbox',
      where:
          'owner_id IN (?, ?) AND entity_type IN '
          "('reading_position', 'bookmark', 'reminder', 'dua_favorite')",
      whereArgs: <Object?>[sourceOwnerId, targetOwnerId],
      orderBy: 'created_at ASC, rowid ASC',
    );
    for (final operation in operations) {
      final key = _accountOutboxLogicalKey(operation);
      if (key == null) continue;
      final state = states.putIfAbsent(key, _TransferLogicalState.new);
      state.observeOperation(
        source: operation['owner_id'] == sourceOwnerId,
        row: operation,
      );
    }
    return states;
  }

  static String? _accountEntityLogicalKey(
    String table,
    Map<String, Object?> row,
  ) {
    final value = switch (table) {
      'reading_positions' => row['edition'],
      'bookmarks' => row['id'],
      'favorites' => row['item_key'],
      'reminders' => row['id'],
      _ => null,
    };
    final key = value?.toString().trim() ?? '';
    if (key.isEmpty) return null;
    final type = switch (table) {
      'reading_positions' => 'reading_position',
      'bookmarks' => 'bookmark',
      'favorites' => 'dua_favorite',
      'reminders' => 'reminder',
      _ => '',
    };
    return type.isEmpty ? null : '$type:$key';
  }

  static String? _accountOutboxLogicalKey(Map<String, Object?> row) {
    final type = row['entity_type']?.toString() ?? '';
    if (!const <String>{
      'reading_position',
      'bookmark',
      'reminder',
      'dua_favorite',
    }.contains(type)) {
      return null;
    }
    String key;
    if (type == 'reading_position') {
      try {
        final decoded = jsonDecode(row['payload']?.toString() ?? '');
        final body = decoded is Map
            ? Map<String, Object?>.from(decoded)
            : const <String, Object?>{};
        final rawIntent = body['payload'];
        final intent = rawIntent is Map
            ? Map<String, Object?>.from(rawIntent)
            : const <String, Object?>{};
        key = intent['edition_code']?.toString().trim() ?? '';
      } on Object {
        return null;
      }
    } else {
      key = row['entity_id']?.toString().trim() ?? '';
    }
    return key.isEmpty ? null : '$type:$key';
  }

  static Future<void> _transferReconciledOutbox(
    DatabaseExecutor db,
    String sourceOwnerId,
    String targetOwnerId,
    Map<String, _TransferLogicalState> logicalStates,
  ) async {
    for (final entry in logicalStates.entries) {
      final state = entry.value;
      if (!state.sourceWins) continue;
      for (final operation in state.targetOperations) {
        await db.delete(
          'outbox',
          where: 'owner_id = ? AND operation_id = ?',
          whereArgs: <Object?>[targetOwnerId, operation['operation_id']],
        );
      }
      final sourceOperation = state.latestSourceOperation;
      if (entry.key.startsWith('dua_favorite:') &&
          sourceOperation != null &&
          !_duaFavoriteOperationDesired(sourceOperation)) {
        await db.delete(
          'favorites',
          where: 'owner_id = ? AND item_key = ?',
          whereArgs: <Object?>[
            targetOwnerId,
            entry.key.substring('dua_favorite:'.length),
          ],
        );
      }
      if (sourceOperation != null) {
        await db.insert('outbox', <String, Object?>{
          ...sourceOperation,
          'owner_id': targetOwnerId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // Share analytics are append-only rather than mutable entity intent.
    final shareEvents = await db.query(
      'outbox',
      where: 'owner_id = ? AND entity_type = ?',
      whereArgs: <Object?>[sourceOwnerId, 'share_event'],
    );
    for (final sourceRow in shareEvents) {
      final targetRows = await db.query(
        'outbox',
        columns: const <String>['created_at'],
        where: 'owner_id = ? AND operation_id = ?',
        whereArgs: <Object?>[targetOwnerId, sourceRow['operation_id']],
        limit: 1,
      );
      if (targetRows.isEmpty ||
          _isAfter(sourceRow['created_at'], targetRows.single['created_at'])) {
        await db.insert('outbox', <String, Object?>{
          ...sourceRow,
          'owner_id': targetOwnerId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static bool _duaFavoriteOperationDesired(Map<String, Object?> operation) {
    try {
      final decoded = jsonDecode(operation['payload']?.toString() ?? '');
      return decoded is Map && decoded['is_favorite'] == true;
    } on Object {
      return false;
    }
  }

  static Future<void> _transferAccountCache(
    DatabaseExecutor db,
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    final sourcePrefix = _accountCacheKey(sourceOwnerId, '');
    final targetPrefix = _accountCacheKey(targetOwnerId, '');
    final sourceRows = await db.query(
      'cache_entries',
      where: 'cache_key LIKE ? ESCAPE \'\\\'',
      whereArgs: <Object?>['${_escapeLike(sourcePrefix)}%'],
    );
    for (final sourceRow in sourceRows) {
      final sourceKey = sourceRow['cache_key']! as String;
      final targetKey =
          '$targetPrefix${sourceKey.substring(sourcePrefix.length)}';
      final targetRows = await db.query(
        'cache_entries',
        columns: const <String>['updated_at'],
        where: 'cache_key = ?',
        whereArgs: <Object?>[targetKey],
        limit: 1,
      );
      if (targetRows.isEmpty ||
          _isAfter(sourceRow['updated_at'], targetRows.single['updated_at'])) {
        await db.insert('cache_entries', <String, Object?>{
          ...sourceRow,
          'cache_key': targetKey,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  static String _safeLegacyOwner(String? ownerId) {
    final normalized = ownerId?.trim() ?? '';
    return normalized.isEmpty ? quarantinedLegacyOwner : normalized;
  }

  @visibleForTesting
  static Future<void> migrateLegacyAccountTablesForTesting(
    Database db, {
    String? legacyOwnerId,
  }) => _migrateAccountTables(db, _safeLegacyOwner(legacyOwnerId));

  static Future<void> _createAccountTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE reading_positions (
        owner_id TEXT NOT NULL,
        edition TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        surah INTEGER NOT NULL,
        ayah INTEGER NOT NULL,
        page INTEGER,
        server_revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, edition)
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks (
        owner_id TEXT NOT NULL,
        id TEXT NOT NULL,
        edition TEXT NOT NULL,
        surah INTEGER NOT NULL,
        ayah INTEGER NOT NULL,
        server_revision INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, id)
      )
    ''');
    await db.execute('''
      CREATE INDEX bookmarks_owner_location_idx
      ON bookmarks(owner_id, edition, surah, ayah, is_deleted)
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        owner_id TEXT NOT NULL,
        item_key TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, item_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE outbox (
        owner_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        last_error TEXT,
        PRIMARY KEY (owner_id, operation_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX outbox_owner_created_idx
      ON outbox(owner_id, created_at)
    ''');
    await db.execute('''
      CREATE TABLE app_state (
        owner_id TEXT NOT NULL,
        state_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, state_key)
      )
    ''');
    await _createReminderTable(db);
  }

  static Future<void> _createDeviceStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_state (
        state_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _migrateAccountTables(
    DatabaseExecutor db,
    String legacyOwnerId,
  ) async {
    // Notification IDs are device-owned OS resources, not account data. Copy
    // the v3 account-state plan into a crash-recovery marker before the legacy
    // table is quarantined/dropped. This lets startup cancel old alarms even
    // when no trustworthy legacy account owner can be recovered.
    await _createDeviceStateTable(db);
    await _extractLegacyManagedNotificationPlan(db);
    for (final table in _accountTables) {
      await db.execute('ALTER TABLE $table RENAME TO ${table}_legacy_v3');
    }
    await _createAccountTables(db);
    await db.rawInsert(
      '''
      INSERT INTO reading_positions
        (owner_id, edition, entity_id, surah, ayah, page, server_revision,
         dirty, updated_at)
      SELECT ?, edition, entity_id, surah, ayah, page, server_revision,
             dirty, updated_at
      FROM reading_positions_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    await db.rawInsert(
      '''
      INSERT INTO bookmarks
        (owner_id, id, edition, surah, ayah, server_revision, is_deleted,
         updated_at)
      SELECT ?, id, edition, surah, ayah, server_revision, is_deleted,
             updated_at
      FROM bookmarks_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    await db.rawInsert(
      '''
      INSERT INTO favorites (owner_id, item_key, kind, payload, updated_at)
      SELECT ?, item_key, kind, payload, updated_at
      FROM favorites_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    await db.rawInsert(
      '''
      INSERT INTO outbox
        (owner_id, operation_id, entity_type, entity_id, payload, attempts,
         created_at, last_error)
      SELECT ?, operation_id, entity_type, entity_id, payload, attempts,
             created_at, last_error
      FROM outbox_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    await db.rawInsert(
      '''
      INSERT INTO app_state (owner_id, state_key, payload, updated_at)
      SELECT ?, state_key, payload, updated_at
      FROM app_state_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    await db.rawInsert(
      '''
      INSERT INTO reminders
        (owner_id, id, payload, revision, is_deleted, updated_at)
      SELECT ?, id, payload, revision, is_deleted, updated_at
      FROM reminders_legacy_v3
    ''',
      <Object?>[legacyOwnerId],
    );
    for (final table in _accountTables.reversed) {
      await db.execute('DROP TABLE ${table}_legacy_v3');
    }
  }

  static Future<void> _extractLegacyManagedNotificationPlan(
    DatabaseExecutor db,
  ) async {
    const managedStateKey = 'managed_notification_ids_v1';
    final rows = await db.query(
      'app_state',
      columns: const <String>['payload'],
      where: 'state_key = ?',
      whereArgs: const <Object?>['reminder_notification_plan'],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final legacyIds = <int>{};
    try {
      final decoded = jsonDecode(rows.single['payload']! as String);
      if (decoded is! Map) return;
      final rawIds = decoded['ids'];
      if (rawIds is! List || rawIds.length > 4096) return;
      for (final value in rawIds.whereType<num>()) {
        final id = value.toInt();
        if (id >= 0 && id <= 0x7fffffff) legacyIds.add(id);
      }
    } on Object {
      // A malformed legacy plan cannot be safely mapped to OS identifiers.
      return;
    }
    if (legacyIds.isEmpty) return;

    var generation = 1;
    final existing = await db.query(
      'device_state',
      columns: const <String>['payload'],
      where: 'state_key = ?',
      whereArgs: const <Object?>[managedStateKey],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      try {
        final decoded = jsonDecode(existing.single['payload']! as String);
        if (decoded is Map) {
          final rawIds = decoded['ids'];
          if (rawIds is List && rawIds.length <= 4096) {
            for (final value in rawIds.whereType<num>()) {
              final id = value.toInt();
              if (id >= 0 && id <= 0x7fffffff) legacyIds.add(id);
            }
          }
          final oldGeneration = (decoded['generation'] as num?)?.toInt() ?? 0;
          generation = oldGeneration < 0 ? 1 : oldGeneration + 1;
        }
      } on Object {
        // The extracted legacy IDs are still sufficient for safe cleanup.
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('device_state', <String, Object?>{
      'state_key': managedStateKey,
      'payload': jsonEncode(<String, Object?>{
        'ids': legacyIds.toList(growable: false)..sort(),
        'owner_id': null,
        'generation': generation,
        'in_progress': true,
        'updated_at': now,
      }),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _createReminderTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        owner_id TEXT NOT NULL,
        id TEXT NOT NULL,
        payload TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, id)
      )
    ''');
  }

  static Future<void> _createOfflinePackageTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_packages (
        package_id TEXT PRIMARY KEY,
        package_type TEXT NOT NULL,
        content_key TEXT NOT NULL,
        version TEXT NOT NULL,
        width INTEGER,
        checksum_sha256 TEXT NOT NULL,
        manifest TEXT NOT NULL,
        status TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 0,
        total_items INTEGER NOT NULL,
        completed_items INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS offline_packages_content_idx
      ON offline_packages(content_key, is_active, updated_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_package_items (
        package_id TEXT NOT NULL,
        item_key TEXT NOT NULL,
        item_number INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        url TEXT NOT NULL,
        checksum_sha256 TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        metadata TEXT NOT NULL,
        status TEXT NOT NULL,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (package_id, item_key),
        FOREIGN KEY (package_id) REFERENCES offline_packages(package_id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS offline_package_items_page_idx
      ON offline_package_items(package_id, item_number)
    ''');
  }
}

class _TransferLogicalState {
  Object? _sourceTimestamp;
  Object? _targetTimestamp;
  bool _sourceObserved = false;
  bool _targetObserved = false;
  Map<String, Object?>? latestSourceOperation;
  final List<Map<String, Object?>> targetOperations = <Map<String, Object?>>[];

  bool get sourceWins {
    if (!_sourceObserved) return false;
    if (!_targetObserved) return true;
    final source = DateTime.tryParse(_sourceTimestamp?.toString() ?? '');
    final target = DateTime.tryParse(_targetTimestamp?.toString() ?? '');
    if (source == null) return false;
    return target == null || source.isAfter(target);
  }

  void observeEntity({required bool source, required Object? timestamp}) {
    if (source) {
      _sourceObserved = true;
      _sourceTimestamp = _later(_sourceTimestamp, timestamp);
    } else {
      _targetObserved = true;
      _targetTimestamp = _later(_targetTimestamp, timestamp);
    }
  }

  void observeOperation({
    required bool source,
    required Map<String, Object?> row,
  }) {
    final timestamp = row['created_at'];
    if (source) {
      _sourceObserved = true;
      final later = _later(_sourceTimestamp, timestamp);
      if (identical(later, timestamp) || later == timestamp) {
        latestSourceOperation = row;
      }
      _sourceTimestamp = later;
    } else {
      _targetObserved = true;
      _targetTimestamp = _later(_targetTimestamp, timestamp);
      targetOperations.add(row);
    }
  }

  static Object? _later(Object? current, Object? candidate) {
    if (current == null) return candidate;
    final currentTime = DateTime.tryParse(current.toString());
    final candidateTime = DateTime.tryParse(candidate?.toString() ?? '');
    if (candidateTime == null) return current;
    return currentTime == null || !candidateTime.isBefore(currentTime)
        ? candidate
        : current;
  }
}
