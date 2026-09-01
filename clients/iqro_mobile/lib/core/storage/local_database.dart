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

  static const schemaVersion = 3;
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
        await _createReminderTable(db);
        await _createOfflinePackageTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createReminderTable(db);
        if (oldVersion < 3) await _createOfflinePackageTables(db);
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

  Future<void> deleteState(String key) async {
    await database.delete(
      'app_state',
      where: 'state_key = ?',
      whereArgs: <Object?>[key],
    );
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

  Future<void> replaceOutboxOperation({
    required String operationId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
  }) async {
    await database.transaction((transaction) async {
      await transaction.delete(
        'outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>[entityType, entityId],
      );
      await transaction.insert('outbox', <String, Object?>{
        'operation_id': operationId,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<List<Map<String, Object?>>> readReminders() async {
    final rows = await database.query('reminders', orderBy: 'updated_at DESC');
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

  Future<void> upsertReminder(Map<String, Object?> reminder) async {
    final id = reminder['id']?.toString();
    if (id == null || id.isEmpty) return;
    await database.insert('reminders', <String, Object?>{
      'id': id,
      'payload': jsonEncode(reminder),
      'revision': (reminder['revision'] as num?)?.toInt() ?? 0,
      'is_deleted': reminder['deleted_at'] == null ? 0 : 1,
      'updated_at':
          reminder['updated_at']?.toString() ??
          reminder['client_updated_at']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> discardLocalReminder(String id) async {
    await database.transaction((transaction) async {
      await transaction.delete(
        'reminders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await transaction.delete(
        'outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>['reminder', id],
      );
    });
  }

  Future<void> replaceReminderSnapshot(
    List<Map<String, Object?>> reminders,
  ) async {
    await database.transaction((transaction) async {
      await transaction.delete('reminders');
      for (final reminder in reminders) {
        final id = reminder['id']?.toString();
        if (id == null || id.isEmpty) continue;
        await transaction.insert('reminders', <String, Object?>{
          'id': id,
          'payload': jsonEncode(reminder),
          'revision': (reminder['revision'] as num?)?.toInt() ?? 0,
          'is_deleted': reminder['deleted_at'] == null ? 0 : 1,
          'updated_at':
              reminder['updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
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

  static Future<void> _createReminderTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
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
