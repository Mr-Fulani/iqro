import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';

class DuaCategory {
  const DuaCategory({
    required this.id,
    required this.slug,
    required this.title,
    required this.entryCount,
  });

  factory DuaCategory.fromJson(Map<String, Object?> json) => DuaCategory(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    entryCount: (json['entry_count'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String slug;
  final String title;
  final int entryCount;
}

class DuaAudioAsset {
  const DuaAudioAsset({
    required this.id,
    required this.languageCode,
    required this.provider,
    required this.readerName,
    required this.readerNameAr,
    required this.url,
    required this.sourceUrl,
    required this.rightsUrl,
    required this.sourceVersion,
  });

  factory DuaAudioAsset.fromJson(Map<String, Object?> json) => DuaAudioAsset(
    id: json['id']?.toString() ?? '',
    languageCode: json['language_code']?.toString() ?? '',
    provider: json['provider']?.toString() ?? '',
    readerName: json['reader_name']?.toString() ?? '',
    readerNameAr: json['reader_name_ar']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    sourceUrl: json['source_url']?.toString() ?? '',
    rightsUrl: json['rights_url']?.toString() ?? '',
    sourceVersion: json['source_version']?.toString() ?? '',
  );

  final String id;
  final String languageCode;
  final String provider;
  final String readerName;
  final String readerNameAr;
  final String url;
  final String sourceUrl;
  final String rightsUrl;
  final String sourceVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'language_code': languageCode,
    'provider': provider,
    'reader_name': readerName,
    'reader_name_ar': readerNameAr,
    'url': url,
    'source_url': sourceUrl,
    'rights_url': rightsUrl,
    'source_version': sourceVersion,
  };
}

class DuaSourceEdition {
  const DuaSourceEdition({
    required this.languageCode,
    required this.provider,
    required this.sourceItemId,
    required this.title,
    required this.author,
    required this.translator,
    required this.reviewer,
    required this.sourceUrl,
    required this.rightsUrl,
    required this.sourceVersion,
  });

  factory DuaSourceEdition.fromJson(Map<String, Object?> json) =>
      DuaSourceEdition(
        languageCode: json['language_code']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        sourceItemId: json['source_item_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        author: json['author']?.toString() ?? '',
        translator: json['translator']?.toString() ?? '',
        reviewer: json['reviewer']?.toString() ?? '',
        sourceUrl: json['source_url']?.toString() ?? '',
        rightsUrl: json['rights_url']?.toString() ?? '',
        sourceVersion: json['source_version']?.toString() ?? '',
      );

  final String languageCode;
  final String provider;
  final String sourceItemId;
  final String title;
  final String author;
  final String translator;
  final String reviewer;
  final String sourceUrl;
  final String rightsUrl;
  final String sourceVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'language_code': languageCode,
    'provider': provider,
    'source_item_id': sourceItemId,
    'title': title,
    'author': author,
    'translator': translator,
    'reviewer': reviewer,
    'source_url': sourceUrl,
    'rights_url': rightsUrl,
    'source_version': sourceVersion,
  };
}

class DuaEvidence {
  const DuaEvidence({
    required this.kind,
    required this.provider,
    required this.sourceName,
    required this.sourceReference,
    required this.sourceUrl,
    required this.grade,
    required this.externalId,
    required this.verificationStatus,
  });

  factory DuaEvidence.fromJson(Map<String, Object?> json) => DuaEvidence(
    kind: json['kind']?.toString() ?? '',
    provider: json['provider']?.toString() ?? '',
    sourceName: json['source_name']?.toString() ?? '',
    sourceReference: json['source_reference']?.toString() ?? '',
    sourceUrl: json['source_url']?.toString() ?? '',
    grade: json['grade']?.toString() ?? '',
    externalId: json['external_id']?.toString() ?? '',
    verificationStatus: json['verification_status']?.toString() ?? '',
  );

  final String kind;
  final String provider;
  final String sourceName;
  final String sourceReference;
  final String sourceUrl;
  final String grade;
  final String externalId;
  final String verificationStatus;

  bool get isEditoriallyVerified =>
      verificationStatus == 'editorially_verified';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'provider': provider,
    'source_name': sourceName,
    'source_reference': sourceReference,
    'source_url': sourceUrl,
    'grade': grade,
    'external_id': externalId,
    'verification_status': verificationStatus,
  };
}

class DuaEntry {
  const DuaEntry({
    required this.id,
    required this.sourceNumber,
    required this.collection,
    this.collectionVersion = '',
    required this.categoryTitle,
    required this.arabicText,
    required this.meaning,
    required this.transliteration,
    required this.repetitions,
    required this.sourceLabel,
    this.repetitionLabel = '',
    this.source,
    this.evidence = const <DuaEvidence>[],
    this.audio = const <DuaAudioAsset>[],
  });

