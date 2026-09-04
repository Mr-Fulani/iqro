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
      initialLocation: '/audio',
      routes: <RouteBase>[
        GoRoute(
          path: '/audio',
          builder: (context, state) => const AudioScreen(),
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
              apiBaseUrl: 'https://staging.iqro.forum',
              fallbackDownloadUrl: 'https://iqro.forum',
              environment: 'staging',
            ),
          ),
          appPreferencesProvider.overrideWith((ref) => preferences),
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

    expect(find.text('Воспроизвести'), findsNothing);

    await tester.tap(find.text('Тестовый чтец'));
    await tester.pumpAndSettle();

    expect(repository.requestedRecitationId, 'recitation-1');
    expect(repository.requestedSurah, 1);
    expect(controller.state.reciter?.id, 'reciter-1');
    expect(controller.state.surahName, 'Аль-Фатиха');
    expect(engine.playCalls, 1);
    expect(find.text('PLAYER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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

class _AudioRepositoryFake implements AudioRepository {
  String? requestedRecitationId;
  int? requestedSurah;

  @override
  Future<List<Reciter>> reciters({bool forceRefresh = false}) async =>
      const <Reciter>[_reciter];

  @override
  Future<List<Recitation>> recitationsForReciters(
    Iterable<String> reciterIds,
  ) async {
    expect(reciterIds, contains(_reciter.id));
    return const <Recitation>[_recitation];
  }

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
