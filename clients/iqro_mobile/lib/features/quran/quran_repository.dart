import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/public_asset_uri.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'quran_models.dart';
import 'mushaf_edition.dart';

typedef MushafDigestReader = Future<String> Function(File file);

class MushafAssetVerificationCache {
  MushafAssetVerificationCache({
    this.maxEntries = 12,
    MushafDigestReader? digestReader,
  }) : assert(maxEntries > 0),
       _digestReader = digestReader ?? _readSha256;

  final int maxEntries;
  final MushafDigestReader _digestReader;
  final LinkedHashMap<String, _VerifiedMushafAsset> _verified =
      LinkedHashMap<String, _VerifiedMushafAsset>();

  Future<bool> verify(
    File file,
    String expectedChecksum, {
    required int? expectedBytes,
  }) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          (expectedBytes != null && stat.size != expectedBytes)) {
        _verified.remove(file.path);
        return false;
      }
      final stamp = _VerifiedMushafAsset(
        checksum: expectedChecksum,
        expectedBytes: expectedBytes,
        actualBytes: stat.size,
        modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
        changedMicroseconds: stat.changed.microsecondsSinceEpoch,
      );
      final cached = _verified.remove(file.path);
      if (cached == stamp) {
        _verified[file.path] = cached!;
        return true;
      }
      final handle = await file.open();
      late final List<int> header;
      try {
        header = await handle.read(16);
      } finally {
        await handle.close();
      }
      if (!_validWebp(header) ||
          (expectedChecksum.isNotEmpty &&
              await _digestReader(file) != expectedChecksum)) {
        _verified.remove(file.path);
        return false;
      }
      _remember(file.path, stamp);
      return true;
    } on FileSystemException {
      _verified.remove(file.path);
      return false;
    }
  }

  Future<void> rememberVerified(
    File file,
    String expectedChecksum, {
    required int? expectedBytes,
  }) async {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        (expectedBytes != null && stat.size != expectedBytes)) {
      return;
    }
    _remember(
      file.path,
      _VerifiedMushafAsset(
        checksum: expectedChecksum,
        expectedBytes: expectedBytes,
        actualBytes: stat.size,
        modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
        changedMicroseconds: stat.changed.microsecondsSinceEpoch,
      ),
    );
  }

  void _remember(String path, _VerifiedMushafAsset stamp) {
    _verified.remove(path);
    _verified[path] = stamp;
    while (_verified.length > maxEntries) {
      _verified.remove(_verified.keys.first);
    }
  }

  static Future<String> _readSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

class _VerifiedMushafAsset {
  const _VerifiedMushafAsset({
    required this.checksum,
    required this.expectedBytes,
    required this.actualBytes,
    required this.modifiedMicroseconds,
    required this.changedMicroseconds,
  });

  final String checksum;
  final int? expectedBytes;
  final int actualBytes;
  final int modifiedMicroseconds;
  final int changedMicroseconds;

  @override
  bool operator ==(Object other) =>
      other is _VerifiedMushafAsset &&
      other.checksum == checksum &&
      other.expectedBytes == expectedBytes &&
      other.actualBytes == actualBytes &&
      other.modifiedMicroseconds == modifiedMicroseconds &&
      other.changedMicroseconds == changedMicroseconds;

  @override
  int get hashCode => Object.hash(
    checksum,
    expectedBytes,
    actualBytes,
    modifiedMicroseconds,
    changedMicroseconds,
  );
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

class QuranRepository {
  QuranRepository({
    required ApiClient api,
    required LocalDatabase database,
    Uuid? uuid,
    this.mushaf = MushafIdentity.primary,
    this.foundationVersion = '',
  }) : _api = api,
       _database = database,
       _uuid = uuid ?? const Uuid();

  static const edition = 'madani-hafs';
  final MushafIdentity mushaf;
  final String foundationVersion;

  QuranRepository withFoundationVersion(String version) =>
      !mushaf.isFoundation || version == foundationVersion
      ? this
      : QuranRepository(
          api: _api,
          database: _database,
          uuid: _uuid,
          mushaf: mushaf,
          foundationVersion: version,
        );

  QuranRepository forMushaf(MushafIdentity identity) => identity == mushaf
      ? this
      : QuranRepository(
          api: _api,
          database: _database,
          uuid: _uuid,
          mushaf: identity,
        );

