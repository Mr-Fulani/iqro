import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'audio_models.dart';

class AudioRepository {
  AudioRepository({required ApiClient api, required LocalDatabase database})
    : _api = api,
      _database = database;

  final ApiClient _api;
  final LocalDatabase _database;

  Future<List<Reciter>> reciters({bool forceRefresh = false}) async {
    const key = 'audio:reciters';
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return parseReciters(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/reciters',
        query: const <String, Object?>{'page_size': 100},
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(hours: 12),
      );
      return parseReciters(payload);
    } on Object {
      if (cached != null) return parseReciters(cached.value);
      rethrow;
    }
  }

  Future<Recitation?> recitationFor(String reciterId) async {
    final payload = await _api.get(
      '/recitations',
      query: <String, Object?>{
        'reciter_id': reciterId,
        'quran_edition': 'madani-hafs',
        'style': 'murattal',
        'page_size': 10,
      },
      public: true,
    );
    final rows = jsonResults(payload).whereType<Map>();
    if (rows.isEmpty) return null;
    return Recitation.fromJson(Map<String, Object?>.from(rows.first));
  }

  Future<AudioTrack?> track({
    required String reciterId,
    required int surah,
  }) async {
    final recitation = await recitationFor(reciterId);
    if (recitation == null) return null;
    final payload = await _api.get(
      '/recitations/${recitation.id}/surahs/$surah',
      public: true,
    );
    final track = AudioTrack.fromPlayback(jsonMap(payload));
    return track.url.isEmpty ? null : track;
  }
}
