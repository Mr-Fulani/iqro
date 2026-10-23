import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import '../dua/dua_repository.dart' show canUseUnverifiedDuaFallback;
import 'tajweed_course_models.dart';
import 'tajweed_practice.dart';

abstract interface class TajweedCourseRemoteGateway {
  Future<Object?> courses();

  Future<Object?> course(String slug, String language);

  Future<Object?> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  });

  /// `PUT /me/tajweed/progress/<course>`: the server merges and answers
  /// with the result.
  Future<Object?> saveProgress(
    String course,
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  });

  /// `GET /tajweed/courses/<slug>/practice`: tasks on the targets of
  /// [lessons], the [review] keys first.
  Future<Object?> practice(
    String slug, {
    required List<String> lessons,
    required int count,
    required int seed,
    required List<String> review,
  });

  /// `POST /me/tajweed/practice-sessions`: the answer is the practice state
  /// after the session.
  Future<Object?> savePracticeSession(
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  });

  /// `GET /me/tajweed/practice/<course>`.
  Future<Object?> practiceState(
    String course, {
    AccountScopeSnapshot? accountScope,
  });
}

class ApiTajweedCourseGateway implements TajweedCourseRemoteGateway {
  ApiTajweedCourseGateway(this._api);

  final ApiClient _api;

  @override
  Future<Object?> courses() => _api.get('/tajweed/courses', public: true);

  @override
  Future<Object?> course(String slug, String language) => _api.get(
    '/tajweed/courses/${Uri.encodeComponent(slug)}',
    query: <String, Object?>{'language': language},
    public: true,
  );

  @override
  Future<Object?> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) => _api.get(
    '/tajweed/courses/${Uri.encodeComponent(slug)}/lessons/'
    '${Uri.encodeComponent(lesson)}/examples',
    query: <String, Object?>{'offset': offset, 'limit': limit},
    public: true,
  );

  @override
  Future<Object?> saveProgress(
    String course,
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  }) => _api.put(
    '/me/tajweed/progress/${Uri.encodeComponent(course)}',
    data: body,
    accountScope: accountScope,
  );

  @override
  Future<Object?> practice(
    String slug, {
    required List<String> lessons,
    required int count,
    required int seed,
    required List<String> review,
  }) => _api.get(
    '/tajweed/courses/${Uri.encodeComponent(slug)}/practice',
    query: <String, Object?>{
      'lessons': lessons.join(','),
      'count': count,
      'seed': seed,
      if (review.isNotEmpty) 'review': review.join(','),
    },
    public: true,
  );

  @override
  Future<Object?> savePracticeSession(
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/tajweed/practice-sessions',
    data: body,
    accountScope: accountScope,
  );

  @override
  Future<Object?> practiceState(
    String course, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/tajweed/practice/${Uri.encodeComponent(course)}',
    accountScope: accountScope,
  );
}

/// Loads the compiled course document and keeps it in the local cache, the
/// same way as the Salah course: the cache key carries the published
/// version, and the cached copy is trusted after the course list confirms
/// it. Without a network the last confirmed version is used.
class TajweedCourseRepository {
  TajweedCourseRepository({
    required TajweedCourseRemoteGateway remote,
    required LocalDatabase database,
  }) : _remote = remote,
       _database = database;

  static const _documentMaxAge = Duration(days: 30);

  final TajweedCourseRemoteGateway _remote;
  final LocalDatabase _database;

  static String documentCacheKey(
    String slug,
    String language,
    String version,
  ) => 'tajweed-course:$slug:$language:$version';

  static String _currentVersionKey(String slug, String language) =>
      'tajweed-course:$slug:$language:current';

  Future<List<TajweedCourseSummary>> courses() async => [
    for (final item in jsonResults(await _remote.courses()))
      TajweedCourseSummary.fromJson(item),
  ];

  Future<TajweedCourseDocument> course(String slug, String language) async {
    final String version;
    try {
      version = await _activeVersion(slug);
    } on TajweedCourseUnavailable {
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
    final document = TajweedCourseDocument.fromJson(payload);
    if (document.course.slug != slug) {
      throw const FormatException('Tajweed document belongs to another course');
    }
    // A new version may be published between the two requests; the document
    // names its own version, so it is cached under that one.
    final documentVersion = document.course.version;
    await _write(documentCacheKey(slug, language, documentVersion), payload);
    await _rememberVersion(slug, language, documentVersion);
    return document;
  }

  /// A page of a lesson's examples. They change with the markup, so they are
  /// not kept.
  Future<TajweedExamplesPage> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) async => TajweedExamplesPage.fromJson(
    await _remote.examples(slug, lesson, offset: offset, limit: limit),
  );

  /// Tasks of a practice session on the targets of [lessons]; [review] keys
  /// come first. The same [seed] gives the same tasks.
  Future<List<TajweedPracticeTask>> practice(
    String slug, {
    required List<String> lessons,
    required int seed,
    List<String> review = const [],
    int count = tajweedPracticeTasks,
  }) async => parseTajweedPracticeTasks(
    await _remote.practice(
      slug,
      lessons: lessons,
      count: count,
      seed: seed,
      review: review,
    ),
  );

  Future<String> _activeVersion(String slug) async {
    for (final summary in await courses()) {
      if (summary.slug == slug) return summary.version;
    }
    throw TajweedCourseUnavailable(slug);
  }

  Future<TajweedCourseDocument?> _cachedDocument(
    String slug,
    String language,
    String version,
  ) async {
    final cached = await _read(documentCacheKey(slug, language, version));
    if (cached == null) return null;
    try {
      final document = TajweedCourseDocument.fromJson(cached.value);
      if (document.course.slug != slug || document.course.version != version) {
        return null;
      }
      return document;
    } on Object {
      // A malformed row is a miss; the next valid response replaces it.
      return null;
    }
  }

  Future<TajweedCourseDocument?> _lastConfirmed(
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
