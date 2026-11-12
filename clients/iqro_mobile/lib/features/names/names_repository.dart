import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../dua/dua_repository.dart' show canUseUnverifiedDuaFallback;
import 'names_models.dart';

/// Nothing is published yet: the section says it is being prepared.
class NamesUnavailable implements Exception {
  const NamesUnavailable(this.slug);

  final String slug;

  @override
  String toString() => 'Names collection "$slug" is not published';
}

abstract interface class NamesRemoteGateway {
  Future<Object?> collection(String slug, String language);
}

class ApiNamesRemoteGateway implements NamesRemoteGateway {
  ApiNamesRemoteGateway(this._api);

  final ApiClient _api;

  @override
  Future<Object?> collection(String slug, String language) => _api.get(
    '/names/collections/${Uri.encodeComponent(slug)}',
    query: <String, Object?>{'language': language},
    public: true,
  );
}

/// Loads the published list and keeps it for offline.
///
/// The server answers with the active version, so the network comes first;
/// without it the copy of the last answer is shown.
class NamesRepository {
  NamesRepository({
    required NamesRemoteGateway remote,
    required LocalDatabase database,
  }) : _remote = remote,
       _database = database;

  static const _documentMaxAge = Duration(days: 30);

  final NamesRemoteGateway _remote;
  final LocalDatabase _database;

  static String cacheKey(String slug, String language) =>
      'names:$slug:$language';

  Future<NamesDocument> collection(String slug, String language) async {
    final Object? payload;
    try {
      payload = await _remote.collection(slug, language);
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw NamesUnavailable(slug);
      return _cachedOr(slug, language, error);
    } on Object catch (error) {
      return _cachedOr(slug, language, error);
    }
    final document = NamesDocument.fromJson(payload);
    if (document.slug != slug) {
      throw const FormatException('Names document belongs to another list');
    }
    try {
      await _database.writeCache(
        cacheKey(slug, language),
        payload,
        maxAge: _documentMaxAge,
      );
    } on Object {
      // Caching must not turn a valid online response into a failure.
    }
    return document;
  }

  Future<NamesDocument> _cachedOr(
    String slug,
    String language,
    Object error,
  ) async {
    if (canUseUnverifiedDuaFallback(error)) {
      try {
        final cached = await _database.readCache(cacheKey(slug, language));
        if (cached != null) return NamesDocument.fromJson(cached.value);
      } on Object {
        // A malformed row is a miss; the next valid response replaces it.
      }
    }
    // ignore: only_throw_errors
    throw error;
  }
}
