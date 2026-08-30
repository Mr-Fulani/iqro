import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
  LocalDatabase._(this.database);

  static const schemaVersion = 1;
  final Database database;

  static Future<LocalDatabase> open() async {
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
        await db.execute('''
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
        await db.execute('''
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
        await db.execute('''
          CREATE TABLE favorites (
            item_key TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
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
        await db.execute('''
          CREATE TABLE app_state (
            state_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return LocalDatabase._(database);
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

  Future<Map<String, Object?>?> readState(String key) async {
    final rows = await database.query(
      'app_state',
      where: 'state_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['payload']! as String);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<void> writeState(String key, Map<String, Object?> value) async {
    await database.insert('app_state', <String, Object?>{
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
  }) async {
    await database.insert('outbox', <String, Object?>{
      'operation_id': operationId,
      'entity_type': entityType,
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> pendingOutbox({int limit = 100}) async {
    return database.query('outbox', orderBy: 'created_at ASC', limit: limit);
  }

  Future<void> acknowledgeOutbox(String operationId) async {
    await database.delete(
      'outbox',
      where: 'operation_id = ?',
      whereArgs: <Object?>[operationId],
    );
  }

  Future<void> markOutboxFailure(String operationId, String error) async {
    await database.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE operation_id = ?',
      <Object?>[error, operationId],
    );
  }

  Future<void> close() => database.close();
}
