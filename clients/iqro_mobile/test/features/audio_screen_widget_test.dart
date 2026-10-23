import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/audio/audio_screen.dart';
import 'package:iqro_mobile/features/audio/reciter_launch_screen.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('tapping a reciter starts playback and opens the player', (
    tester,
  ) async {
    final harness = await _pumpAudioScreen(tester);

    expect(find.text('Воспроизвести'), findsNothing);
    expect(find.text('Тестовый чтец'), findsOneWidget);
    expect(find.text('Чтец муджаввада'), findsNothing);

    await tester.tap(find.text('Тестовый чтец'));
    await tester.pumpAndSettle();

    expect(harness.repository.requestedRecitationId, 'recitation-1');
    expect(harness.repository.requestedSurah, 1);
    expect(harness.controller.state.reciter?.id, 'reciter-1');
    expect(harness.controller.state.surahName, 'Аль-Фатиха');
    expect(harness.engine.playCalls, 1);
    expect(find.text('PLAYER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an announcement opens its reciter straight in the player', (
    tester,
  ) async {
    final harness = await _pumpAudioScreen(
      tester,
      location: '/audio/reciter/reciter-2?play=1',
    );

    expect(harness.repository.requestedRecitationId, 'recitation-2');
    expect(harness.controller.state.reciter?.id, 'reciter-2');
    expect(harness.engine.playCalls, 1);
    expect(harness.preferences.state.listeningRecitationId, 'recitation-2');
    expect(find.text('PLAYER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown reciter leads back to all reciters', (tester) async {
    final harness = await _pumpAudioScreen(
      tester,
      location: '/audio/reciter/missing?play=1',
    );

    expect(harness.engine.playCalls, 0);
    expect(find.text('PLAYER'), findsNothing);
    await tester.tap(find.text('Все чтецы'));
    await tester.pumpAndSettle();
    expect(find.text('Тестовый чтец'), findsOneWidget);
  });

  testWidgets('recitation style filters reciters and defaults to Murattal', (
    tester,
  ) async {
    final harness = await _pumpAudioScreen(tester);

    expect(
      find.text('Для этой записи право на офлайн-загрузку не предоставлено.'),
      findsNothing,
    );
    final murattal = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Мурратталь'),
    );
    expect(murattal.selected, isTrue);
    expect(find.text('Тестовый чтец'), findsOneWidget);
    expect(find.text('Чтец муджаввада'), findsNothing);

    await tester.tap(find.text('Муджаввад'));
    await tester.pumpAndSettle();

    final mujawwad = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Муджаввад'),
    );
    expect(mujawwad.selected, isTrue);
    expect(find.text('Тестовый чтец'), findsNothing);
    expect(find.text('Чтец муджаввада'), findsOneWidget);

    await tester.tap(find.text('Чтец муджаввада'));
    await tester.pumpAndSettle();

    expect(harness.repository.requestedRecitationId, 'recitation-2');
    expect(harness.controller.state.reciter?.id, 'reciter-2');
    expect(find.text('PLAYER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Audio keeps its reader while Mushaf owns the physical player', (
    tester,
  ) async {
    final harness = await _pumpAudioScreen(tester);
    await harness.preferences.setListeningRecitation('recitation-1');
    await harness.controller.loadPlayback(
      playback: await harness.repository.playback(
        recitationId: 'recitation-1',
        surah: 1,
      ),
      reciter: _reciter,
      surahName: 'Audio Al-Fatiha',
      autoplay: false,
    );
    await harness.controller.loadPlayback(
      playback: await harness.repository.playback(
        recitationId: 'recitation-2',
        surah: 2,
      ),
      reciter: _mujawwadReciter,
      channel: AudioPlaybackChannel.mushaf,
      surahName: 'Mushaf Al-Baqarah',
      autoplay: false,
    );
    await tester.pumpAndSettle();

    expect(harness.controller.state.channel, AudioPlaybackChannel.mushaf);
    expect(find.text('Чтец муджаввада'), findsNothing);
    expect(find.text('Тестовый чтец'), findsWidgets);
    expect(find.text('Mushaf Al-Baqarah'), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(harness.controller.state.channel, AudioPlaybackChannel.listening);
    expect(harness.controller.state.reciter?.id, _reciter.id);
    expect(tester.takeException(), isNull);
  });
  testWidgets('landscape keeps the page in a centered column', (tester) async {
    // Redmi Note 7 turned to landscape: 851x393 logical pixels.
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await _pumpAudioScreen(tester);

    expect(tester.takeException(), isNull);
    const width = 2340 / 2.75;
    final texts = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Text),
    );
    expect(texts, findsWidgets);
    for (var index = 0; index < texts.evaluate().length; index++) {
      final rect = tester.getRect(texts.at(index));
      expect(rect.left, greaterThanOrEqualTo((width - 640) / 2));
      expect(rect.right, lessThanOrEqualTo((width + 640) / 2));
    }
    await tester.ensureVisible(find.text('Тестовый чтец'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тестовый чтец'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYER'), findsOneWidget);
  });
}

Future<_AudioTestHarness> _pumpAudioScreen(
  WidgetTester tester, {
  String location = '/audio',
}) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final sharedPreferences = await SharedPreferences.getInstance();
  final rawDatabase = await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  );
  final database = LocalDatabase.forTesting(rawDatabase!);
  final preferences = AppPreferencesController(
    PreferencesStore(sharedPreferences),
    PlanRepository(database),
  );
  final repository = _AudioRepositoryFake();
  final engine = _RecordingAudioEngine();
  final controller = AudioController(engine: engine);
  final router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/audio', builder: (context, state) => const AudioScreen()),
      GoRoute(path: '/app', builder: (context, state) => const AudioScreen()),
      GoRoute(
        path: '/audio/reciter/:id',
        builder: (context, state) => ReciterLaunchScreen(
          reciterId: state.pathParameters['id']!,
          autoplay: state.uri.queryParameters['play'] == '1',
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const Scaffold(body: Text('PLAYER')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(controller.dispose);
  addTearDown(() => tester.runAsync(rawDatabase.close));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            fallbackDownloadUrl: 'https://iqro.forum',
            environment: 'production',
          ),
        ),
        appPreferencesProvider.overrideWith((ref) => preferences),
        activeAccountScopeKeyProvider.overrideWithValue(
          accountScopeKey(database.accountScope.current!),
        ),
        audioRepositoryProvider.overrideWithValue(repository),
        audioControllerProvider.overrideWith((ref) => controller),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(
            surahs: <Surah>[
              Surah(
                id: 'surah-1',
                number: 1,
                nameAr: 'الفاتحة',
                nameEn: 'Al-Fatihah',
                nameRu: 'Аль-Фатиха',
                ayahCount: 7,
                revelationType: 'meccan',
              ),
            ],
            fromCache: false,
          ),
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _AudioTestHarness(repository, engine, controller, preferences);
}

class _AudioTestHarness {
  const _AudioTestHarness(
    this.repository,
    this.engine,
    this.controller,
    this.preferences,
  );

  final _AudioRepositoryFake repository;
  final _RecordingAudioEngine engine;
  final AudioController controller;
  final AppPreferencesController preferences;
}

const _reciter = Reciter(
  id: 'reciter-1',
  slug: 'test-reciter',
  nameAr: 'القارئ التجريبي',
  nameEn: 'Test reciter',
  nameRu: 'Тестовый чтец',
  nameTr: 'Test okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

const _recitation = Recitation(
  id: 'recitation-1',
  code: 'test-recitation',
  reciter: _reciter,
  style: 'murattal',
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);

const _mujawwadReciter = Reciter(
  id: 'reciter-2',
  slug: 'test-mujawwad-reciter',
  nameAr: 'القارئ المجود',
  nameEn: 'Mujawwad reciter',
  nameRu: 'Чтец муджаввада',
  nameTr: 'Mücevved okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

const _mujawwadRecitation = Recitation(
  id: 'recitation-2',
  code: 'test-mujawwad-recitation',
  reciter: _mujawwadReciter,
  style: 'mujawwad',
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);

class _AudioRepositoryFake implements AudioRepository {
  String? requestedRecitationId;
  int? requestedSurah;

  @override
  Future<List<Reciter>> reciters({bool forceRefresh = false}) async =>
      const <Reciter>[_reciter, _mujawwadReciter];

  @override
  Future<List<Recitation>> recitations({
    String? reciterId,
    bool forceRefresh = false,
  }) async => const <Recitation>[_recitation, _mujawwadRecitation];

  @override
  Future<SurahPlayback> playback({
    required String recitationId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    requestedRecitationId = recitationId;
    requestedSurah = surah;
    return SurahPlayback(
      track: AudioTrack(
        id: 'track-$surah',
        recitationId: recitationId,
        surah: surah,
        url: 'https://cdn.example.test/audio.mp3',
        duration: const Duration(minutes: 3),
        offlineDownloadAllowed: false,
      ),
      segments: const <AudioSegment>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAudioEngine implements IqroAudioEngine {
  var playCalls = 0;

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
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<Duration?> setAudioSource(AudioSource source) async =>
      const Duration(minutes: 3);

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {}
}