  Future<List<NativeMushafEdition>> mushafRenditions({
    bool forceRefresh = false,
  }) async {
    final key = 'mushaf-renditions:${_api.dio.options.baseUrl}';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseRenditions(cached!.value);
    }
    try {
      Object? foundation;
      try {
        foundation = await _api.get('/quran/foundation/mushafs', public: true);
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      final legacy = await _api.get('/quran/mushaf-renditions', public: true);
      final payload = <Object?>[
        if (foundation is List) ...foundation,
        if (legacy is List) ...legacy,
      ];
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(hours: 1),
      );
      return _parseRenditions(payload);
    } on Object {
      if (cached != null) return _parseRenditions(cached.value);
      rethrow;
    }
  }

  /// Previously published catalog, scoped to this API origin. A cold offline
  /// start must not wait for an HTTP timeout to authorize a downloaded edition.
  Future<List<NativeMushafEdition>> cachedMushafRenditions() async {
    final cached = await _database.readCache(
      'mushaf-renditions:${_api.dio.options.baseUrl}',
    );
    return _parseRenditions(cached?.value);
  }

  static List<NativeMushafEdition> _parseRenditions(Object? payload) {
    if (payload is! List) return const [];
    final editions = payload
        .whereType<Map>()
        .map((e) {
          final json = Map<String, Object?>.from(e);
          return json.containsKey('source_id')
              ? NativeMushafEdition.fromFoundation(json)
              : NativeMushafEdition.parse(json);
        })
        .whereType<NativeMushafEdition>()
        .toList();
    // Raster copies remain a fallback for older backends/offline catalogs.
    // Avoid duplicate choices when the direct source is available.
    for (final entry in const {
      5: 'kfgqpc-hafs',
      1: 'qcf-v2-hafs',
      19: 'qcf-v4-tajweed-hafs',
    }.entries) {
      if (editions.any((e) => e.identity.foundationId == entry.key)) {
        editions.removeWhere((e) => e.identity.code == entry.value);
      }
    }
    return editions;
  }

