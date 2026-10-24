import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/quran/quran_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = 'https://iqro.forum/api/v1';
const _catalogKey = 'mushaf-renditions:$_origin';
const _catalogPath = '/quran/foundation/mushafs';
final _tajweed = MushafIdentity.defaultEdition;

void main() {
  test('a fresh catalog cache is served without a network request', () async {
    final api = _Api();
    final cache = _Cache()
      ..entries[_catalogKey] = _cached([_foundation('Cached Tajweed')]);
    final container = await _container(api, cache);

    final catalog = await container.read(mushafRenditionsProvider.future);
    expect(catalog.single.nameFor('en'), 'Cached Tajweed');
    expect(
      container.read(availableMushafRenditionsProvider).single.identity,
      _tajweed,
    );
    expect(container.read(selectedMushafIdentityProvider), _tajweed);
    expect(api.calls, isEmpty);

    // Opening the picker re-reads the catalog; a fresh copy still costs no
    // request.
    container.invalidate(mushafRenditionsProvider);
    await container.read(mushafRenditionsProvider.future);
    expect(api.calls, isEmpty);
  });

  test(
    'an expired catalog cache stays on screen while the refresh runs',
    () async {
      final api = _Api();
      final cache = _Cache()
        ..entries[_catalogKey] = _cached([
          _foundation('Cached Tajweed'),
        ], fresh: false);
      final container = await _container(api, cache);

      // Watching the catalog starts the refresh after the cache is read.
      container.listen(availableMushafRenditionsProvider, (_, _) {});
      await container.read(cachedMushafRenditionsProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(api.calls[_catalogPath], 1);
      expect(api.catalog.isCompleted, isFalse);
      // The expired copy is drawn, not an empty catalog.
      expect(
        container.read(availableMushafRenditionsProvider).single.nameFor('en'),
        'Cached Tajweed',
      );
      final seen = <List<NativeMushafEdition>>[];
      container.listen(
        availableMushafRenditionsProvider,
        (_, next) => seen.add(next),
      );
      final repository = container.read(mushafRepositoryProvider(_tajweed));

      api.catalog.complete([_foundation('Fresh Tajweed')]);
      await container.read(mushafRenditionsProvider.future);
      expect(
        container.read(availableMushafRenditionsProvider).single.nameFor('en'),
        'Fresh Tajweed',
      );
      expect(seen, isNotEmpty);
      expect(seen.every((catalog) => catalog.isNotEmpty), isTrue);
      expect(cache.entries[_catalogKey]!.isFresh, isTrue);
      // The source version did not change, so open pages keep their
      // repository instead of reloading.
      expect(
        identical(
          container.read(mushafRepositoryProvider(_tajweed)),
          repository,
        ),
        isTrue,
      );
    },
  );

  test('a changed source checksum rebuilds the page repository', () async {
    final api = _Api();
    final cache = _Cache()
      ..entries[_catalogKey] = _cached([
        _foundation('Cached Tajweed'),
      ], fresh: false);
    final container = await _container(api, cache);
    container.listen(availableMushafRenditionsProvider, (_, _) {});
    await container.read(cachedMushafRenditionsProvider.future);
    expect(
      container.read(mushafRepositoryProvider(_tajweed)).foundationVersion,
      'a' * 64,
    );

    api.catalog.complete([_foundation('Fresh Tajweed', checksum: 'b')]);
    await container.read(mushafRenditionsProvider.future);
    expect(
      container.read(mushafRepositoryProvider(_tajweed)).foundationVersion,
      'b' * 64,
    );
  });

  testWidgets(
    'the Quran tab draws the cached Mushaf without requesting the catalog',
    (tester) async {
      final api = _Api();
      final cache = _Cache()
        ..entries[_catalogKey] = _cached([_foundation('Cached Tajweed')]);
      await _pumpQuran(tester, api, cache);
      final l10n = _l10n(tester);

      expect(find.text('Cached Tajweed'), findsOneWidget);
      expect(find.text(l10n.mushafCatalogEmpty), findsNothing);
      expect(api.calls, isEmpty);

      await tester.tap(find.text(l10n.selectedMushaf));
      await _settle(tester);
      expect(find.text(l10n.chooseMushaf), findsOneWidget);
      expect(find.text('Cached Tajweed'), findsWidgets);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'the Quran tab keeps the expired Mushaf drawn while the catalog refreshes',
    (tester) async {
      final api = _Api();
      final cache = _Cache()
        ..entries[_catalogKey] = _cached([
          _foundation('Cached Tajweed'),
        ], fresh: false);
      await _pumpQuran(tester, api, cache);
      final l10n = _l10n(tester);

      expect(api.calls[_catalogPath], 1);
      expect(find.text('Cached Tajweed'), findsOneWidget);
      expect(find.text(l10n.mushafCatalogEmpty), findsNothing);

      api.catalog.complete([_foundation('Fresh Tajweed')]);
      await _settle(tester);
      expect(find.text('Fresh Tajweed'), findsOneWidget);
      expect(find.text(l10n.mushafCatalogEmpty), findsNothing);
      expect(api.calls[_catalogPath], 1);
    },
  );

  testWidgets(
    'the first frame shows the edition from the catalog read at startup',
    (tester) async {
      final api = _Api();
      final cache = _Cache()
        ..entries[_catalogKey] = _cached([_foundation('Cached Tajweed')]);
      // AppDependencies reads the catalog before the app's first frame.
      final startup = await QuranRepository(
        api: api,
        database: cache,
      ).cachedMushafRenditions();
      // Startup queries hold the database, so the tab's own reads wait.
      final busy = cache.busy = Completer<void>();
      await _pumpQuran(
        tester,
        api,
        cache,
        settle: false,
        overrides: [
          cachedMushafRenditionsProvider.overrideWith((ref) => startup),
        ],
      );
      final l10n = _l10n(tester);

      expect(find.text('Cached Tajweed'), findsOneWidget);
      expect(find.text(l10n.mushafCatalogEmpty), findsNothing);

      busy.complete();
      await _settle(tester);
      expect(find.text('Cached Tajweed'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );
}

Map<String, Object?> _foundation(String name, {String checksum = 'a'}) => {
  'source_id': _tajweed.foundationId,
  'name': name,
  'pages_count': 604,
  'lines_per_page': 15,
  'qirat_name': 'Hafs',
  'mapping_mode': 'reference',
  'rendering': {'version': 2, 'available': true, 'mode': 'page-font'},
  'source_checksum_sha256': checksum * 64,
};

CachedValue _cached(List<Object?> payload, {bool fresh = true}) => CachedValue(
  value: payload,
  updatedAt: DateTime(2026, 10, 23),
  expiresAt: DateTime.now().toUtc().add(Duration(hours: fresh ? 1 : -1)),
);

Future<ProviderContainer> _container(_Api api, _Cache cache) async {
  final container = ProviderContainer(
    overrides: [
      ..._overrides(api, cache),
      preferencesStoreProvider.overrideWithValue(await _store()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<PreferencesStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  return PreferencesStore(await SharedPreferences.getInstance());
}

List<Override> _overrides(_Api api, _Cache cache) => [
  appConfigProvider.overrideWithValue(
    const AppConfig(
      apiBaseUrl: 'https://iqro.forum',
      fallbackDownloadUrl: 'https://iqro.forum',
      environment: 'production',
    ),
  ),
  planRepositoryProvider.overrideWithValue(_Plan()),
  localDatabaseProvider.overrideWithValue(cache),
  quranRepositoryProvider.overrideWithValue(
    QuranRepository(api: api, database: cache),
  ),
];

// Page artwork never arrives: the card's layout is defined by metadata.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(QuranScreen)));

Future<void> _pumpQuran(
  WidgetTester tester,
  _Api api,
  _Cache cache, {
  bool settle = true,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = const Size(1080, 2340);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._overrides(api, cache),
        preferencesStoreProvider.overrideWithValue(await _store()),
        // Miniatures draw through their own page repository; the catalog
        // under test comes from the real one above.
        mushafRepositoryProvider.overrideWith(
          (ref, identity) => _Pages(identity),
        ),
        activeAccountScopeKeyProvider.overrideWithValue(null),
        audioControllerProvider.overrideWith((ref) => _IdleAudio()),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(surahs: [], fromCache: false),
        ),
        quranJuzProvider.overrideWith((ref) async => const []),
        mushafDownloadProvider.overrideWithValue(
          const MushafDownloadSnapshot.empty(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const QuranScreen(),
      ),
    ),
  );
  if (settle) await _settle(tester);
}

class _Api implements ApiClient {
  @override
  final Dio dio = Dio(BaseOptions(baseUrl: _origin));
  final calls = <String, int>{};
  final catalog = Completer<List<Object?>>();

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) {
    calls[path] = (calls[path] ?? 0) + 1;
    return switch (path) {
      _catalogPath => catalog.future,
      '/quran/mushaf-renditions' => Future.value(const <Object?>[]),
      _ => Future.error(StateError('unexpected request $path')),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  final entries = <String, CachedValue>{};
  Completer<void>? busy;

  @override
  Future<CachedValue?> readCache(String key) async {
    await busy?.future;
    return entries[key];
  }

  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final now = DateTime.now().toUtc();
    entries[key] = CachedValue(
      value: value,
      updatedAt: now,
      expiresAt: now.add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plan implements PlanRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pages implements QuranRepository {
  _Pages(this.mushaf);

  @override
  final MushafIdentity mushaf;
  final _asset = Completer<File>();

  @override
  QuranRepository forMushaf(MushafIdentity identity) => _Pages(identity);

  @override
  QuranRepository withFoundationVersion(String version) => this;

  @override
  Future<MushafPageData> mushafPage(int page, {bool forceRefresh = false}) =>
      Future.value(
        MushafPageData(
          number: page,
          editionCode: mushaf.code,
          contentVersion: 'test',
          checksumSha256: '',
          imageWidth: 900,
          imageHeight: 1380,
          assets: const <MushafAsset>[
            MushafAsset(
              url: 'https://example.test/page.webp',
              width: 2700,
              sha256: '',
            ),
          ],
          regions: const <MushafAyahRegion>[],
        ),
      );

  @override
  Future<bool> refreshMushafPageResolution(
    MushafPageData page, {
    required int minimumWidth,
  }) async => false;

  @override
  Future<File> cachedMushafPageAsset(MushafPageData page, MushafAsset asset) =>
      _asset.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleAudio extends StateNotifier<IqroAudioState>
    implements AudioController {
  _IdleAudio() : super(const IqroAudioState());

  @override
  IqroAudioPresentation listeningPresentation(IqroAudioState current) =>
      iqroAudioPresentation(current);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
