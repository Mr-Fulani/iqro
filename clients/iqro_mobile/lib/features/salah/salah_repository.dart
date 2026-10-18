import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import '../dua/dua_repository.dart' show canUseUnverifiedDuaFallback;
import 'salah_models.dart';

/// The only course of the first version (Hanbali, «Umdat al-Fiqh»).
const salahDefaultCourseSlug = 'hanbali-umdah';

/// The course is not published, or was withdrawn.
class SalahCourseUnavailable implements Exception {
  const SalahCourseUnavailable(this.slug);

  final String slug;

  @override
  String toString() => 'Salah course "$slug" is not published';
}

abstract interface class SalahRemoteGateway {
  Future<Object?> courses();

  Future<Object?> course(String slug, String language);
}

class ApiSalahRemoteGateway implements SalahRemoteGateway {
  ApiSalahRemoteGateway(this._api);

  final ApiClient _api;

  @override
  Future<Object?> courses() => _api.get('/salah/courses', public: true);

  @override
  Future<Object?> course(String slug, String language) => _api.get(
    '/salah/courses/${Uri.encodeComponent(slug)}',
    query: <String, Object?>{'language': language},
    public: true,
  );
}

/// Loads the compiled course document and keeps it in the local cache.
///
/// A published version never changes, so the cache key carries it
/// (`salah:<slug>:<lang>:<version>`). Like `DuaRepository`, the cached copy
/// is trusted only after the course list confirms its version is still the
/// active one. Without a network the last confirmed version is used.
class SalahRepository {
  SalahRepository({
    ApiClient? api,
    SalahRemoteGateway? remote,
    required LocalDatabase database,
  }) : assert(api != null || remote != null),
       _remote = remote ?? ApiSalahRemoteGateway(api!),
       _database = database;

  static const _documentMaxAge = Duration(days: 30);

  final SalahRemoteGateway _remote;
  final LocalDatabase _database;

  static String documentCacheKey(
    String slug,
    String language,
    String version,
  ) => 'salah:$slug:$language:$version';

  static String _currentVersionKey(String slug, String language) =>
      'salah:$slug:$language:current';

  Future<List<SalahCourseSummary>> courses() async => <SalahCourseSummary>[
    for (final item in jsonResults(await _remote.courses()))
      SalahCourseSummary.fromJson(item),
  ];

  Future<SalahCourseDocument> course(String slug, String language) async {
    final String version;
    try {
      version = await _activeVersion(slug);
    } on SalahCourseUnavailable {
      rethrow;
    } on Object catch (error) {
      if (!canUseUnverifiedDuaFallback(error)) rethrow;
      final cached = await _lastConfirmed(slug, language);
      if (cached == null) rethrow;
      return cached;
    }

    final cached = await _cachedDocument(slug, language, version);
    if (cached != null) {
      await _rememberVersion(slug, language, version);
      return cached;
    }

    final payload = await _remote.course(slug, language);
    final document = SalahCourseDocument.fromJson(payload);
    if (document.course.slug != slug) {
      throw const FormatException('Salah document belongs to another course');
    }
    // The course may be published again between the two requests; the
    // document names its own version, so it is cached under that one.
    final documentVersion = document.course.version;
    await _write(documentCacheKey(slug, language, documentVersion), payload);
    await _rememberVersion(slug, language, documentVersion);
    return document;
  }

  Future<String> _activeVersion(String slug) async {
    for (final summary in await courses()) {
      if (summary.slug == slug) return summary.version;
    }
    throw SalahCourseUnavailable(slug);
  }

  Future<SalahCourseDocument?> _cachedDocument(
    String slug,
    String language,
    String version,
  ) async {
    final cached = await _read(documentCacheKey(slug, language, version));
    if (cached == null) return null;
    try {
      final document = SalahCourseDocument.fromJson(cached.value);
      if (document.course.slug != slug || document.course.version != version) {
        return null;
      }
      return document;
    } on Object {
      // A malformed row is a miss; the next valid response replaces it.
      return null;
    }
  }

  Future<SalahCourseDocument?> _lastConfirmed(
    String slug,
    String language,
  ) async {
    final pointer = await _read(_currentVersionKey(slug, language));
    final value = pointer?.value;
    final version = value is Map ? value['version']?.toString() : null;
    if (version == null || version.isEmpty) return null;
    return _cachedDocument(slug, language, version);
  }

  Future<void> _rememberVersion(String slug, String language, String version) =>
      _write(_currentVersionKey(slug, language), <String, Object?>{
        'version': version,
      });

  Future<CachedValue?> _read(String key) async {
    try {
      return await _database.readCache(key);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, Object? payload) async {
    try {
      await _database.writeCache(key, payload, maxAge: _documentMaxAge);
    } on Object {
      // Caching must not turn a valid online response into a failure.
    }
  }
}
