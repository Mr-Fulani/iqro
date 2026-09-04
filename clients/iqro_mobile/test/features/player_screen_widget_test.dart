import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/audio/player_screen.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('maps playback progress only through matching ayah timings', () {
    final current = IqroAudioState(
      track: _track(_currentRecitation),
      reciter: _currentReciter,
      surahName: 'Аль-Бакара',
      duration: const Duration(minutes: 1),
      position: const Duration(seconds: 15),
      activeAyah: 7,
      segments: const <AudioSegment>[
        AudioSegment(
          ayahId: '2:7',
          surah: 2,
          ayah: 7,
          start: Duration(seconds: 10),
          end: Duration(seconds: 20),
        ),
      ],
    );

    expect(
      compatibleRecitationPosition(
        current: current,
        target: _playback(
          _mujawwadRecitation,
          start: const Duration(seconds: 30),
          end: const Duration(seconds: 50),
        ),
      ),
      const Duration(seconds: 40),
    );
    expect(
      compatibleRecitationPosition(
        current: current,
        target: SurahPlayback(
          track: _track(_mujawwadRecitation),
          segments: const <AudioSegment>[],
        ),
      ),
      isNull,
    );
  });

  testWidgets('switches style and reciter without losing the current ayah', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);

    expect(find.text('Текущий чтец'), findsOneWidget);
    expect(find.text('Мурратталь'), findsOneWidget);

    await tester.tap(find.text('Текущий чтец'));
    await tester.pumpAndSettle();

    final murattal = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Мурратталь'),
    );
    expect(murattal.selected, isTrue);

    await tester.tap(find.text('Муджаввад'));
    await tester.pumpAndSettle();
    expect(find.text('Другой чтец'), findsOneWidget);

    await tester.tap(find.text('Другой чтец'));
    await tester.pumpAndSettle();

    expect(harness.repository.requestedRecitationId, 'recitation-mujawwad');
    expect(harness.repository.requestedSurah, 2);
    expect(harness.controller.state.track?.recitationId, 'recitation-mujawwad');
    expect(harness.controller.state.reciter?.id, 'reciter-mujawwad');
    expect(harness.controller.state.displayedAyah, 7);
    expect(harness.engine.seekCalls.last, const Duration(seconds: 40));
    expect(harness.engine.playCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches audio rendition without losing playback position', (
    tester,
  ) async {
    final harness = await _pumpPlayer(tester);

    expect(find.text('Автоматически · 128 кбит/с'), findsOneWidget);
    await tester.ensureVisible(find.text('Качество аудио'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Качество аудио'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Высокое'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.track?.renditionQuality, 'high');
    expect(
      harness.controller.state.track?.url,
      'https://cdn.example.test/recitation-current-high.mp3',
    );
    expect(harness.controller.state.position, const Duration(seconds: 15));
    expect(harness.controller.state.displayedAyah, 7);
    expect(harness.controller.state.playing, isTrue);
    expect(harness.engine.seekCalls.last, const Duration(seconds: 15));
    expect(harness.engine.playCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<_PlayerHarness> _pumpPlayer(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final sharedPreferences = await SharedPreferences.getInstance();
  final accountScope = AccountScope.forTesting('owner');
  final rawDatabase = await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  );
  final database = LocalDatabase.forTesting(
    rawDatabase!,
    accountScope: accountScope,
  );
  final preferences = AppPreferencesController(
    PreferencesStore(sharedPreferences),
    PlanRepository(database),
  );
  final auth = AuthRepository(config: _config, accountScope: accountScope);
  final session = _TestSessionController(
    auth,
    NotificationGateway(database: database),
  );
  final repository = _AudioRepositoryFake();
  final engine = _RecordingAudioEngine();
  final controller = AudioController(engine: engine);
  await controller.loadPlayback(
    playback: _playback(
      _currentRecitation,
      start: const Duration(seconds: 10),
      end: const Duration(seconds: 20),
    ),
    reciter: _currentReciter,
    surahName: 'Аль-Бакара',
    autoplay: false,
  );
  await controller.seek(const Duration(seconds: 15));
  await controller.toggle();
  addTearDown(controller.dispose);
  addTearDown(() => tester.runAsync(rawDatabase.close));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        localDatabaseProvider.overrideWithValue(database),
        sessionProvider.overrideWith((ref) => session),
        appPreferencesProvider.overrideWith((ref) => preferences),
        audioRepositoryProvider.overrideWithValue(repository),
        audioControllerProvider.overrideWith((ref) => controller),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(
            surahs: <Surah>[
              Surah(
                id: 'surah-2',
                number: 2,
                nameAr: 'البقرة',
                nameEn: 'Al-Baqarah',
                nameRu: 'Аль-Бакара',
                ayahCount: 286,
                revelationType: 'medinan',
              ),
            ],
            fromCache: false,
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        home: const PlayerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _PlayerHarness(repository, engine, controller);
}

class _PlayerHarness {
  const _PlayerHarness(this.repository, this.engine, this.controller);

  final _AudioRepositoryFake repository;
  final _RecordingAudioEngine engine;
  final AudioController controller;
}

const _config = AppConfig(
  apiBaseUrl: 'https://staging.iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'staging',
);

AuthSession get _session => AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: 'owner',
  userStatus: 'guest',
  deviceId: 'device',
);

const _currentReciter = Reciter(
  id: 'reciter-current',
  slug: 'current-reciter',
  nameAr: 'القارئ الحالي',
  nameEn: 'Current reciter',
  nameRu: 'Текущий чтец',
  nameTr: 'Mevcut okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

const _mujawwadReciter = Reciter(
  id: 'reciter-mujawwad',
  slug: 'other-reciter',
  nameAr: 'القارئ الآخر',
  nameEn: 'Other reciter',
  nameRu: 'Другой чтец',
  nameTr: 'Diğer okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

const _currentRecitation = Recitation(
  id: 'recitation-current',
  code: 'current-murattal',
  reciter: _currentReciter,
  style: 'murattal',
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);

const _mujawwadRecitation = Recitation(
  id: 'recitation-mujawwad',
  code: 'other-mujawwad',
  reciter: _mujawwadReciter,
  style: 'mujawwad',
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);

AudioTrack _track(Recitation recitation) => AudioTrack(
  id: 'track-${recitation.id}',
  recitationId: recitation.id,
  surah: 2,
  url: 'https://cdn.example.test/${recitation.id}.mp3',
  duration: const Duration(minutes: 1),
  offlineDownloadAllowed: false,
  renditionQuality: 'standard',
  codec: 'mp3',
  bitrateKbps: 128,
  renditions: <AudioRendition>[
    AudioRendition(
      id: '${recitation.id}-standard',
      quality: 'standard',
      isDefault: true,
      url: 'https://cdn.example.test/${recitation.id}.mp3',
      codec: 'mp3',
      bitrateKbps: 128,
    ),
    AudioRendition(
      id: '${recitation.id}-high',
      quality: 'high',
      isDefault: false,
      url: 'https://cdn.example.test/${recitation.id}-high.mp3',
      codec: 'mp3',
      bitrateKbps: 256,
    ),
  ],
);

SurahPlayback _playback(
  Recitation recitation, {
  Duration start = const Duration(seconds: 10),
  Duration end = const Duration(seconds: 20),
}) => SurahPlayback(
  track: _track(recitation),
  segments: <AudioSegment>[
    AudioSegment(ayahId: '2:7', surah: 2, ayah: 7, start: start, end: end),
  ],
);

class _AudioRepositoryFake implements AudioRepository {
  String? requestedRecitationId;
  int? requestedSurah;

  @override
  Future<List<Reciter>> reciters({bool forceRefresh = false}) async =>
      const <Reciter>[_currentReciter, _mujawwadReciter];

  @override
  Future<List<Recitation>> recitations({
    String? reciterId,
    bool forceRefresh = false,
  }) async => const <Recitation>[_currentRecitation, _mujawwadRecitation];

  @override
  Future<SurahPlayback> playback({
    required String recitationId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    requestedRecitationId = recitationId;
    requestedSurah = surah;
    return _playback(
      _mujawwadRecitation,
      start: const Duration(seconds: 30),
      end: const Duration(seconds: 50),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSessionController extends SessionController {
  _TestSessionController(AuthRepository auth, NotificationGateway notifications)
    : super(auth, notifications, () => 'ru') {
    state = AsyncValue<AuthSession?>.data(_session);
  }

  @override
  Future<void> initialize() async {}
}

class _RecordingAudioEngine implements IqroAudioEngine {
  final _playerStates = StreamController<PlayerState>.broadcast(sync: true);
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _durations = StreamController<Duration?>.broadcast(sync: true);
  final seekCalls = <Duration>[];
  var playCalls = 0;
  var _playing = false;
  var _processingState = ProcessingState.idle;
  var _disposed = false;

  @override
  Stream<PlayerException> get errorStream => const Stream.empty();

  @override
  bool get playing => _playing;

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  ProcessingState get processingState => _processingState;

  @override
  Future<void> clearAudioSources() async {
    _processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      _playerStates.close(),
      _positions.close(),
      _durations.close(),
    ]);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playerStates.add(PlayerState(false, _processingState));
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    _playing = true;
    _playerStates.add(PlayerState(true, _processingState));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    _positions.add(position);
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    _playing = false;
    _processingState = ProcessingState.ready;
    _durations.add(const Duration(minutes: 1));
    _playerStates.add(PlayerState(false, _processingState));
    return const Duration(minutes: 1);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {
    _playing = false;
    _processingState = ProcessingState.idle;
    _playerStates.add(PlayerState(false, _processingState));
  }
}
