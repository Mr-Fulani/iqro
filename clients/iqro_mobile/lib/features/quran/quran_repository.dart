import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'mushaf_offline_repository.dart';
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
  final Map<String, Future<File>> _pageAssetDownloads =
      <String, Future<File>>{};
  final Map<String, List<QuranAyahTranslation>> _translationMemory = {};
  final Map<String, List<QuranAyahTafsir>> _tafsirMemory = {};

  Future<QuranCatalog> surahs({bool forceRefresh = false}) async {
    const key = 'quran:$edition:surahs';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return QuranCatalog(surahs: parseSurahs(cached!.value), fromCache: false);
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

  Future<List<QuranDivision>> juz({bool forceRefresh = false}) async {
    const key = 'quran:$edition:juz';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseDivisions(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/quran/editions/$edition/juz',
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(days: 30),
      );
      return _parseDivisions(payload);
    } on Object {
      if (cached != null) return _parseDivisions(cached.value);
      rethrow;
    }
  }

  Future<List<QuranTranslationEdition>> translationEditions(
    String locale, {
    bool forceRefresh = false,
  }) async {
    final key = 'quran:translations:catalog:$locale';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseTranslationEditions(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/quran/translations',
        query: <String, Object?>{'language': locale},
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 1));
      return _parseTranslationEditions(payload);
    } on Object {
      if (cached != null) return _parseTranslationEditions(cached.value);
      rethrow;
    }
  }

  Future<List<QuranAyahTranslation>> translations({
    required int sourceId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    final key = 'quran:translations:$sourceId:surah:$surah';
    if (!forceRefresh) {
      final memory = _translationMemory.remove(key);
      if (memory != null) {
        _translationMemory[key] = memory;
        return memory;
      }
    }
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _rememberTranslations(key, _parseTranslations(cached!.value));
    }
    try {
      final payload = await _api.get(
        '/quran/translations/$sourceId/surahs/$surah',
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(days: 30),
      );
      return _rememberTranslations(key, _parseTranslations(payload));
    } on Object {
      if (cached != null) {
        return _rememberTranslations(key, _parseTranslations(cached.value));
      }
      rethrow;
    }
  }

  Future<List<QuranTafsirEdition>> tafsirEditions(
    String locale, {
    bool forceRefresh = false,
  }) async {
    final key = 'quran:tafsirs:catalog:$locale';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseTafsirEditions(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/quran/tafsirs',
        query: <String, Object?>{'language': locale},
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 1));
      return _parseTafsirEditions(payload);
    } on Object {
      if (cached != null) return _parseTafsirEditions(cached.value);
      rethrow;
    }
  }

  Future<List<QuranAyahTafsir>> tafsirs({
    required int sourceId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    final key = 'quran:tafsirs:$sourceId:surah:$surah';
    if (!forceRefresh) {
      final memory = _tafsirMemory.remove(key);
      if (memory != null) {
        _tafsirMemory[key] = memory;
        return memory;
      }
    }
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _rememberTafsirs(key, _parseTafsirs(cached!.value));
    }
    try {
      final payload = await _api.get(
        '/quran/tafsirs/$sourceId/surahs/$surah',
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(days: 30),
      );
      return _rememberTafsirs(key, _parseTafsirs(payload));
    } on Object {
      if (cached != null) {
        return _rememberTafsirs(key, _parseTafsirs(cached.value));
      }
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

  Future<File> cachedMushafPageAsset(
    MushafPageData page,
    MushafAsset asset,
  ) async {
    final offline = await _activeOfflineMushafPage(page, asset);
    if (offline != null) return offline;
    final supportDirectory = await getApplicationSupportDirectory();
    final safeVersion = page.contentVersion.replaceAll(
      RegExp('[^a-zA-Z0-9._-]'),
      '_',
    );
    final checksum = asset.sha256.isNotEmpty
        ? asset.sha256
        : page.checksumSha256;
    final checksumPrefix = checksum.length >= 16
        ? checksum.substring(0, 16)
        : 'unversioned';
    final directory = Directory(
      p.join(supportDirectory.path, 'mushaf_pages', edition, safeVersion),
    );
    await directory.create(recursive: true);
    final file = File(
      p.join(
        directory.path,
        'page-${page.number.toString().padLeft(3, '0')}'
        '-w${asset.width}-$checksumPrefix.webp',
      ),
    );
    if (await _validCachedPage(file, checksum, expectedBytes: asset.bytes)) {
      return file;
    }
    final inFlight = _pageAssetDownloads.putIfAbsent(
      file.path,
      () => _downloadMushafPageAsset(file, asset, expectedChecksum: checksum),
    );
    try {
      return await inFlight;
    } finally {
      if (identical(_pageAssetDownloads[file.path], inFlight)) {
        _pageAssetDownloads.remove(file.path);
      }
    }
  }

  Future<File?> _activeOfflineMushafPage(
    MushafPageData page,
    MushafAsset asset,
  ) async {
    final rows = await _database.database.rawQuery(
      '''
      SELECT item.local_path, item.file_name, item.size_bytes,
             item.checksum_sha256
      FROM offline_package_items AS item
      INNER JOIN offline_packages AS package
        ON package.package_id = item.package_id
      WHERE package.content_key = ?
        AND package.is_active = 1
        AND package.status = 'ready'
        AND item.item_number = ?
        AND item.status = 'ready'
        AND item.checksum_sha256 = ?
      LIMIT 1
      ''',
      <Object?>['quran-edition:$edition', page.number, asset.sha256],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = File(row['local_path']! as String);
    final offlinePage = OfflineMushafPage(
      number: page.number,
      url: Uri.parse(asset.url),
      fileName: row['file_name']! as String,
      width: asset.width,
      height: asset.height ?? page.imageHeight,
      bytes: row['size_bytes']! as int,
      sha256: row['checksum_sha256']! as String,
      metadata: const <String, Object?>{},
    );
    return await verifyMushafAssetFile(file, offlinePage) ? file : null;
  }

  Future<File> _downloadMushafPageAsset(
    File file,
    MushafAsset asset, {
    required String expectedChecksum,
  }) async {
    final uri = Uri.tryParse(asset.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.path.toLowerCase().endsWith('.webp')) {
      throw const FormatException('Mushaf page URL is invalid');
    }
    final bytes = await _api.getPublicBytes(
      uri,
      allowedHosts: const <String>{
        'media.staging.iqro.forum',
        'media.iqro.forum',
      },
      maxBytes: 4 * 1024 * 1024,
    );
    if (!_validWebp(bytes) ||
        (asset.bytes != null && bytes.length != asset.bytes) ||
        (expectedChecksum.isNotEmpty &&
            sha256.convert(bytes).toString() != expectedChecksum)) {
      throw const FormatException('Mushaf page integrity check failed');
    }
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    return temporary.rename(file.path);
  }

  Future<bool> _validCachedPage(
    File file,
    String expectedChecksum, {
    required int? expectedBytes,
  }) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (!_validWebp(bytes) ||
        (expectedBytes != null && bytes.length != expectedBytes)) {
      return false;
    }
    return expectedChecksum.isEmpty ||
        sha256.convert(bytes).toString() == expectedChecksum;
  }

  bool _validWebp(List<int> bytes) {
    return bytes.length >= 16 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }

  List<QuranAyahTranslation> _rememberTranslations(
    String key,
    List<QuranAyahTranslation> value,
  ) {
    _translationMemory.remove(key);
    _translationMemory[key] = value;
    while (_translationMemory.length > 4) {
      _translationMemory.remove(_translationMemory.keys.first);
    }
    return value;
  }

  List<QuranAyahTafsir> _rememberTafsirs(
    String key,
    List<QuranAyahTafsir> value,
  ) {
    _tafsirMemory.remove(key);
    _tafsirMemory[key] = value;
    while (_tafsirMemory.length > 2) {
      _tafsirMemory.remove(_tafsirMemory.keys.first);
    }
    return value;
  }

  Future<AccountScopeSnapshot> captureAccount() => _database.captureAccount();

  void ensureAccountCurrent(AccountScopeSnapshot scope) =>
      _database.ensureCurrent(scope);

  Future<ReadingPosition> position({AccountScopeSnapshot? accountScope}) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    return _positionFor(scope);
  }

  Future<ReadingPosition> _positionFor(AccountScopeSnapshot scope) async {
    final rows = await _database.database.query(
      'reading_positions',
      where: 'owner_id = ? AND edition = ?',
      whereArgs: <Object?>[scope.userId, edition],
      limit: 1,
    );
    _database.ensureCurrent(scope);
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
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final current = await _positionFor(scope);
    final now = DateTime.now().toUtc();
    final operationId = _uuid.v4();
    final progress = ((page / 604) * 100).clamp(0, 100).toStringAsFixed(2);
    await _database.database.transaction((transaction) async {
      _database.ensureCurrent(scope);
      await transaction.insert('reading_positions', <String, Object?>{
        'owner_id': scope.userId,
        'edition': edition,
        'entity_id': current.entityId,
        'surah': surah,
        'ayah': ayah,
        'page': page,
        'server_revision': current.revision,
        'dirty': 1,
        'updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.delete(
        'outbox',
        where: 'owner_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>[
          scope.userId,
          'reading_position',
          current.entityId,
        ],
      );
      await transaction.insert('outbox', <String, Object?>{
        'owner_id': scope.userId,
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
    _database.ensureCurrent(scope);
  }

  Future<bool> isBookmarked(
    int surah,
    int ayah, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final rows = await _database.database.query(
      'bookmarks',
      columns: const <String>['id'],
      where:
          'owner_id = ? AND edition = ? AND surah = ? AND ayah = ? '
          'AND is_deleted = 0',
      whereArgs: <Object?>[scope.userId, edition, surah, ayah],
      limit: 1,
    );
    _database.ensureCurrent(scope);
    return rows.isNotEmpty;
  }

  Future<bool> toggleBookmark(
    int surah,
    int ayah, {
    int? page,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final rows = await _database.database.query(
      'bookmarks',
      where:
          'owner_id = ? AND edition = ? AND surah = ? AND ayah = ? '
          'AND is_deleted = 0',
      whereArgs: <Object?>[scope.userId, edition, surah, ayah],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    _database.ensureCurrent(scope);
    final now = DateTime.now().toUtc();
    if (rows.isNotEmpty) {
      final row = rows.single;
      final id = row['id']! as String;
      final revision = row['server_revision']! as int;
      await _database.database.transaction((transaction) async {
        _database.ensureCurrent(scope);
        if (revision == 0) {
          await transaction.delete(
            'bookmarks',
            where: 'owner_id = ? AND id = ?',
            whereArgs: <Object?>[scope.userId, id],
          );
          await transaction.delete(
            'outbox',
            where: 'owner_id = ? AND entity_id = ?',
            whereArgs: <Object?>[scope.userId, id],
          );
        } else {
          await transaction.update(
            'bookmarks',
            <String, Object?>{
              'is_deleted': 1,
              'updated_at': now.toIso8601String(),
            },
            where: 'owner_id = ? AND id = ?',
            whereArgs: <Object?>[scope.userId, id],
          );
          final operationId = _uuid.v4();
          await transaction.delete(
            'outbox',
            where: 'owner_id = ? AND entity_type = ? AND entity_id = ?',
            whereArgs: <Object?>[scope.userId, 'bookmark', id],
          );
          await transaction.insert(
            'outbox',
            _outboxRow(
              operationId: operationId,
              entityId: id,
              ownerId: scope.userId,
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
      _database.ensureCurrent(scope);
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
      _database.ensureCurrent(scope);
      await transaction.insert('bookmarks', <String, Object?>{
        'owner_id': scope.userId,
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
          ownerId: scope.userId,
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
    _database.ensureCurrent(scope);
    return true;
  }

  Future<List<Map<String, Object?>>> bookmarks({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final rows = await _database.database.query(
      'bookmarks',
      where: 'owner_id = ? AND is_deleted = 0',
      whereArgs: <Object?>[scope.userId],
      orderBy: 'updated_at DESC',
    );
    _database.ensureCurrent(scope);
    return rows;
  }

  Map<String, Object?> _outboxRow({
    required String operationId,
    required String entityId,
    required String ownerId,
    required DateTime now,
    required Map<String, Object?> body,
  }) {
    return <String, Object?>{
      'owner_id': ownerId,
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

List<QuranTranslationEdition> _parseTranslationEditions(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map(
        (item) =>
            QuranTranslationEdition.fromJson(Map<String, Object?>.from(item)),
      )
      .where((item) => item.sourceId > 0 && item.name.isNotEmpty)
      .toList(growable: false);
}

List<QuranAyahTranslation> _parseTranslations(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map(
        (item) =>
            QuranAyahTranslation.fromJson(Map<String, Object?>.from(item)),
      )
      .where((item) => item.verseKey.isNotEmpty && item.text.isNotEmpty)
      .toList(growable: false);
}

List<QuranTafsirEdition> _parseTafsirEditions(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map(
        (item) => QuranTafsirEdition.fromJson(Map<String, Object?>.from(item)),
      )
      .where((item) => item.sourceId > 0 && item.name.isNotEmpty)
      .toList(growable: false);
}

List<QuranAyahTafsir> _parseTafsirs(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map((item) => QuranAyahTafsir.fromJson(Map<String, Object?>.from(item)))
      .where((item) => item.verseKey.isNotEmpty && item.text.isNotEmpty)
      .toList(growable: false);
}

List<QuranDivision> _parseDivisions(Object? payload) {
  return jsonResults(payload)
      .whereType<Map>()
      .map((item) => QuranDivision.fromJson(Map<String, Object?>.from(item)))
      .where(
        (item) =>
            item.number > 0 &&
            item.startAyah.surah > 0 &&
            item.startAyah.ayah > 0,
      )
      .toList(growable: false);
}
