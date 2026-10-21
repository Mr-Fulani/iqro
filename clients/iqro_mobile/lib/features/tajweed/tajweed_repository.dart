import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'tajweed_models.dart';

class TajweedRepository {
  TajweedRepository({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;

  /// Until the markup is imported every page answers 404; one answer is
  /// enough for a while, instead of a request on every page turn.
  DateTime? _missingUntil;

  /// Rule names, explanations and colours; null without tajweed on the server.
  Future<TajweedReference?> rules() => _load(
    'quran:tajweed:rules',
    '/quran/tajweed/rules',
    const Duration(days: 7),
    TajweedReference.fromJson,
  );

  /// The rules of a QF Mushaf 19 page; null until the markup is imported.
  Future<TajweedPage?> page(int number) async {
    final missingUntil = _missingUntil;
    if (missingUntil != null && DateTime.now().isBefore(missingUntil)) {
      return null;
    }
    final page = await _load(
      'quran:tajweed:page:$number',
      '/quran/tajweed/pages/$number',
      const Duration(days: 30),
      (json) => TajweedPage.fromJson(json, number),
    );
    _missingUntil = page == null
        ? DateTime.now().add(const Duration(hours: 1))
        : null;
    return page;
  }

  Future<T?> _load<T>(
    String key,
    String path,
    Duration maxAge,
    T Function(Map<String, Object?> json) parse,
  ) async {
    final cached = await _database.readCache(key);
    T? previous;
    if (cached != null) {
      try {
        previous = parse(jsonMap(cached.value));
      } on Object {
        // A corrupt or outdated entry is replaced by the API response.
      }
      if (cached.isFresh && previous != null) return previous;
    }
    try {
      final payload = await _api.get(path, public: true);
      final parsed = parse(jsonMap(payload));
      await _database.writeCache(key, payload, maxAge: maxAge);
      return parsed;
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      if (previous != null) return previous;
      rethrow;
    } on Object {
      if (previous != null) return previous;
      rethrow;
    }
  }
}