  factory DuaEntry.fromJson(Map<String, Object?> json) {
    final category = json['category'] is Map
        ? Map<String, Object?>.from(json['category']! as Map)
        : const <String, Object?>{};
    final translation = json['translation'] is Map
        ? Map<String, Object?>.from(json['translation']! as Map)
        : const <String, Object?>{};
    final source = json['source'] is Map
        ? Map<String, Object?>.from(json['source']! as Map)
        : const <String, Object?>{};
    final sourceEdition = source.isEmpty
        ? null
        : DuaSourceEdition.fromJson(source);
    final legacySourceLabel = json['source_label']?.toString() ?? '';
    final sourceLabel = sourceEdition == null
        ? legacySourceLabel
        : sourceEdition.title.isNotEmpty
        ? sourceEdition.title
        : sourceEdition.provider.isNotEmpty
        ? sourceEdition.provider
        : legacySourceLabel;
    final repetitions = (json['repetitions'] as num?)?.toInt() ?? 1;
    return DuaEntry(
      id: json['id']?.toString() ?? '',
      sourceNumber: (json['source_number'] as num?)?.toInt() ?? 0,
      collection: json['collection']?.toString() ?? 'hisn-al-muslim',
      collectionVersion: json['collection_version']?.toString() ?? '',
      categoryTitle:
          category['title']?.toString() ??
          json['category_title']?.toString() ??
          '',
      arabicText: json['arabic_text']?.toString() ?? '',
      meaning:
          translation['meaning_text']?.toString() ??
          json['meaning']?.toString() ??
          '',
      transliteration:
          translation['transliteration']?.toString() ??
          json['transliteration']?.toString() ??
          '',
      repetitions: repetitions > 0 ? repetitions : 1,
      repetitionLabel: json['repetition_label']?.toString() ?? '',
      source: sourceEdition,
      evidence: _modelList(json['evidence'], DuaEvidence.fromJson),
      audio: _modelList(json['audio'], DuaAudioAsset.fromJson),
      sourceLabel: sourceLabel,
    );
  }

  final String id;
  final int sourceNumber;
  final String collection;
  final String collectionVersion;
  final String categoryTitle;
  final String arabicText;
  final String meaning;
  final String transliteration;
  final int repetitions;
  final String repetitionLabel;
  final String sourceLabel;
  final DuaSourceEdition? source;
  final List<DuaEvidence> evidence;
  final List<DuaAudioAsset> audio;

  String get favoriteKey => 'dua:$collection:$sourceNumber';
  bool get hasDeclaredSource =>
      source != null ||
      sourceLabel.trim().isNotEmpty ||
      evidence.any(
        (item) =>
            item.provider.trim().isNotEmpty ||
            item.sourceName.trim().isNotEmpty ||
            item.sourceReference.trim().isNotEmpty,
      );
  bool get isEditoriallyVerified =>
      evidence.isNotEmpty &&
      evidence.every((item) => item.isEditoriallyVerified);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source_number': sourceNumber,
    'collection': collection,
    'collection_version': collectionVersion,
    'category_title': categoryTitle,
    'category': <String, Object?>{'title': categoryTitle},
    'arabic_text': arabicText,
    'meaning': meaning,
    'transliteration': transliteration,
    'translation': <String, Object?>{
      'meaning_text': meaning,
      'transliteration': transliteration,
    },
    'repetitions': repetitions,
    'repetition_label': repetitionLabel,
    'source_label': sourceLabel,
    'source': source?.toJson(),
    'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
    'audio': audio.map((item) => item.toJson()).toList(growable: false),
  };

