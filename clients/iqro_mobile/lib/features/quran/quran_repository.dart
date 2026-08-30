import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'quran_models.dart';

class QuranRepository {
  QuranRepository({
    required ApiClient api,
    required LocalDatabase database,
    Uuid? uuid,
  }) : _api = api,
       _database = database,
       _uuid = uuid ?? const Uuid();

  static const edition = 'madani-hafs';
  final ApiClient _api;
  final LocalDatabase _database;
  final Uuid _uuid;

  Future<QuranCatalog> surahs({bool forceRefresh = false}) async {
    const key = 'quran:$edition:surahs';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return QuranCatalog(surahs: parseSurahs(cached!.value), fromCache: true);
    }
    try {
      final payload = await _api.get(
        '/quran/editions/$edition/surahs',
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 1));
      return QuranCatalog(surahs: parseSurahs(payload), fromCache: false);
    } on Object {
      if (cached != null) {
        return QuranCatalog(surahs: parseSurahs(cached.value), fromCache: true);
      }
      rethrow;
    }
  }

  Future<List<QuranAyah>> ayahs(int surah, {bool forceRefresh = false}) async {
    final key = 'quran:$edition:surah:$surah:ayahs';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseAyahs(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/quran/editions/$edition/surahs/$surah/ayahs',
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
      return _parseAyahs(payload);
    } on Object {
      if (cached != null) return _parseAyahs(cached.value);
      rethrow;
    }
  }

  Future<MushafPageData> mushafPage(
    int page, {
    bool forceRefresh = false,
  }) async {
    final key = 'quran:$edition:page:$page';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return MushafPageData.fromJson(jsonMap(cached!.value));
    }
    try {
      final payload = await _api.get(
        '/quran/editions/$edition/pages/$page',
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(days: 30),
      );
      return MushafPageData.fromJson(jsonMap(payload));
    } on Object {
      if (cached != null) return MushafPageData.fromJson(jsonMap(cached.value));
      rethrow;
    }
  }

  Future<List<MushafVariant>> mushafVariants({
    bool forceRefresh = false,
  }) async {
    const key = 'quran:foundation:mushafs';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseMushafVariants(cached!.value);
    }
    try {
      final payload = await _api.get('/quran/foundation/mushafs', public: true);
      await _database.writeCache(key, payload, maxAge: const Duration(days: 1));
      return _parseMushafVariants(payload);
    } on Object {
      if (cached != null) return _parseMushafVariants(cached.value);
      rethrow;
    }
  }

  Future<ReadingPosition> position() async {
    final rows = await _database.database.query(
      'reading_positions',
      where: 'edition = ?',
      whereArgs: const <Object?>[edition],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ReadingPosition(
        edition: edition,
        entityId: _uuid.v4(),
        surah: 1,
        ayah: 1,
        page: 1,
        revision: 0,
      );
    }
    final row = rows.single;
    return ReadingPosition(
      edition: edition,
      entityId: row['entity_id']! as String,
      surah: row['surah']! as int,
      ayah: row['ayah']! as int,
      page: (row['page'] as int?) ?? 1,
      revision: row['server_revision']! as int,
    );
  }

  Future<void> savePosition({
    required int surah,
    required int ayah,
    required int page,
  }) async {
    final current = await position();
    final now = DateTime.now().toUtc();
    final operationId = _uuid.v4();
    final progress = ((page / 604) * 100).clamp(0, 100).toStringAsFixed(2);
    await _database.database.transaction((transaction) async {
      await transaction.insert('reading_positions', <String, Object?>{
        'edition': edition,
        'entity_id': current.entityId,
        'surah': surah,
        'ayah': ayah,
        'page': page,
        'server_revision': current.revision,
        'dirty': 1,
        'updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('outbox', <String, Object?>{
        'operation_id': operationId,
        'entity_type': 'reading_position',
        'entity_id': current.entityId,
        'payload': jsonEncode(<String, Object?>{
          'operation_id': operationId,
          'entity_type': 'reading_position',
          'entity_id': current.entityId,
          'action': 'upsert',
          'base_revision': current.revision,
          'client_updated_at': now.toIso8601String(),
          'payload': <String, Object?>{
            'edition_code': edition,
            'page_number': page,
            'surah_number': surah,
            'ayah_number': ayah,
            'progress_percent': progress,
            'last_read_at': now.toIso8601String(),
          },
        }),
        'attempts': 0,
        'created_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<bool> isBookmarked(int surah, int ayah) async {
    final rows = await _database.database.query(
      'bookmarks',
      columns: const <String>['id'],
      where: 'edition = ? AND surah = ? AND ayah = ? AND is_deleted = 0',
      whereArgs: <Object?>[edition, surah, ayah],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleBookmark(int surah, int ayah, {int? page}) async {
    final rows = await _database.database.query(
      'bookmarks',
      where: 'edition = ? AND surah = ? AND ayah = ? AND is_deleted = 0',
      whereArgs: <Object?>[edition, surah, ayah],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    final now = DateTime.now().toUtc();
    if (rows.isNotEmpty) {
      final row = rows.single;
      final id = row['id']! as String;
      final revision = row['server_revision']! as int;
      await _database.database.transaction((transaction) async {
        if (revision == 0) {
          await transaction.delete(
            'bookmarks',
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
          await transaction.delete(
            'outbox',
            where: 'entity_id = ?',
            whereArgs: <Object?>[id],
          );
        } else {
          await transaction.update(
            'bookmarks',
            <String, Object?>{
              'is_deleted': 1,
              'updated_at': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
          final operationId = _uuid.v4();
          await transaction.insert(
            'outbox',
            _outboxRow(
              operationId: operationId,
              entityId: id,
              now: now,
              body: <String, Object?>{
                'operation_id': operationId,
                'entity_type': 'bookmark',
                'entity_id': id,
                'action': 'delete',
                'base_revision': revision,
                'client_updated_at': now.toIso8601String(),
                'payload': const <String, Object?>{},
              },
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return false;
    }

    final id = _uuid.v7();
    final operationId = _uuid.v4();
    final bookmarkPayload = <String, Object?>{
      'edition_code': edition,
      'surah_number': surah,
      'ayah_number': ayah,
      'page_number': ?page,
      'color_key': 'emerald',
    };
    await _database.database.transaction((transaction) async {
      await transaction.insert('bookmarks', <String, Object?>{
        'id': id,
        'edition': edition,
        'surah': surah,
        'ayah': ayah,
        'server_revision': 0,
        'is_deleted': 0,
        'updated_at': now.toIso8601String(),
      });
      await transaction.insert(
        'outbox',
        _outboxRow(
          operationId: operationId,
          entityId: id,
          now: now,
          body: <String, Object?>{
            'operation_id': operationId,
            'entity_type': 'bookmark',
            'entity_id': id,
            'action': 'upsert',
            'base_revision': 0,
            'client_updated_at': now.toIso8601String(),
            'payload': bookmarkPayload,
          },
        ),
      );
    });
    return true;
  }

  Future<List<Map<String, Object?>>> bookmarks() {
    return _database.database.query(
      'bookmarks',
      where: 'is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
  }

  Map<String, Object?> _outboxRow({
    required String operationId,
    required String entityId,
    required DateTime now,
    required Map<String, Object?> body,
  }) {
    return <String, Object?>{
      'operation_id': operationId,
      'entity_type': 'bookmark',
      'entity_id': entityId,
      'payload': jsonEncode(body),
      'attempts': 0,
      'created_at': now.toIso8601String(),
    };
  }

  List<QuranAyah> _parseAyahs(Object? payload) {
    return jsonResults(payload)
        .whereType<Map>()
        .map((item) => QuranAyah.fromJson(Map<String, Object?>.from(item)))
        .where((ayah) => ayah.number > 0 && ayah.textUthmani.isNotEmpty)
        .toList(growable: false);
  }
}

List<MushafVariant> _parseMushafVariants(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map((item) => MushafVariant.fromJson(Map<String, Object?>.from(item)))
      .where((item) => item.sourceId > 0 && item.name.isNotEmpty)
      .toList(growable: false);
}
