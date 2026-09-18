import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/dua/dua_presentation.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/dua/dua_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('Dua catalog', () {
    testWidgets('shows the localized empty state at narrow large-text layout', (
      tester,
    ) async {
      await _useNarrowLargeTextView(tester);
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[],
      );

      expect(find.text('Категории ду’а пока недоступны'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out long category data at narrow width and 2x text', (
      tester,
    ) async {
      await _useNarrowLargeTextView(tester);
      const longTitle =
          'Очень длинное название категории молитв для проверки '
          'корректного переноса текста';
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[
          DuaCategory(
            id: 'category-1',
            slug: 'long-category',
            title: longTitle,
            entryCount: 24,
            collection: 'hisn-al-muslim',
            collectionVersion: '2026-09',
            sourceNumber: 1,
          ),
        ],
      );

      expect(find.text(longTitle), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders Arabic catalog and entry content right-to-left', (
      tester,
    ) async {
      const category = DuaCategory(
        id: 'category-ar',
        slug: 'morning',
        title: 'أذكار الصباح',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        collectionVersion: '2026-09',
        sourceNumber: 1,
      );
      final entry = _entry(
        categoryTitle: category.title,
        arabicText: 'اللهم بك أصبحنا وبك أمسينا',
        meaning: 'دعاء الصباح',
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('ar'),
        categories: () async => const <DuaCategory>[category],
        entries: (identity) async {
          expect(identity, category.identity);
          return <DuaEntry>[entry];
        },
      );

      expect(
        Directionality.of(tester.element(find.text(category.title))),
        TextDirection.rtl,
      );

      await tester.tap(find.text(category.title));
      await tester.pumpAndSettle();

      final arabic = tester.widget<Text>(find.text(entry.arabicText));
      expect(arabic.textDirection, TextDirection.rtl);
      expect(
        Directionality.of(tester.element(find.text(entry.arabicText))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('debounces root search and renders server results', (
      tester,
    ) async {
      final requests = <DuaSearchQuery>[];
      final result = _entry(
        categoryTitle: 'Server category',
        arabicText: 'الرحمة',
        meaning: 'Server-only result',
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('en'),
        categories: () async => const <DuaCategory>[],
        search: (request) async {
          requests.add(request);
          return <DuaEntry>[result];
        },
      );

      await tester.enterText(find.byType(EditableText), 'm');
      await tester.pump();
      expect(
        find.text('Enter at least 2 characters to search'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, isEmpty);

      await tester.enterText(find.byType(EditableText), '  mercy  ');
      await tester.pump();
      expect(requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 349));
      expect(requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(requests, hasLength(1));
      expect(requests.single.query, 'mercy');
      expect(requests.single.collection, isNull);
      expect(requests.single.category, isNull);

      await tester.pumpAndSettle();
      expect(find.text('الرحمة'), findsOneWidget);
      expect(find.text('Server category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resolves a unique legacy category link across collections', (
      tester,
    ) async {
      const category = DuaCategory(
        id: 'category-legacy',
        slug: 'waking-up',
        title: 'Слова поминания при пробуждении ото сна',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        collectionVersion: '2026-09',
        sourceNumber: 1,
      );
      final entry = _entry(
        categoryTitle: category.title,
        arabicText: 'الْحَمْدُ للَّهِ',
        meaning: 'Хвала Аллаху',
      );
      DuaCategoryIdentity? requestedIdentity;

      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        home: const DuaScreen(initialCategory: 'waking-up'),
        categories: () async => const <DuaCategory>[category],
        entries: (identity) async {
          requestedIdentity = identity;
          return <DuaEntry>[entry];
        },
      );

      expect(requestedIdentity, category.identity);
      expect(find.text(category.title), findsWidgets);
      expect(find.text(entry.arabicText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dua cold detail route', () {
    testWidgets('shows loading then a recoverable unavailable state', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      await _pumpDetail(tester, load: (id) => result.future);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      result.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Это ду’а недоступно'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses a saved fallback but keeps unverified audio disabled', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      var loadCalls = 0;
      final cached = _entry(
        categoryTitle: 'Сохранённая категория',
        arabicText: 'سبحان الله',
        meaning: 'Пречист Аллах',
        audio: const <DuaAudioAsset>[
          DuaAudioAsset(
            id: 'audio-1',
            languageCode: 'ar',
            provider: 'source',
            readerName: 'Reader',
            readerNameAr: 'القارئ',
            url: 'https://media.example.test/dua/1.mp3',
            sourceUrl: 'https://source.example.test/1',
            rightsUrl: '',
            sourceVersion: '2026-09',
          ),
        ],
      );
      await _pumpDetail(
        tester,
        load: (id) {
          loadCalls += 1;
          return result.future;
        },
        initialEntry: cached,
      );

      expect(find.text(cached.arabicText), findsOneWidget);
      expect(
        find.text(
          'Показана сохранённая копия. Аудио станет доступно после проверки '
          'актуальной версии.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);

      result.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Повторить'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(loadCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not mask an authoritative withdrawal with initial data', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      final withdrawn = _entry(
        categoryTitle: 'Withdrawn category',
        arabicText: 'سبحان الله',
        meaning: 'Withdrawn entry',
      );
      await _pumpDetail(
        tester,
        load: (id) => result.future,
        initialEntry: withdrawn,
      );

      expect(find.text(withdrawn.arabicText), findsOneWidget);

      result.completeError(
        const ApiException(
          message: 'Not found',
          code: 'not_found',
          statusCode: 404,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(withdrawn.arabicText), findsNothing);
      expect(find.text('Это ду’а недоступно'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'clears favorite state and ignores account A completion after handoff',
    (tester) async {
      final accountScope = AccountScope.forTesting('account-a');
      final database = await _openTestDatabase(
        tester,
        accountScope: accountScope,
      );
      final repository = _DelayedFavoriteDuaRepository(database);
      final controller = AudioController(engine: _SilentAudioEngine());
      final rebuild = ValueNotifier<int>(0);
      addTearDown(controller.dispose);
      addTearDown(rebuild.dispose);
      final entry = _entry(
        categoryTitle: 'Morning',
        arabicText: 'سبحان الله',
        meaning: 'Glory be to Allah',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localDatabaseProvider.overrideWithValue(database),
            duaRepositoryProvider.overrideWithValue(repository),
            audioControllerProvider.overrideWith((ref) => controller),
          ],
          child: _TestApp(
            locale: const Locale('ru'),
            home: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, value, child) => DuaEntryScreen(entry: entry),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(repository.favoriteReads, hasLength(1));

      repository.favoriteReads.single.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pump();
      expect(repository.favoriteToggles, hasLength(1));

      accountScope.activate('account-b');
      rebuild.value += 1;
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(repository.favoriteReads, hasLength(2));

      repository.favoriteToggles.single.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      repository.favoriteReads.last.complete(false);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same audio opened by another screen transfers ownership', (
    tester,
  ) async {
    final database = await _openTestDatabase(tester);
    final engine = _SilentAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);
    final entry = _entry(
      categoryTitle: 'Morning',
      arabicText: 'سبحان الله',
      meaning: 'Glory be to Allah',
      audio: const <DuaAudioAsset>[
        DuaAudioAsset(
          id: 'audio-owner-transfer',
          languageCode: 'ar',
          provider: 'source',
          readerName: 'Reader',
          readerNameAr: 'القارئ',
          url: 'https://media.example.test/dua/owner.mp3',
          sourceUrl: 'https://source.example.test/owner',
          rightsUrl: '',
          sourceVersion: '2026-09',
        ),
      ],
    );
    final playbackId = duaAudioPlaybackId(entry, entry.audio.single, 0);
    await controller.loadStandalone(
      id: playbackId,
      url: entry.audio.single.url,
      title: 'Existing screen',
      owner: Object(),
    );
    expect(engine.setAudioSourceCalls, 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(database),
          audioControllerProvider.overrideWith((ref) => controller),
        ],
        child: _TestApp(
          locale: const Locale('ru'),
          home: DuaEntryScreen(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    expect(engine.setAudioSourceCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _useNarrowLargeTextView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required Locale locale,
  required Future<List<DuaCategory>> Function() categories,
  Widget home = const DuaScreen(),
  Future<List<DuaEntry>> Function(DuaCategoryIdentity identity)? entries,
  Future<List<DuaEntry>> Function(DuaSearchQuery request)? search,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        duaCategoriesProvider.overrideWith((ref) => categories()),
        duaEntriesByCategoryProvider.overrideWith(
          (ref, identity) =>
              entries?.call(identity) ?? Future.value(const <DuaEntry>[]),
        ),
        duaSearchProvider.overrideWith(
          (ref, request) =>
              search?.call(request) ?? Future.value(const <DuaEntry>[]),
        ),
      ],
      child: _TestApp(
        locale: locale,
        textScaler: tester.view.physicalSize.width == 320
            ? const TextScaler.linear(2)
            : TextScaler.noScaling,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Future<DuaEntry> Function(String id) load,
  DuaEntry? initialEntry,
}) async {
  final database = await _openTestDatabase(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(database),
        duaEntryProvider.overrideWith((ref, id) => load(id)),
        audioControllerProvider.overrideWith(
          (ref) => AudioController(engine: _SilentAudioEngine()),
        ),
      ],
      child: _TestApp(
        locale: const Locale('ru'),
        home: DuaEntryRouteScreen(
          entryId: '0194f11e-972b-7b07-a772-5b7651ab78ea',
          initialEntry: initialEntry,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.locale,
    required this.home,
    this.textScaler = TextScaler.noScaling,
  });

  final Locale locale;
  final Widget home;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: IqroTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home,
    );
  }
}

DuaEntry _entry({
  required String categoryTitle,
  required String arabicText,
  required String meaning,
  List<DuaAudioAsset> audio = const <DuaAudioAsset>[],
}) => DuaEntry(
  id: '0194f11e-972b-7b07-a772-5b7651ab78ea',
  sourceNumber: 1,
  collection: 'hisn-al-muslim',
  collectionVersion: '2026-09',
  categoryTitle: categoryTitle,
  categorySlug: 'morning',
  arabicText: arabicText,
  meaning: meaning,
  transliteration: '',
  repetitions: 1,
  sourceLabel: 'Hisn al-Muslim',
  audio: audio,
);

class _SilentAudioEngine implements IqroAudioEngine {
  var setAudioSourceCalls = 0;

  @override
  Stream<PlayerException> get errorStream => const Stream.empty();

  @override
  bool get playing => false;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  ProcessingState get processingState => ProcessingState.idle;

  @override
  Future<void> clearAudioSources() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    setAudioSourceCalls += 1;
    return Duration.zero;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {}
}

Future<LocalDatabase> _openTestDatabase(
  WidgetTester tester, {
  AccountScope? accountScope,
}) async {
  final database = (await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(database.close));
  return LocalDatabase.forTesting(database, accountScope: accountScope);
}

class _DelayedFavoriteDuaRepository extends DuaRepository {
  _DelayedFavoriteDuaRepository(LocalDatabase database)
    : super(database: database, remote: _UnusedDuaRemote());

  final List<Completer<bool>> favoriteReads = <Completer<bool>>[];
  final List<Completer<bool>> favoriteToggles = <Completer<bool>>[];

  @override
  Future<bool> isFavorite(
    DuaEntry entry, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = Completer<bool>();
    favoriteReads.add(result);
    return result.future;
  }

  @override
  Future<bool> toggleFavorite(
    DuaEntry entry, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = Completer<bool>();
    favoriteToggles.add(result);
    return result.future;
  }
}

class _UnusedDuaRemote implements DuaRemoteGateway {
  @override
  Uri get apiBaseUri => Uri.parse('https://iqro.forum/api/v1');

  Never _unused() => throw UnsupportedError('Not used by this widget test');

  @override
  Future<Object?> categories(String locale) => _unused();

  @override
  Future<Object?> collections(String locale) => _unused();

  @override
  Future<Object?> entries(
    String locale, {
    String? collection,
    String? category,
    String? query,
    String? cursor,
    required int pageSize,
  }) => _unused();

  @override
  Future<Object?> entry(String locale, String id) => _unused();

  @override
  Future<Object?> favorites(
    String locale, {
    AccountScopeSnapshot? accountScope,
  }) => _unused();

  @override
  Future<Object?> resolveEntry(
    String locale, {
    required String collection,
    required int sourceNumber,
  }) => _unused();

  @override
  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite, {
    AccountScopeSnapshot? accountScope,
  }) => _unused();
}
