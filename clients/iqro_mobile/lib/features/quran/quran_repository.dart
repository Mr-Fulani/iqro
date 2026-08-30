import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
  final Map<String, Future<Uint8List>> _fontDownloads =
      <String, Future<Uint8List>>{};

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

  Future<FoundationMushafPage> foundationMushafPage(
    int sourceId,
    int page, {
    bool forceRefresh = false,
  }) async {
    final safePage = page.clamp(1, 604);
    final key = 'quran:foundation:mushaf:$sourceId:page:$safePage';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return FoundationMushafPage.fromJson(
        jsonMap(cached!.value),
        fromCache: true,
      );
    }
    try {
      final payload = await _api.get(
        '/quran/foundation/mushafs/$sourceId/pages/$safePage',
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
      return FoundationMushafPage.fromJson(jsonMap(payload), fromCache: false);
    } on Object {
      if (cached != null) {
        return FoundationMushafPage.fromJson(
          jsonMap(cached.value),
          fromCache: true,
        );
      }
      rethrow;
    }
  }

  Future<String> mushafFontDataUri(MushafVariant variant, int page) async {
    final uri = variant.fontUriForPage(page);
    if (uri == null) {
      throw const FormatException('Mushaf font URL is unavailable');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(
        supportDirectory.path,
        'mushaf_fonts',
        'source-${variant.sourceId}',
      ),
    );
    await directory.create(recursive: true);
    final basename = variant.renderingMode == 'page-font'
        ? 'page-${page.toString().padLeft(3, '0')}.woff2'
        : 'global.woff2';
    final file = File(p.join(directory.path, basename));
    final sourceFile = File('${file.path}.source');
    final bytes = await _fontBytes(file, sourceFile, uri);
    return 'data:font/woff2;base64,${base64Encode(bytes)}';
  }

  Future<void> prefetchFoundationMushaf(
    MushafVariant variant,
    int currentPage,
  ) async {
    final pages = <int>{
      currentPage,
      if (currentPage > 1) currentPage - 1,
      if (currentPage < variant.pagesCount) currentPage + 1,
    };
    await Future.wait(
      pages.map((page) async {
        try {
          await Future.wait(<Future<Object?>>[
            foundationMushafPage(variant.sourceId, page),
            mushafFontDataUri(variant, page),
          ]);
        } on Object {
          // Prefetch is best-effort; the visible page owns user-facing errors.
        }
      }),
    );
  }

  Future<Uint8List> _fontBytes(File file, File sourceFile, Uri uri) async {
    final cached = await _readCachedFont(file, sourceFile, uri);
    if (cached != null) return cached;
    final key = file.path;
    final inFlight = _fontDownloads.putIfAbsent(
      key,
      () => _downloadFont(file, sourceFile, uri),
    );
    try {
      return await inFlight;
    } finally {
      if (identical(_fontDownloads[key], inFlight)) {
        _fontDownloads.remove(key);
      }
    }
  }

  Future<Uint8List?> _readCachedFont(
    File file,
    File sourceFile,
    Uri uri,
  ) async {
    if (!await file.exists() || !await sourceFile.exists()) return null;
    if ((await sourceFile.readAsString()).trim() != uri.toString()) return null;
    final bytes = await file.readAsBytes();
    return _validWoff2(bytes) ? bytes : null;
  }

  Future<Uint8List> _downloadFont(File file, File sourceFile, Uri uri) async {
    try {
      final bytes = await _api.getPublicBytes(
        uri,
        allowedHosts: const <String>{'verses.quran.foundation'},
      );
      if (!_validWoff2(bytes)) {
        throw const FormatException('Mushaf font is not a valid WOFF2 file');
      }
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final temporaryFile = File('${file.path}.$suffix.part');
      final temporarySource = File('${sourceFile.path}.$suffix.part');
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporarySource.writeAsString(uri.toString(), flush: true);
      if (await file.exists()) await file.delete();
      if (await sourceFile.exists()) await sourceFile.delete();
      await temporaryFile.rename(file.path);
      await temporarySource.rename(sourceFile.path);
      return bytes;
    } on Object {
      if (await file.exists()) {
        final stale = await file.readAsBytes();
        if (_validWoff2(stale)) return stale;
      }
      rethrow;
    }
  }

  bool _validWoff2(List<int> bytes) {
    return bytes.length >= 48 &&
        bytes[0] == 0x77 &&
        bytes[1] == 0x4f &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x32;
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