  factory DuaEntry.fromFavorite(Map<String, Object?> json) =>
      DuaEntry.fromJson(json);
}

List<T> _modelList<T>(
  Object? value,
  T Function(Map<String, Object?>) fromJson,
) => value is List
    ? value
          .whereType<Map>()
          .map((item) => fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false)
    : <T>[];

abstract interface class DuaRemoteGateway {
  Uri get apiBaseUri;

  Future<Object?> categories(String locale);

  Future<Object?> entries(
    String locale, {
    String? category,
    String? cursor,
    required int pageSize,
  });

  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite,
  );
}

class ApiDuaRemoteGateway implements DuaRemoteGateway {
  ApiDuaRemoteGateway(this._api);

  final ApiClient _api;

  @override
  Uri get apiBaseUri => Uri.parse(_api.dio.options.baseUrl);

  @override
  Future<Object?> categories(String locale) => _api.get(
    '/dua/categories',
    query: <String, Object?>{'language': locale},
    public: true,
  );

  @override
  Future<Object?> entries(
    String locale, {
    String? category,
    String? cursor,
    required int pageSize,
  }) => _api.get(
    '/dua/entries',
    query: <String, Object?>{
      'language': locale,
      'category': ?category,
      'page_size': pageSize,
      'cursor': ?cursor,
    },
    public: true,
  );

  @override
  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite,
  ) async {
    await _api.put(
      '/me/dua-favorites/$collection/$sourceNumber',
      data: <String, Object?>{'is_favorite': isFavorite},
    );
  }
}

class DuaRepository {
  DuaRepository({
    ApiClient? api,
    DuaRemoteGateway? remote,
    required LocalDatabase database,
    Uuid? uuid,
  }) : assert(api != null || remote != null),
       _remote = remote ?? ApiDuaRemoteGateway(api!),
       _database = database,
       _uuid = uuid ?? const Uuid();

  static const _entryPageSize = 100;
  static const _featuredEntryCount = 20;
  static const _maxEntryPages = 50;
  static const _entryCacheVersion = 'v3';

  final DuaRemoteGateway _remote;
  final LocalDatabase _database;
  final Uuid _uuid;

  String get _cacheNamespace {
    final base = _remote.apiBaseUri;
    final scheme = base.scheme.toLowerCase();
    if (!base.isAbsolute ||
        (scheme != 'http' && scheme != 'https') ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException('Dua API base URL is invalid');
    }
    final normalizedPath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final canonical = Uri(
      scheme: scheme,
      host: base.host.toLowerCase(),
      port: _effectivePort(base),
      path: normalizedPath,
    );
    return Uri.encodeComponent(canonical.toString());
  }

  Future<CachedValue?> _readCacheSafely(String key) async {
    try {
      return await _database.readCache(key);
    } on Object {
      // A malformed or partially written local row is a cache miss. The row
      // is deliberately preserved for diagnostics and replaced only after a
      // complete, validated network response.
      return null;
    }
  }

  Future<void> _writeCacheSafely(String key, Object? payload) async {
    try {
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
    } on Object {
      // Caching must not turn a valid online response into a user-facing
      // failure. A later request can try persisting the catalog again.
    }
  }