  final ApiClient _api;
  final LocalDatabase _database;
  final Uuid _uuid;
  final Map<(String, int, int, int?, String), Future<File>> _pageAssetRequests =
      <(String, int, int, int?, String), Future<File>>{};
  final Set<(int, String, int, int)> _pageResolutionRefreshAttempts =
      <(int, String, int, int)>{};
  final MushafAssetVerificationCache _pageAssetVerifier =
      MushafAssetVerificationCache();
  final Map<String, List<QuranAyahTranslation>> _translationMemory = {};
  final Map<String, List<QuranAyahTafsir>> _tafsirMemory = {};
  static final _foundationAssetRequests = <String, Future<File>>{};

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
    return _divisions('juz', forceRefresh: forceRefresh);
  }

  Future<List<QuranDivision>> hizb({bool forceRefresh = false}) async {
    return _divisions('hizb', forceRefresh: forceRefresh);
  }

  Future<List<QuranDivision>> rubElHizb({bool forceRefresh = false}) async {
    return _divisions('rub-el-hizb', forceRefresh: forceRefresh);
  }

  Future<List<QuranDivision>> _divisions(
    String kind, {
    required bool forceRefresh,
  }) async {
    final key = 'quran:$edition:$kind';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _parseDivisions(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/quran/editions/$edition/$kind',
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
    final key =
        '${mushaf.pageCacheKey(page)}${foundationVersion.isEmpty ? '' : ':$foundationVersion'}${mushaf.isFoundation ? ':qul-layout-v1' : ''}';
    final cached = await _database.readCache(key);
    MushafPageData? previous;
    if (cached != null) {
      try {
        previous = _parseMushafPage(cached.value, page);
      } on Object {
        // Retry the API when cached metadata is corrupt or belongs to another version.
      }
      if (!forceRefresh && cached.isFresh && previous != null) return previous;
    }
    try {
      final payload = await _api.get(
        '${mushaf.apiPath}/pages/$page',
        public: true,
      );
      final parsed = _parseMushafPage(payload, page);
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(days: 30),
      );
      return parsed;
    } on Object {
      if (previous != null) return previous;
      rethrow;
    }
  }

  MushafPageData _parseMushafPage(Object? payload, int number) {
    final parsed = mushaf.isFoundation
        ? MushafPageData.fromFoundation(jsonMap(payload))
        : MushafPageData.fromJson(jsonMap(payload));
    if (parsed.number != number || parsed.editionCode != mushaf.code) {
      throw const FormatException('Mushaf page identity mismatch');
    }
    if (mushaf.isFoundation &&
        foundationVersion.isNotEmpty &&
        parsed.contentVersion != foundationVersion) {
      throw const FormatException('Mushaf source version changed');
    }
    return parsed;
  }

  Future<Map<String, List<int>>> foundationPageIndex() async {
    if (!mushaf.isFoundation) return const {};
    final key = '${mushaf.contentKey}:page-index:$foundationVersion';
    final cached = await _database.readCache(key);
    Map<String, List<int>>? previous;
    if (cached != null) {
      try {
        previous = _parseFoundationIndex(cached.value);
      } on Object {
        // Invalid cached metadata cannot authorize a navigation.
      }
      if (cached.isFresh && previous != null) return previous;
    }
    try {
      final payload = await _api.get(
        '${mushaf.apiPath}/page-index',
        public: true,
      );
      final parsed = _parseFoundationIndex(payload);
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(hours: 1),
      );
      return parsed;
    } on Object {
      if (previous == null) rethrow;
      return previous;
    }
  }

  Map<String, List<int>> _parseFoundationIndex(Object? payload) {
    final value = jsonMap(payload);
    if (value['mushaf_id'] != mushaf.foundationId) {
      throw const FormatException('Mushaf index identity mismatch');
    }
    if (foundationVersion.isNotEmpty &&
        value['source_checksum_sha256'] != foundationVersion) {
      throw const FormatException('Mushaf index version changed');
    }
    final count = value['pages_count'];
    if (count is! int || count < 1 || count > 1000) {
      throw const FormatException('Invalid Mushaf page count');
    }
    return jsonMap(value['verse_pages']).map((key, value) {
      if (value is! List ||
          value.isEmpty ||
          value.any((page) => page is! int || page < 1 || page > count)) {
        throw const FormatException('Invalid Mushaf verse pages');
      }
      return MapEntry(key, value.cast<int>());
    });
  }

  Future<int> pageForAyah(int surah, int ayah, {required int fallback}) async {
    if (!mushaf.isFoundation) return fallback;
    final pages = (await foundationPageIndex())['$surah:$ayah'];
    if (pages == null || pages.isEmpty) {
      throw const FormatException('Missing Mushaf verse mapping');
    }
    return pages.first;
  }

  Future<File> foundationAsset(Uri uri, String version) {
    final key = '${_api.dio.options.baseUrl}:$uri:$version';
    return _foundationAssetRequests.putIfAbsent(key, () async {
      try {
        return await _loadFoundationAsset(uri, version);
      } finally {
        _foundationAssetRequests.remove(key);
      }
    });
  }

  Future<File> _loadFoundationAsset(Uri uri, String version) async {
    final allowedFont =
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        ((uri.host == 'verses.quran.foundation' &&
                uri.path.startsWith('/fonts/quran/') &&
                uri.path.endsWith('.ttf')) ||
            (uri.host == 'static-cdn.tarteel.ai' &&
                uri.path ==
                    '/qul/fonts/nastaleeq/KFGQPCNastaleeq-Regular.ttf'));
    final allowedImage =
        uri.origin == 'https://static.qurancdn.com' &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        uri.query == 'v=1' &&
        RegExp(
          r'^/images/w/(?:(?:qa-color|rq-color|qa-black)/[1-9]\d*/[1-9]\d*/[1-9]\d*|common/[1-9]\d*)\.png$',
        ).hasMatch(uri.path);
    if (!allowedFont && !allowedImage) {
      throw const FormatException('Unapproved Quran asset');
    }
    final key =
        'foundation-asset:${sha256.convert(utf8.encode('$uri:$version'))}';
    final cached = await _database.readCache(key);
    if (cached != null) {
      final value = jsonMap(cached.value);
      final file = File(value['path'] as String);
      try {
        if (await file.length() == value['bytes'] &&
            (await sha256.bind(file.openRead()).first).toString() ==
                value['sha256']) {
          return file;
        }
      } on FileSystemException {
        // A missing or damaged file is downloaded again.
      }
    }
    final bytes = await _api.getPublicBytes(
      uri,
      allowedHosts: const {
        'verses.quran.foundation',
        'static-cdn.tarteel.ai',
        'static.qurancdn.com',
      },
      maxBytes: 8 * 1024 * 1024,
    );
    final checksum = sha256.convert(bytes).toString();
    final root = await getApplicationSupportDirectory();
    final file = File(
      p.join(
        root.path,
        'foundation_assets',
        '$checksum${p.extension(uri.path)}',
      ),
    );
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${_uuid.v4()}.partial');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    await _database.writeCache(key, {
      'path': file.path,
      'sha256': checksum,
      'bytes': bytes.length,
    }, maxAge: const Duration(days: 30));
    return file;
  }

  Future<bool> refreshMushafPageResolution(
    MushafPageData current, {
    required int minimumWidth,
  }) async {
    if (minimumWidth <= 0 || current.maximumAssetWidth >= minimumWidth) {
      return false;
    }
    final attempt = (
      current.number,
      current.contentVersion,
      current.maximumAssetWidth,
      minimumWidth,
    );
    if (!_pageResolutionRefreshAttempts.add(attempt)) return false;

    final refreshed = await mushafPage(current.number, forceRefresh: true);
    return refreshed.contentVersion != current.contentVersion ||
        refreshed.maximumAssetWidth > current.maximumAssetWidth;
  }

  Future<File> cachedMushafPageAsset(
    MushafPageData page,
    MushafAsset asset,
  ) async {
    if (page.editionCode != mushaf.code) {
      throw const FormatException('Mushaf asset edition mismatch');
    }
    final checksum = asset.sha256.isNotEmpty
        ? asset.sha256
        : page.checksumSha256;
    final requestKey = (
      page.contentVersion,
      page.number,
      asset.width,
      asset.bytes,
      checksum,
    );
    final existing = _pageAssetRequests[requestKey];
    if (existing != null) return existing;
    final request = _cachedMushafPageAsset(page, asset, checksum);
    _pageAssetRequests[requestKey] = request;
    try {
      return await request;
    } finally {
      if (identical(_pageAssetRequests[requestKey], request)) {
        _pageAssetRequests.remove(requestKey);
      }
    }
  }

  Future<File> _cachedMushafPageAsset(
    MushafPageData page,
    MushafAsset asset,
    String checksum,
  ) async {
    final offline = await _activeOfflineMushafPage(page, checksum);
    if (offline != null) return offline;
    final supportDirectory = await getApplicationSupportDirectory();
    final safeVersion = page.contentVersion.replaceAll(
      RegExp('[^a-zA-Z0-9._-]'),
      '_',
    );
    final checksumPrefix = checksum.length >= 16
        ? checksum.substring(0, 16)
        : 'unversioned';
    final directory = Directory(
      p.join(supportDirectory.path, 'mushaf_pages', mushaf.code, safeVersion),
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
    final downloaded = await _downloadMushafPageAsset(
      file,
      asset,
      expectedChecksum: checksum,
    );
    await _pageAssetVerifier.rememberVerified(
      downloaded,
      checksum,
      expectedBytes: asset.bytes,
    );
    return downloaded;
  }

  Future<File?> _activeOfflineMushafPage(
    MushafPageData page,
    String expectedChecksum,
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
      <Object?>[mushaf.contentKey, page.number, expectedChecksum],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = File(row['local_path']! as String);
    return await _pageAssetVerifier.verify(
          file,
          row['checksum_sha256']! as String,
          expectedBytes: row['size_bytes']! as int,
        )
        ? file
        : null;
  }

  Future<File> _downloadMushafPageAsset(
    File file,
    MushafAsset asset, {
    required String expectedChecksum,
  }) async {
    final uri = resolvePublicAssetUri(
      asset.url,
      Uri.parse(_api.dio.options.baseUrl),
    );
    if (!uri.path.toLowerCase().endsWith('.webp')) {
      throw const FormatException('Mushaf page URL is invalid');
    }
    final bytes = await _api.getPublicBytes(
      uri,
      allowedHosts: const <String>{'media.iqro.forum'},
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
  }) => _pageAssetVerifier.verify(
    file,
    expectedChecksum,
    expectedBytes: expectedBytes,
  );

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
