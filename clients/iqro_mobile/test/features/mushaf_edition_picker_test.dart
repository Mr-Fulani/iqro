import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition_picker.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/quran/quran_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

NativeMushafEdition _edition(int id, String name) => NativeMushafEdition(
  identity: MushafIdentity.fromPreference('native:qf-$id'),
  names: {'en': name},
  stagingOnly: false,
);

final _hafs = _edition(5, 'KFGQPC HAFS');
final _tajweed = _edition(19, 'QCF V4 Tajweed');
final _v2 = _edition(1, 'QCF V2');

void main() {
  test(
    'readers who never chose get QCF V4 Tajweed; a saved choice is kept',
    () async {
      Future<MushafIdentity> resolve(
        String? saved,
        List<NativeMushafEdition> catalog,
      ) async {
        final store = await _store(saved);
        final container = ProviderContainer(
          overrides: _overrides(store, _Repository(), catalog),
        );
        addTearDown(container.dispose);
        await container.read(mushafRenditionsProvider.future);
        return container.read(selectedMushafIdentityProvider);
      }

      final catalog = [_hafs, _tajweed, _v2];
      expect(await resolve(null, catalog), _tajweed.identity);
      expect(await resolve(_v2.identity.preference, catalog), _v2.identity);
      expect(await resolve(_hafs.identity.preference, catalog), _hafs.identity);
      // Without Tajweed in the catalog the previous default still applies.
      expect(await resolve(null, [_hafs, _v2]), _hafs.identity);
    },
  );

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'dark=$dark scale=$scale the selector expands into page miniatures',
        (tester) async {
          final repository = _Repository();
          await _pumpQuran(tester, repository, dark: dark, scale: scale);
          final l10n = _l10n(tester);

          // The field itself shows the default edition's page.
          expect(find.text('QCF V4 Tajweed'), findsOneWidget);
          expect(find.byType(MushafEditionThumbnail), findsOneWidget);

          await tester.tap(find.text(l10n.selectedMushaf));
          await _settle(tester);
          expect(find.text(l10n.chooseMushaf), findsOneWidget);
          for (final edition in [_hafs, _tajweed, _v2]) {
            final tile = find.byKey(
              ValueKey('mushaf-edition-${edition.identity.code}'),
            );
            await tester.scrollUntilVisible(tile, 200, scrollable: _sheet);
            expect(
              find.descendant(
                of: tile,
                matching: find.byType(MushafEditionThumbnail),
              ),
              findsOneWidget,
            );
          }
          // Each miniature is that edition's own last page.
          expect(
            repository.requested,
            containsAll(<String>['qf-5:604', 'qf-19:604', 'qf-1:604']),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'dark=$dark scale=$scale preview enlarges a page and makes it primary',
        (tester) async {
          final store = await _store(null);
          await _pumpQuran(
            tester,
            _Repository(),
            store: store,
            dark: dark,
            scale: scale,
          );
          final l10n = _l10n(tester);
          await tester.tap(find.text(l10n.selectedMushaf));
          await _settle(tester);

          final tile = find.byKey(const ValueKey('mushaf-edition-qf-1'));
          await tester.scrollUntilVisible(tile, 200, scrollable: _sheet);
          await tester.ensureVisible(tile);
          await _settle(tester);
          final small = tester.getSize(
            find.descendant(
              of: tile,
              matching: find.byType(MushafEditionThumbnail),
            ),
          );
          await tester.tap(tile);
          await _settle(tester);

          final preview = find.byType(MushafEditionPreviewScreen);
          expect(preview, findsOneWidget);
          expect(
            find.descendant(of: preview, matching: find.text('QCF V2')),
            findsOneWidget,
          );
          final large = tester.getSize(
            find.descendant(
              of: preview,
              matching: find.byType(MushafEditionThumbnail),
            ),
          );
          expect(large.width, greaterThan(small.width * 1.5));
          expect(tester.takeException(), isNull);

          await tester.tap(find.text(l10n.mushafMakePrimary));
          await _settle(tester);
          expect(preview, findsNothing);
          expect(find.text(l10n.chooseMushaf), findsNothing);
          expect(store.read().mushafVariant, 'native:qf-1');
          expect(find.text('QCF V2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the primary edition cannot be chosen again; swiping compares', (
    tester,
  ) async {
    final store = await _store(null);
    await _pumpQuran(tester, _Repository(), store: store);
    final l10n = _l10n(tester);
    await tester.tap(find.text(l10n.selectedMushaf));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('mushaf-edition-qf-19')));
    await _settle(tester);

    final preview = find.byType(MushafEditionPreviewScreen);
    expect(
      find.descendant(of: preview, matching: find.text('2 / 3')),
      findsOne,
    );
    final primary = find.widgetWithText(OutlinedButton, l10n.mushafIsPrimary);
    expect(tester.widget<OutlinedButton>(primary).onPressed, isNull);
    expect(find.text(l10n.mushafMakePrimary), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await _settle(tester);
    expect(
      find.descendant(of: preview, matching: find.text('3 / 3')),
      findsOne,
    );
    expect(
      find.descendant(of: preview, matching: find.text('QCF V2')),
      findsOneWidget,
    );
    expect(find.text(l10n.mushafMakePrimary), findsOneWidget);

    // Closing the preview keeps the current choice.
    await tester.tap(find.byType(CloseButton));
    await _settle(tester);
    expect(preview, findsNothing);
    expect(store.read().mushafVariant, defaultMushafVariant);
    expect(tester.takeException(), isNull);
  });
}

Future<PreferencesStore> _store(String? mushafVariant) async {
  SharedPreferences.setMockInitialValues({'mushaf_variant': ?mushafVariant});
  return PreferencesStore(await SharedPreferences.getInstance());
}

List<Override> _overrides(
  PreferencesStore store,
  _Repository repository,
  List<NativeMushafEdition> catalog,
) => [
  appConfigProvider.overrideWithValue(
    const AppConfig(
      apiBaseUrl: 'https://iqro.forum',
      fallbackDownloadUrl: 'https://iqro.forum',
      environment: 'production',
    ),
  ),
  preferencesStoreProvider.overrideWithValue(store),
  planRepositoryProvider.overrideWithValue(_Plan()),
  localDatabaseProvider.overrideWithValue(_Database()),
  quranRepositoryProvider.overrideWithValue(repository),
  mushafRenditionsProvider.overrideWith((ref) async => catalog),
  cachedMushafRenditionsProvider.overrideWith((ref) async => catalog),
];

final _sheet = find
    .descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable))
    .first;

// Page artwork never arrives: the miniatures' layout is defined by metadata.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(QuranScreen)));

Future<void> _pumpQuran(
  WidgetTester tester,
  _Repository repository, {
  PreferencesStore? store,
  bool dark = false,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = const Size(1080, 2340);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._overrides(store ?? await _store(null), repository, [
          _hafs,
          _tajweed,
          _v2,
        ]),
        activeAccountScopeKeyProvider.overrideWithValue(null),
        audioControllerProvider.overrideWith((ref) => _IdleAudio()),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(surahs: [], fromCache: false),
        ),
        quranJuzProvider.overrideWith((ref) async => const []),
        mushafDownloadProvider.overrideWithValue(
          const MushafDownloadSnapshot.empty(),
        ),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        darkTheme: IqroTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const QuranScreen(),
      ),
    ),
  );
  await _settle(tester);
}

class _Repository implements QuranRepository {
  _Repository([this.mushaf = MushafIdentity.primary, List<String>? requested])
    : requested = requested ?? <String>[];

  @override
  final MushafIdentity mushaf;
  final List<String> requested;
  final _asset = Completer<File>();

  @override
  QuranRepository forMushaf(MushafIdentity identity) =>
      _Repository(identity, requested);

  @override
  QuranRepository withFoundationVersion(String version) => this;

  @override
  Future<MushafPageData> mushafPage(int page, {bool forceRefresh = false}) {
    requested.add('${mushaf.code}:$page');
    return Future.value(
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
  }

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

class _Plan implements PlanRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
