import '../../core/network/api_client.dart';
import '../../core/network/public_asset_uri.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/utils/json_helpers.dart';

const classicPlayerBackgroundId = 'bundled:classic';

/// A still image, or a silent looping video over its poster, behind the
/// full-screen player. Bundled entries work offline; admin entries come from
/// `/player-backgrounds` and are decoded downscaled.
class PlayerBackground {
  const PlayerBackground({
    required this.id,
    required this.titles,
    this.assetPath,
    this.imageUrl,
    this.videoAssetPath,
    this.videoUrl,
    this.showEqualizer = true,
  });

  final String id;
  final Map<String, String> titles;
  final String? assetPath;
  final String? imageUrl;

  /// Plays over the image, which stays as the poster and the picker tile.
  final String? videoAssetPath;

  /// An admin video, downloaded once and then played from the cache.
  final String? videoUrl;

  bool get hasVideo => videoAssetPath != null || videoUrl != null;

  /// Whether the sound bars sway over it while the controls are hidden; set
  /// per background in the admin.
  final bool showEqualizer;

  bool get hasImage => assetPath != null || imageUrl != null;

  String titleFor(String locale) {
    for (final code in <String>[locale, 'en', 'ru', 'ar']) {
      final title = titles[code]?.trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return '';
  }
}

const bundledPlayerBackgrounds = <PlayerBackground>[
  PlayerBackground(
    id: classicPlayerBackgroundId,
    titles: <String, String>{
      'ru': 'Классический',
      'en': 'Classic',
      'tr': 'Klasik',
      'ar': 'كلاسيكي',
    },
  ),
  PlayerBackground(
    id: defaultPlayerBackgroundId,
    assetPath: 'assets/player_backgrounds/desert-night.webp',
    titles: <String, String>{
      'ru': 'Ночная пустыня',
      'en': 'Desert night',
      'tr': 'Çöl gecesi',
      'ar': 'ليل الصحراء',
    },
  ),
  PlayerBackground(
    id: 'bundled:sea-dawn',
    assetPath: 'assets/player_backgrounds/sea-dawn.webp',
    titles: <String, String>{
      'ru': 'Море на рассвете',
      'en': 'Sea at dawn',
      'tr': 'Şafakta deniz',
      'ar': 'البحر عند الفجر',
    },
  ),
  PlayerBackground(
    id: 'bundled:palm-oasis',
    assetPath: 'assets/player_backgrounds/palm-oasis.webp',
    titles: <String, String>{
      'ru': 'Оазис',
      'en': 'Oasis',
      'tr': 'Vaha',
      'ar': 'الواحة',
    },
  ),
  PlayerBackground(
    id: 'bundled:geometric',
    assetPath: 'assets/player_backgrounds/geometric.webp',
    titles: <String, String>{
      'ru': 'Орнамент',
      'en': 'Ornament',
      'tr': 'Süsleme',
      'ar': 'زخرفة',
    },
  ),
  PlayerBackground(
    id: 'bundled:reciter-video',
    assetPath: 'assets/player_backgrounds/reciter-hood.webp',
    videoAssetPath: 'assets/player_backgrounds/reciter-hood.mp4',
    titles: <String, String>{
      'ru': 'Чтец',
      'en': 'Reciter',
      'tr': 'Kâri',
      'ar': 'القارئ',
    },
  ),
];

List<PlayerBackground> parsePlayerBackgrounds(
  Object? payload, {
  required String apiBaseUrl,
}) {
  final base = Uri.parse(apiBaseUrl);
  final result = <PlayerBackground>[];
  for (final item in jsonResults(payload)) {
    if (item is! Map) continue;
    final json = jsonMap(item);
    final id = json['id']?.toString().trim() ?? '';
    final url = json['image_url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (id.isEmpty || uri == null || url.isEmpty) continue;
    final video = json['video_url']?.toString().trim() ?? '';
    final videoUri = video.isEmpty ? null : Uri.tryParse(video);
    result.add(
      PlayerBackground(
        id: 'remote:$id',
        imageUrl: uri.hasScheme
            ? url
            : resolvePublicAssetUri(url, base).toString(),
        videoUrl: videoUri == null
            ? null
            : videoUri.hasScheme
            ? video
            : resolvePublicAssetUri(video, base).toString(),
        // Rows cached before the admin switch existed keep the bars.
        showEqualizer: json['show_equalizer'] != false,
        titles: <String, String>{
          for (final code in const <String>['ru', 'en', 'tr', 'ar'])
            if (json['title_$code'] != null) code: '${json['title_$code']}',
        },
      ),
    );
  }
  return result;
}

PlayerBackground resolvePlayerBackground(
  String id,
  List<PlayerBackground> available,
) {
  for (final background in available) {
    if (background.id == id) return background;
  }
  // A removed admin background falls back to the bundled default.
  return bundledPlayerBackgrounds.firstWhere(
    (item) => item.id == defaultPlayerBackgroundId,
  );
}

class PlayerBackgroundRepository {
  PlayerBackgroundRepository({
    required ApiClient api,
    required LocalDatabase database,
    required String apiBaseUrl,
  }) : _api = api,
       _database = database,
       _apiBaseUrl = apiBaseUrl;

  final ApiClient _api;
  final LocalDatabase _database;
  final String _apiBaseUrl;
  // v2: rows carry video_url; a v1 copy would hide admin videos for 12 hours.
  static const _cacheKey = 'audio:player-backgrounds:v2';

  Future<List<PlayerBackground>> remote() async {
    final cached = await _database.readCache(_cacheKey);
    if (cached?.isFresh == true) {
      return parsePlayerBackgrounds(cached!.value, apiBaseUrl: _apiBaseUrl);
    }
    try {
      final payload = await _api.get('/player-backgrounds', public: true);
      await _database.writeCache(
        _cacheKey,
        payload,
        maxAge: const Duration(hours: 12),
      );
      return parsePlayerBackgrounds(payload, apiBaseUrl: _apiBaseUrl);
    } on Object {
      if (cached != null) {
        return parsePlayerBackgrounds(cached.value, apiBaseUrl: _apiBaseUrl);
      }
      rethrow;
    }
  }
}
