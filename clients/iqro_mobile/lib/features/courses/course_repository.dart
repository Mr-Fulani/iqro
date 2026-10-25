import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../dua/dua_repository.dart' show canUseUnverifiedDuaFallback;
import 'course_models.dart';

abstract interface class CourseRemoteGateway {
  /// `GET /courses?language=`.
  Future<Object?> courses(String language);

  /// `GET /courses/{slug}?language=`.
  Future<Object?> course(String slug, String language);
}

class ApiCourseGateway implements CourseRemoteGateway {
  ApiCourseGateway(this._api);

  final ApiClient _api;

  @override
  Future<Object?> courses(String language) => _api.get(
    '/courses',
    query: <String, Object?>{'language': language},
    public: true,
  );

  @override
  Future<Object?> course(String slug, String language) => _api.get(
    '/courses/${Uri.encodeComponent(slug)}',
    query: <String, Object?>{'language': language},
    public: true,
  );
}

/// Course list and documents, kept on the device for reading offline.
///
/// Online the list says which courses are visible and which version of each
/// is current: a new version means a new document, and a course missing from
/// the list is hidden. A document is stored under its version and read from
/// there while the list names that version. Offline the last list is shown,
/// limited to the courses whose document is stored.
class CourseRepository {
  CourseRepository({
    required CourseRemoteGateway remote,
    required LocalDatabase database,
    Future<void> Function(Iterable<LessonMedia> media)? keepMedia,
  }) : _remote = remote,
       _database = database,
       _keepMedia = keepMedia;

  // Expired entries stay usable and are removed long after expiry.
  static const _maxAge = Duration(days: 180);

  final CourseRemoteGateway _remote;
  final LocalDatabase _database;

  /// Keeps the pictures of the lessons for offline with the document.
  final Future<void> Function(Iterable<LessonMedia> media)? _keepMedia;

  static String documentCacheKey(
    String slug,
    String language,
    String version,
  ) => 'courses.document.$slug.$language.$version';

  /// The last list received in [language].
  static String catalogCacheKey(String language) => 'courses.catalog.$language';

  /// `{"<course>": "<version>"}`: the latest document stored per course.
  static String savedCacheKey(String language) => 'courses.saved.$language';

  Future<CourseCatalog> catalog(String language) async {
    final Object? payload;
    try {
      payload = await _remote.courses(language);
    } on Object catch (error) {
      // A server without the section has no courses to show.
      if (error is ApiException && error.statusCode == 404) {
        return const CourseCatalog(courses: []);
      }
      if (!canUseUnverifiedDuaFallback(error)) rethrow;
      return _offlineCatalog(language);
    }
    final courses = parseCourseList(payload);
    await _write(catalogCacheKey(language), payload);
    return CourseCatalog(
      courses: courses,
      builtIn: BuiltInCourseCovers.fromList(payload),
    );
  }

  /// The document of [course] as the catalog names it.
  Future<CourseDocument> document(CourseSummary course, String language) async {
    final cached = await _cachedDocument(course.slug, language, course.version);
    if (cached != null) {
      // After a rollback the older stored version is current again.
      await _rememberSaved(language, course.slug, course.version);
      // Pictures that did not arrive with the document are fetched now.
      _keepPictures(cached);
      return cached;
    }
    final Object? payload;
    try {
      payload = await _remote.course(course.slug, language);
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw CourseUnavailable(course.slug);
      rethrow;
    }
    final document = CourseDocument.fromJson(payload);
    if (document.course.slug != course.slug ||
        document.course.language != language) {
      throw const FormatException('The document belongs to another course');
    }
    // A version published between the two requests names itself.
    final version = document.course.version;
    await _write(documentCacheKey(course.slug, language, version), payload);
    await _rememberSaved(language, course.slug, version);
    _keepPictures(document);
    return document;
  }

  /// In the background: the course opens without waiting for its pictures.
  void _keepPictures(CourseDocument document) {
    final keep = _keepMedia;
    if (keep == null) return;
    unawaited(
      Future<void>.sync(
        () => keep(document.lessons.expand((lesson) => lesson.media)),
      ).catchError((Object _) {}),
    );
  }

  Future<CourseCatalog> _offlineCatalog(String language) async {
    final saved = await _saved(language);
    final listed = await _read(catalogCacheKey(language));
    var courses = const <CourseSummary>[];
    try {
      if (listed != null) courses = parseCourseList(listed.value);
    } on Object {
      // A damaged list shows nothing rather than failing the section.
    }
    final available = <CourseSummary>[];
    for (final course in courses) {
      final version = saved[course.slug];
      if (version == null) continue;
      // Cache maintenance may have removed a document unused for long.
      final key = documentCacheKey(course.slug, language, version);
      if (await _read(key) == null) continue;
      available.add(course.withVersion(version));
    }
    return CourseCatalog(
      courses: available,
      // The cover pictures themselves stay in the image cache.
      builtIn: BuiltInCourseCovers.fromList(listed?.value),
      offline: true,
    );
  }

  Future<CourseDocument?> _cachedDocument(
    String slug,
    String language,
    String version,
  ) async {
    final cached = await _read(documentCacheKey(slug, language, version));
    if (cached == null) return null;
    try {
      final document = CourseDocument.fromJson(cached.value);
      if (document.course.slug != slug || document.course.version != version) {
        return null;
      }
      return document;
    } on Object {
      // A malformed row is a miss; the next valid response replaces it.
      return null;
    }
  }

  Future<Map<String, String>> _saved(String language) async {
    final value = (await _read(savedCacheKey(language)))?.value;
    if (value is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in value.entries)
        if (key is String && value is String) key: value,
    };
  }

  Future<void> _rememberSaved(
    String language,
    String slug,
    String version,
  ) async {
    final saved = await _saved(language);
    if (saved[slug] == version) return;
    await _write(savedCacheKey(language), <String, Object?>{
      ...saved,
      slug: version,
    });
  }

  Future<CachedValue?> _read(String key) async {
    try {
      return await _database.readCache(key);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, Object? payload) async {
    try {
      await _database.writeCache(key, payload, maxAge: _maxAge);
    } on Object {
      // Caching must not turn a valid online response into a failure.
    }
  }
}
