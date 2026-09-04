import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'audio_models.dart';
import 'audio_offline_repository.dart';

class AudioRepository {
  AudioRepository({
    required ApiClient api,
    required LocalDatabase database,
    required AudioOfflineRepository offline,
    String Function()? preferredQuality,
  }) : _api = api,
       _database = database,
       _offline = offline,
       _preferredQuality = preferredQuality ?? _automaticQuality;

  final ApiClient _api;
  final LocalDatabase _database;
  final AudioOfflineRepository _offline;
  final String Function() _preferredQuality;
  final Map<String, List<Recitation>> _recitationMemory = {};
  final Map<String, SurahPlayback> _playbackMemory = {};

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
      if (!forceRefresh && cached != null) return parseReciters(cached.value);
      rethrow;
    }
  }

  Future<Recitation?> recitationFor(String reciterId) async {
    final items = await recitations(reciterId: reciterId);
    if (items.isEmpty) return null;
    final timed = items.where((item) => item.timingsAvailable).toList();
    final candidates = timed.isEmpty ? items : timed;
    final murattal = candidates.where((item) => item.style == 'murattal');
    return (murattal.isEmpty ? candidates : murattal).first;
  }

  Future<List<Recitation>> recitationsForReciters(
    Iterable<String> reciterIds,
  ) async {
    final groups = await Future.wait(
      reciterIds.toSet().map((id) => recitations(reciterId: id)),
    );
    final variants = <String, Recitation>{};
    for (final recitation in groups.expand((items) => items)) {
      final current = variants[recitation.style];
      if (current == null ||
          _recitationRank(recitation) > _recitationRank(current)) {
        variants[recitation.style] = recitation;
      }
    }
    final result = variants.values.toList(growable: false);
    result.sort(
      (left, right) =>
          _styleRank(left.style).compareTo(_styleRank(right.style)),
    );
    return result;
  }

  Future<List<Recitation>> recitations({
    String? reciterId,
    bool forceRefresh = false,
  }) async {
    final suffix = reciterId == null ? 'all' : 'reciter:$reciterId';
    final key = 'audio:recitations:madani-hafs:$suffix';
    if (!forceRefresh) {
      final memory = _recitationMemory[key];
      if (memory != null) return memory;
    }
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _recitationMemory[key] = _parseRecitations(cached!.value);
    }
    try {
      final payload = await _api.get(
        '/recitations',
        query: <String, Object?>{
          'reciter_id': ?reciterId,
          'quran_edition': 'madani-hafs',
          'page_size': 100,
        },
        public: true,
      );
      await _database.writeCache(
        key,
        payload,
        maxAge: const Duration(hours: 12),
      );
      return _recitationMemory[key] = _parseRecitations(payload);
    } on Object {
      if (cached != null) {
        return _recitationMemory[key] = _parseRecitations(cached.value);
      }
      rethrow;
    }
  }

  Future<AudioTrack?> track({
    required String reciterId,
    required int surah,
  }) async {
    final recitation = await recitationFor(reciterId);
    if (recitation == null) return null;
    final result = await playback(recitationId: recitation.id, surah: surah);
    return result.track.url.isEmpty ? null : result.track;
  }

  Future<SurahPlayback> playback({
    required String recitationId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    final offline = await _offline.activePlayback(
      recitationId: recitationId,
      surah: surah,
    );
    if (offline != null) return offline;
    final key = 'audio:playback:$recitationId:surah:$surah';
    if (!forceRefresh) {
      final memory = _playbackMemory.remove(key);
      if (memory != null) {
        _playbackMemory[key] = memory;
        return memory.withPreferredQuality(_preferredQuality());
      }
    }
    final cached = await _database.readCache(key);
    if (!forceRefresh && cached?.isFresh == true) {
      return _rememberPlayback(
        key,
        SurahPlayback.fromJson(jsonMap(cached!.value)),
      ).withPreferredQuality(_preferredQuality());
    }
    try {
      final payload = await _api.get(
        '/recitations/$recitationId/surahs/$surah',
        public: true,
      );
      await _database.writeCache(key, payload, maxAge: const Duration(days: 7));
      return _rememberPlayback(
        key,
        SurahPlayback.fromJson(jsonMap(payload)),
      ).withPreferredQuality(_preferredQuality());
    } on Object {
      if (cached != null) {
        return _rememberPlayback(
          key,
          SurahPlayback.fromJson(jsonMap(cached.value)),
        ).withPreferredQuality(_preferredQuality());
      }
      rethrow;
    }
  }

  SurahPlayback _rememberPlayback(String key, SurahPlayback value) {
    _playbackMemory.remove(key);
    _playbackMemory[key] = value;
    while (_playbackMemory.length > 3) {
      _playbackMemory.remove(_playbackMemory.keys.first);
    }
    return value;
  }
}

String _automaticQuality() => 'auto';

List<Recitation> _parseRecitations(Object? payload) {
  final items = jsonResults(payload)
      .whereType<Map>()
      .map((item) => Recitation.fromJson(Map<String, Object?>.from(item)))
      .where(
        (item) =>
            item.id.isNotEmpty &&
            item.reciter.id.isNotEmpty &&
            item.streamAllowed &&
            item.surahCount > 0,
      )
      .toList(growable: false);
  items.sort((left, right) {
    final leftRank = _recitationRank(left);
    final rightRank = _recitationRank(right);
    final rank = rightRank.compareTo(leftRank);
    if (rank != 0) return rank;
    return left.reciter.nameEn.compareTo(right.reciter.nameEn);
  });
  return items;
}

int _recitationRank(Recitation item) {
  return (item.timingsAvailable ? 10000 : 0) +
      item.surahCount * 10 +
      (item.style == 'murattal' ? 5 : 0) +
      (item.code.startsWith('qf-7-') ? 2 : 0);
}

int _styleRank(String style) => switch (style) {
  'murattal' => 0,
  'mujawwad' => 1,
  'muallim' => 2,
  _ => 3,
};
