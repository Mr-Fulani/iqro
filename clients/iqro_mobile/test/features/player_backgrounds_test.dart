import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/audio/player_backgrounds.dart';

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

const _payload = <Object?>[
  <String, Object?>{
    'id': 'bg-1',
    'title_ar': 'الجبال',
    'title_en': 'Mountains',
    'title_ru': 'Горы',
    'title_tr': '',
    'image_url': 'https://media.iqro.forum/audio/player-backgrounds/a.webp',
    'sort_order': 10,
  },
  <String, Object?>{
    'id': 'bg-2',
    'title_en': 'Relative',
    'image_url': '/media/audio/player-backgrounds/b.jpg',
  },
  <String, Object?>{'id': '', 'image_url': 'https://media.iqro.forum/x.webp'},
  <String, Object?>{'id': 'no-image', 'image_url': ''},
  'not-an-object',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled backgrounds are shipped assets with localized titles', () {
    final ids = bundledPlayerBackgrounds.map((item) => item.id).toSet();
    expect(ids, hasLength(bundledPlayerBackgrounds.length));
    expect(ids, contains(defaultPlayerBackgroundId));
    expect(bundledPlayerBackgrounds.first.id, classicPlayerBackgroundId);
    expect(bundledPlayerBackgrounds.first.hasImage, isFalse);
    for (final background in bundledPlayerBackgrounds) {
      for (final locale in const <String>['ru', 'en', 'tr', 'ar']) {
        expect(background.titles[locale], isNotEmpty);
      }
      final asset = background.assetPath;
      if (asset == null) continue;
      final file = File(asset);
      expect(file.existsSync(), isTrue, reason: asset);
      // Keep the APK small and decoding cheap.
      expect(file.lengthSync(), lessThan(120 * 1024), reason: asset);
      final video = background.videoAssetPath;
      if (video == null) continue;
      expect(File(video).existsSync(), isTrue, reason: video);
      expect(File(video).lengthSync(), lessThan(200 * 1024), reason: video);
    }
  });

  test('parses admin backgrounds and skips malformed rows', () {
    final parsed = parsePlayerBackgrounds(
      _payload,
      apiBaseUrl: _config.apiBaseUrl,
    );

    expect(parsed.map((item) => item.id), <String>[
      'remote:bg-1',
      'remote:bg-2',
    ]);
    expect(
      parsed.first.imageUrl,
      'https://media.iqro.forum/audio/player-backgrounds/a.webp',
    );
    expect(
      parsed.last.imageUrl,
      'https://iqro.forum/media/audio/player-backgrounds/b.jpg',
    );
    // An empty Turkish title falls back to English.
    expect(parsed.first.titleFor('tr'), 'Mountains');
    expect(parsed.first.titleFor('ru'), 'Горы');
  });

  test('an unknown or removed background falls back to the default', () {
    final resolved = resolvePlayerBackground(
      'remote:deleted',
      bundledPlayerBackgrounds,
    );
    expect(resolved.id, defaultPlayerBackgroundId);
  });

  test('provider merges cached admin backgrounds after bundled ones', () async {
    final api = _Api()..response = _payload;
    final cache = _Cache();
    final container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api),
        localDatabaseProvider.overrideWithValue(cache),
        appConfigProvider.overrideWithValue(_config),
      ],
    );
    addTearDown(container.dispose);

    final items = await container.read(playerBackgroundsProvider.future);
    expect(
      items.take(bundledPlayerBackgrounds.length),
      bundledPlayerBackgrounds,
    );
    expect(items.skip(bundledPlayerBackgrounds.length).map((item) => item.id), [
      'remote:bg-1',
      'remote:bg-2',
    ]);
    expect(api.paths, <String>['/player-backgrounds']);

    // A fresh cache serves the list without another request.
    container.invalidate(playerBackgroundsProvider);
    await container.read(playerBackgroundsProvider.future);
    expect(api.paths, hasLength(1));
  });

  test('provider stays usable offline with bundled backgrounds only', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          _Api()..error = StateError('offline'),
        ),
        localDatabaseProvider.overrideWithValue(_Cache()),
        appConfigProvider.overrideWithValue(_config),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(playerBackgroundsProvider.future),
      bundledPlayerBackgrounds,
    );
  });

  test('stale cache is used when the refresh fails', () async {
    final cache = _Cache()
      ..values['audio:player-backgrounds:v1'] = CachedValue(
        value: _payload,
        updatedAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2026),
      );
    final repository = PlayerBackgroundRepository(
      api: _Api()..error = StateError('offline'),
      database: cache,
      apiBaseUrl: _config.apiBaseUrl,
    );

    expect((await repository.remote()).map((item) => item.id), [
      'remote:bg-1',
      'remote:bg-2',
    ]);
  });
}

class _Api implements ApiClient {
  Object? response;
  Object? error;
  final paths = <String>[];

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    expect(public, isTrue);
    paths.add(path);
    if (error != null) throw error!;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalDatabase {
  final values = <String, CachedValue>{};

  @override
  Future<CachedValue?> readCache(String key) async => values[key];

  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    values[key] = CachedValue(
      value: value,
      updatedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