  Future<List<DuaCategory>> categories(String locale) async {
    final key = 'dua:$_cacheNamespace:categories:$locale';
    final cached = await _readCacheSafely(key);
    if (cached?.isFresh == true) {
      try {
        return _parseCategories(cached!.value);
      } on Object {
        // Ignore malformed local data and replace it after a complete load.
      }
    }
    try {
      final payload = await _remote.categories(locale);
      final parsed = _parseCategories(payload);
      await _writeCacheSafely(key, payload);
      return parsed;
    } on Object catch (error, stack) {
      if (cached != null) {
        try {
          return _parseCategories(cached.value);
        } on Object {
          // Preserve the online error when the fallback cache is also invalid.
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<List<DuaEntry>> entries(String locale, {String? category}) async {
    final key =
        'dua:$_cacheNamespace:entries:$_entryCacheVersion:'
        '$locale:${category ?? 'all'}';
    final cached = await _readCacheSafely(key);
    if (cached?.isFresh == true) {
      try {
        return _parseCompleteEntryPayload(cached!.value);
      } on Object {
        // A malformed cache is ignored and replaced only after a complete load.
      }
    }
    try {
      final payload = await _completeEntryPayload(locale, category: category);
      final parsed = _parseCompleteEntryPayload(payload);
      await _writeCacheSafely(key, payload);
      return parsed;
    } on Object catch (error, stack) {
      if (cached != null) {
        try {
          return _parseCompleteEntryPayload(cached.value);
        } on Object {
          // Preserve the online error when the fallback cache is also invalid.
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Loads a small deterministic first page for surfaces such as Home.
  /// Category browsing uses [entries] and still exhausts the full cursor.
  Future<List<DuaEntry>> featuredEntries(String locale) async {
    final key = 'dua:$_cacheNamespace:featured:$_entryCacheVersion:$locale';
    final cached = await _readCacheSafely(key);
    if (cached?.isFresh == true) {
      try {
        return _parseEntryPageResults(cached!.value);
      } on Object {
        // Ignore malformed local data and replace it after a valid response.
      }
    }
    try {
      final payload = await _remote.entries(
        locale,
        pageSize: _featuredEntryCount,
      );
      final parsed = _parseEntryPageResults(payload);
      await _writeCacheSafely(key, payload);
      return parsed;
    } on Object catch (error, stack) {
      if (cached != null) {
        try {
          return _parseEntryPageResults(cached.value);
        } on Object {
          // Preserve the online error when the fallback cache is also invalid.
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool> isFavorite(DuaEntry entry) async {
    final rows = await _database.database.query(
      'favorites',
      columns: const <String>['item_key'],
      where: 'item_key = ?',
      whereArgs: <Object?>[entry.favoriteKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> toggleFavorite(DuaEntry entry) async {
    final active = await isFavorite(entry);
    final operationId = _uuid.v7();
    final payload = <String, Object?>{
      'collection': entry.collection,
      'source_number': entry.sourceNumber,
      'is_favorite': !active,
    };
    await _database.database.transaction((transaction) async {
      if (active) {
        await transaction.delete(
          'favorites',
          where: 'item_key = ?',
          whereArgs: <Object?>[entry.favoriteKey],
        );
      } else {
        await transaction.insert('favorites', <String, Object?>{
          'item_key': entry.favoriteKey,
          'kind': 'dua',
          'payload': jsonEncode(entry.toJson()),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await transaction.delete(
        'outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>['dua_favorite', entry.favoriteKey],
      );
      await transaction.insert('outbox', <String, Object?>{
        'operation_id': operationId,
        'entity_type': 'dua_favorite',
        'entity_id': entry.favoriteKey,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    try {
      await _remote.setFavorite(entry.collection, entry.sourceNumber, !active);
      await _database.acknowledgeOutbox(operationId);
    } on Object catch (error) {
      await _database.markOutboxFailure(operationId, error.toString());
    }
    return !active;
  }

  Future<List<DuaEntry>> favorites() async {
    final rows = await _database.database.query(
      'favorites',
      where: 'kind = ?',
      whereArgs: const <Object?>['dua'],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) {
          final payload = jsonDecode(row['payload']! as String);
          return DuaEntry.fromFavorite(
            Map<String, Object?>.from(payload as Map),
          );
        })
        .toList(growable: false);
  }

  List<DuaCategory> _parseCategories(Object? payload) {
    if (payload is! List || payload.any((item) => item is! Map)) {
      throw const FormatException('Dua categories payload is invalid');
    }
    return payload
        .map((item) {
          final category = DuaCategory.fromJson(
            Map<String, Object?>.from(item! as Map),
          );
          if (category.id.isEmpty ||
              category.slug.isEmpty ||
              category.title.isEmpty ||
              category.entryCount < 0) {
            throw const FormatException(
              'Dua category is missing required fields',
            );
          }
          return category;
        })
        .toList(growable: false);
  }

  List<DuaEntry> _parseCompleteEntryPayload(Object? payload) {
    final page = _validatedEntryPage(payload);
    if (page['next'] != null) {
      throw const FormatException('Cached Dua catalog is incomplete');
    }
    return (page['results']! as List<Object?>)
        .map((item) => _validatedRemoteEntry(item))
        .toList(growable: false);
  }

  List<DuaEntry> _parseEntryPageResults(Object? payload) {
    final page = _validatedEntryPage(payload);
    _nextCursor(page);
    final results = page['results']! as List<Object?>;
    if (results.length > _featuredEntryCount) {
      throw const FormatException('Featured Dua page exceeds the safe limit');
    }
    return results
        .map((item) => _validatedRemoteEntry(item))
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _completeEntryPayload(
    String locale, {
    String? category,
  }) async {
    final entries = <DuaEntry>[];
    final identities = <String>{};
    final cursors = <String>{};
    final collectionVersions = <String, String>{};
    String? cursor;

    for (var page = 0; page < _maxEntryPages; page += 1) {
      final payload = await _remote.entries(
        locale,
        category: category,
        cursor: cursor,
        pageSize: _entryPageSize,
      );
      final pagePayload = _validatedEntryPage(payload);
      for (final item in pagePayload['results']! as List<Object?>) {
        final entry = _validatedRemoteEntry(item);
        final previousVersion = collectionVersions[entry.collection];
        if (previousVersion != null &&
            previousVersion != entry.collectionVersion) {
          throw const FormatException(
            'Dua collection version changed during pagination',
          );
        }
        collectionVersions[entry.collection] = entry.collectionVersion;
        if (!identities.add(entry.favoriteKey)) continue;
        entries.add(entry);
      }

      final nextCursor = _nextCursor(pagePayload);
      if (nextCursor == null) {
        return <String, Object?>{
          'count': entries.length,
          'next': null,
          'previous': null,
          'results': entries
              .map((entry) => entry.toJson())
              .toList(growable: false),
        };
      }
      if (page == _maxEntryPages - 1) {
        throw const FormatException('Dua pagination exceeds the safe limit');
      }
      if (!cursors.add(nextCursor)) {
        throw const FormatException('Dua pagination cursor repeated');
      }
      cursor = nextCursor;
    }
    throw const FormatException('Dua pagination did not terminate');
  }

  String? _nextCursor(Object? payload) {
    if (payload is! Map || payload['next'] == null) return null;
    final rawNext = payload['next'];
    if (rawNext is! String || rawNext.isEmpty || rawNext.length > 8192) {
      throw const FormatException('Dua pagination link is invalid');
    }
    final next = Uri.tryParse(rawNext);
    final base = _remote.apiBaseUri;
    if (next == null ||
        !base.isAbsolute ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('Dua pagination link is invalid');
    }
    final resolved = next.isAbsolute ? next : base.resolveUri(next);
    final expectedPath =
        '${base.path.replaceFirst(RegExp(r'/+$'), '')}'
        '/dua/entries';
    if (resolved.scheme.toLowerCase() != base.scheme.toLowerCase() ||
        resolved.host.toLowerCase() != base.host.toLowerCase() ||
        _effectivePort(resolved) != _effectivePort(base) ||
        resolved.userInfo.isNotEmpty ||
        resolved.hasFragment ||
        resolved.path != expectedPath) {
      throw const FormatException('Dua pagination link is not trusted');
    }
    final values = resolved.queryParametersAll['cursor'];
    if (values == null ||
        values.length != 1 ||
        values.single.isEmpty ||
        values.single.length > 4096) {
      throw const FormatException('Dua pagination cursor is invalid');
    }
    return values.single;
  }

  Map<String, Object?> _validatedEntryPage(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('Dua page must be a JSON object');
    }
    final page = Map<String, Object?>.from(payload);
    final results = page['results'];
    if (results is! List || results.any((item) => item is! Map)) {
      throw const FormatException('Dua page results are invalid');
    }
    final next = page['next'];
    if (next != null && next is! String) {
      throw const FormatException('Dua pagination link is invalid');
    }
    return <String, Object?>{...page, 'results': List<Object?>.from(results)};
  }

  DuaEntry _validatedRemoteEntry(Object? value) {
    if (value is! Map) {
      throw const FormatException('Dua entry is invalid');
    }
    final json = Map<String, Object?>.from(value);
    final sourceNumber = json['source_number'];
    final repetitions = json['repetitions'];
    final category = json['category'];
    if (json['id'] is! String ||
        (json['id']! as String).trim().isEmpty ||
        sourceNumber is! int ||
        sourceNumber < 1 ||
        json['collection'] is! String ||
        (json['collection']! as String).trim().isEmpty ||
        json['collection_version'] is! String ||
        (json['collection_version']! as String).trim().isEmpty ||
        category is! Map ||
        category['title'] is! String ||
        (category['title']! as String).trim().isEmpty ||
        json['arabic_text'] is! String ||
        (json['arabic_text']! as String).trim().isEmpty ||
        repetitions is! int ||
        repetitions < 1 ||
        repetitions > _maxPracticeRepetitions) {
      throw const FormatException('Dua entry is missing required fields');
    }
    if (json['category'] is! Map ||
        (json['translation'] != null && json['translation'] is! Map) ||
        (json['source'] != null && json['source'] is! Map) ||
        json['evidence'] is! List ||
        (json['evidence']! as List).any((item) => item is! Map) ||
        json['audio'] is! List ||
        (json['audio']! as List).any((item) => item is! Map)) {
      throw const FormatException('Dua entry metadata is invalid');
    }
    for (final rawEvidence in json['evidence']! as List) {
      final evidence = Map<String, Object?>.from(rawEvidence! as Map);
      final kind = evidence['kind']?.toString() ?? '';
      final status = evidence['verification_status']?.toString() ?? '';
      if (!_supportedEvidenceKinds.contains(kind) ||
          evidence['provider']?.toString().trim().isEmpty != false ||
          evidence['source_name']?.toString().trim().isEmpty != false ||
          evidence['source_reference']?.toString().trim().isEmpty != false ||
          (status != 'source_only' && status != 'editorially_verified')) {
        throw const FormatException('Dua evidence is invalid');
      }
    }
    for (final rawAudio in json['audio']! as List) {
      final audio = Map<String, Object?>.from(rawAudio! as Map);
      if (audio['id']?.toString().trim().isEmpty != false ||
          audio['provider']?.toString().trim().isEmpty != false ||
          audio['reader_name']?.toString().trim().isEmpty != false ||
          !_isAbsoluteHttpsUrl(audio['url']) ||
          !_isAbsoluteHttpsUrl(audio['source_url']) ||
          audio['source_version']?.toString().trim().isEmpty != false) {
        throw const FormatException('Dua audio metadata is invalid');
      }
    }
    final entry = DuaEntry.fromJson(json);
    if (entry.id.isEmpty ||
        entry.sourceNumber < 1 ||
        entry.collection.isEmpty ||
        entry.collectionVersion.isEmpty ||
        entry.categoryTitle.isEmpty ||
        entry.arabicText.isEmpty) {
      throw const FormatException('Dua entry is missing required fields');
    }
    return entry;
  }
}

const int _maxPracticeRepetitions = 10000;
const Set<String> _supportedEvidenceKinds = <String>{
  'hadith',
  'quran',
  'source_note',
};

bool _isAbsoluteHttpsUrl(Object? value) {
  final uri = Uri.tryParse(value?.toString() ?? '');
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}
