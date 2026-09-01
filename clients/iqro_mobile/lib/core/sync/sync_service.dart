import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/local_database.dart';
import '../utils/json_helpers.dart';

enum SyncStatus { idle, syncing, offline, conflict, sessionExpired, failed }

class SyncReport {
  const SyncReport({
    required this.status,
    this.pushed = 0,
    this.pulled = 0,
    this.message,
  });

  final SyncStatus status;
  final int pushed;
  final int pulled;
  final String? message;
}

class SyncService {
  SyncService({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;
  Future<SyncReport>? _flight;

  Future<SyncReport> synchronize() {
    final current = _flight;
    if (current != null) return current;
    final next = _run();
    _flight = next;
    return next.whenComplete(() => _flight = null);
  }

  Future<SyncReport> _run() async {
    var pushed = 0;
    var pulled = 0;
    try {
      final rows = await _database.pendingOutbox();
      final shareRows = rows.where(
        (row) => row['entity_type'] == 'share_event',
      );
      for (final row in shareRows) {
        final id = row['operation_id']! as String;
        try {
          await _api.post(
            '/share/events',
            data: jsonDecode(row['payload']! as String),
          );
          await _database.acknowledgeOutbox(id);
          pushed++;
        } on ApiException catch (error) {
          if (error.statusCode == 409 || error.statusCode == 400) {
            await _database.acknowledgeOutbox(id);
          } else {
            await _database.markOutboxFailure(id, error.toString());
          }
        }
      }

      final duaFavoriteRows = rows.where(
        (row) => row['entity_type'] == 'dua_favorite',
      );
      for (final row in duaFavoriteRows) {
        final id = row['operation_id']! as String;
        try {
          final payload = Map<String, Object?>.from(
            jsonDecode(row['payload']! as String) as Map,
          );
          await _api.put(
            '/me/dua-favorites/${payload['collection']}/${payload['source_number']}',
            data: <String, Object?>{
              'is_favorite': payload['is_favorite'] == true,
            },
          );
          await _database.acknowledgeOutbox(id);
          pushed++;
        } on ApiException catch (error) {
          await _database.markOutboxFailure(id, error.toString());
        }
      }

      final entityRows = rows
          .where(
            (row) =>
                row['entity_type'] != 'share_event' &&
                row['entity_type'] != 'dua_favorite',
          )
          .take(100)
          .toList(growable: false);
      if (entityRows.isNotEmpty) {
        final operations = entityRows
            .map((row) => jsonDecode(row['payload']! as String))
            .toList(growable: false);
        final response = jsonMap(
          await _api.post(
            '/sync/push',
            data: <String, Object?>{'operations': operations},
          ),
        );
        final results =
            (response['results'] as List?)?.whereType<Map>() ??
            const Iterable<Map>.empty();
        for (final raw in results) {
          final result = Map<String, Object?>.from(raw);
          final operationId = result['operation_id']?.toString();
          if (operationId == null) continue;
          if (result['outcome'] == 'accepted') {
            await _applyAcceptedEntity(result['entity']);
            await _database.acknowledgeOutbox(operationId);
            pushed++;
          } else {
            await _database.markOutboxFailure(
              operationId,
              result['conflict_reason']?.toString() ?? 'sync_conflict',
            );
            return SyncReport(
              status: SyncStatus.conflict,
              pushed: pushed,
              message: result['conflict_reason']?.toString(),
            );
          }
        }
      }

      final cursorState = await _database.readState('sync_cursor');
      var cursor = (cursorState?['value'] as num?)?.toInt() ?? 0;
      var hasMore = true;
      while (hasMore) {
        final response = jsonMap(
          await _api.get(
            '/sync/pull',
            query: <String, Object?>{'cursor': cursor, 'limit': 100},
          ),
        );
        final changes =
            (response['changes'] as List?)?.whereType<Map>() ??
            const Iterable<Map>.empty();
        for (final change in changes) {
          await _applyAcceptedEntity(change['entity']);
          pulled++;
        }
        cursor = (response['next_cursor'] as num?)?.toInt() ?? cursor;
        hasMore = response['has_more'] == true;
        await _database.writeState('sync_cursor', <String, Object?>{
          'value': cursor,
        });
      }
      return SyncReport(
        status: SyncStatus.idle,
        pushed: pushed,
        pulled: pulled,
      );
    } on ApiException catch (error) {
      if (error.code == 'sync_cursor_expired') {
        return _fullResync(pushed: pushed);
      }
      if (error.statusCode == 401) {
        return SyncReport(
          status: SyncStatus.sessionExpired,
          message: error.message,
        );
      }
      return SyncReport(
        status: error.isOffline ? SyncStatus.offline : SyncStatus.failed,
        pushed: pushed,
        pulled: pulled,
        message: error.message,
      );
    } on Object catch (error) {
      return SyncReport(status: SyncStatus.failed, message: error.toString());
    }
  }

  Future<SyncReport> _fullResync({required int pushed}) async {
    var token = '';
    var pulled = 0;
    var hasMore = true;
    var snapshotCursor = 0;
    final entities = <Object?>[];
    while (hasMore) {
      final response = jsonMap(
        await _api.get(
          '/sync/pull',
          query: <String, Object?>{
            'full_resync': true,
            'limit': 100,
            if (token.isNotEmpty) 'page_token': token,
          },
        ),
      );
      entities.addAll((response['entities'] as List?) ?? const <Object?>[]);
      snapshotCursor =
          (response['snapshot_cursor'] as num?)?.toInt() ?? snapshotCursor;
      token = response['next_page_token']?.toString() ?? '';
      hasMore = response['has_more'] == true;
    }
    await _database.database.transaction((transaction) async {
      for (final entity in entities) {
        await _applyAcceptedEntity(entity, database: transaction);
        pulled++;
      }
      await transaction.insert('app_state', <String, Object?>{
        'state_key': 'sync_cursor',
        'payload': jsonEncode(<String, Object?>{'value': snapshotCursor}),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return SyncReport(status: SyncStatus.idle, pushed: pushed, pulled: pulled);
  }

  Future<void> _applyAcceptedEntity(
    Object? raw, {
    DatabaseExecutor? database,
  }) async {
    if (raw is! Map) return;
    final entity = Map<String, Object?>.from(raw);
    final executor = database ?? _database.database;
    final type = entity['entity_type']?.toString();
    if (type == 'reading_position') {
      final ayah = entity['ayah'] is Map
          ? Map<String, Object?>.from(entity['ayah']! as Map)
          : const <String, Object?>{};
      await executor.insert('reading_positions', <String, Object?>{
        'edition': entity['edition_code']?.toString() ?? 'madani-hafs',
        'entity_id': entity['id']?.toString() ?? '',
        'surah': (ayah['surah_number'] as num?)?.toInt() ?? 1,
        'ayah': (ayah['ayah_number'] as num?)?.toInt() ?? 1,
        'page': (entity['page_number'] as num?)?.toInt() ?? 1,
        'server_revision': (entity['revision'] as num?)?.toInt() ?? 0,
        'dirty': 0,
        'updated_at':
            entity['updated_at']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else if (type == 'bookmark') {
      final ayah = entity['ayah'] is Map
          ? Map<String, Object?>.from(entity['ayah']! as Map)
          : const <String, Object?>{};
      await executor.insert('bookmarks', <String, Object?>{
        'id': entity['id']?.toString() ?? '',
        'edition': entity['edition_code']?.toString() ?? 'madani-hafs',
        'surah': (ayah['surah_number'] as num?)?.toInt() ?? 1,
        'ayah': (ayah['ayah_number'] as num?)?.toInt() ?? 1,
        'server_revision': (entity['revision'] as num?)?.toInt() ?? 0,
        'is_deleted': entity['deleted_at'] == null ? 0 : 1,
        'updated_at':
            entity['updated_at']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else if (type == 'reminder') {
      final id = entity['id']?.toString() ?? '';
      if (id.isEmpty) return;
      await executor.insert('reminders', <String, Object?>{
        'id': id,
        'payload': jsonEncode(entity),
        'revision': (entity['revision'] as num?)?.toInt() ?? 0,
        'is_deleted': entity['deleted_at'] == null ? 0 : 1,
        'updated_at':
            entity['updated_at']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
