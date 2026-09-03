import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/audio/audio_playback_store.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'Quran and standalone audio use one engine and preserve Quran options',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );
      await controller.setSpeed(1.25);
      await controller.toggleRepeat();

      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
        contentType: 'dua',
        autoplay: false,
      );

      expect(engine.sources, hasLength(2));
      expect(controller.state.active, isFalse);
      expect(controller.state.standalone?.mediaItem.id, 'dua:1');
      expect(
        controller.state.standalone?.mediaItem.extras?['content_type'],
        'dua',
      );
      expect(controller.state.speed, 1.25);
      expect(controller.state.repeatEnabled, isTrue);

      await controller.stopStandalone('dua:1');
      expect(controller.state.standalone, isNull);
      expect(controller.state.speed, 1.25);
      expect(controller.state.repeatEnabled, isTrue);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );
      expect(engine.speed, 1.25);
      expect(engine.loopMode, LoopMode.one);
    },
  );

  test('a late Dua stop cannot stop a newer Quran source', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      autoplay: false,
    );
    final quranLoad = controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
      autoplay: false,
    );
    final staleStop = controller.stopStandalone('dua:1');

    await Future.wait(<Future<void>>[quranLoad, staleStop]);

    expect(controller.state.active, isTrue);
    expect(controller.state.track?.id, 'track-1');
    expect(controller.state.standalone, isNull);
    // Loading Quran preempts the old Dua once; the stale close callback must
    // not issue a second stop against the new source.
    expect(engine.stopCalls, 1);
    expect(
      ((engine.sources.last as UriAudioSource).tag! as MediaItem).id,
      'track-1',
    );
  });

  test('standalone controls are ownership checked', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      autoplay: false,
    );
    await controller.seekStandalone('another-id', const Duration(seconds: 20));
    await controller.toggleStandaloneRepeat('another-id');
    await controller.toggleStandalone('another-id');

    expect(engine.seekCalls, isEmpty);
    expect(controller.state.standalone?.repeatEnabled, isFalse);
    expect(controller.state.standalone?.playing, isFalse);

    await controller.seekStandalone('dua:1', const Duration(seconds: 20));
    await controller.toggleStandaloneRepeat('dua:1');
    await controller.toggleStandalone('dua:1');

    expect(engine.seekCalls, <Duration>[const Duration(seconds: 20)]);
    expect(controller.state.standalone?.repeatEnabled, isTrue);
    expect(controller.state.standalone?.playing, isTrue);
  });

  test(
    'owned standalone controls cannot be called without the owner',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);
      final owner = Object();

      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Owned session',
        owner: owner,
        autoplay: false,
      );
      await controller.seekStandalone('dua:1', const Duration(seconds: 20));
      await controller.toggleStandaloneRepeat('dua:1');
      await controller.toggleStandalone('dua:1');
      await controller.stopStandalone('dua:1');

      expect(engine.seekCalls, isEmpty);
      expect(controller.state.standalone?.repeatEnabled, isFalse);
      expect(controller.state.standalone?.playing, isFalse);
      expect(controller.state.standalone?.mediaItem.id, 'dua:1');

      await controller.stopStandalone('dua:1', owner: owner);
      expect(controller.state.standalone, isNull);
    },
  );

  test(
    'the newest standalone request wins while an older load is pending',
    () async {
      final engine = _FakeAudioEngine()..blockNextSource();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      final first = controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'First',
      );
      await engine.nextSourceStarted.future;
      final second = controller.loadStandalone(
        id: 'dua:2',
        url: 'https://media.example.test/dua/2.mp3',
        title: 'Second',
      );

      engine.releaseBlockedSource();
      await Future.wait(<Future<void>>[first, second]);

      expect(engine.sources, hasLength(2));
      expect(engine.stopCalls, 1);
      expect(engine.playCalls, 1);
      expect(controller.state.standalone?.mediaItem.id, 'dua:2');
      expect(controller.state.standalone?.playing, isTrue);
    },
  );

  test(
    'closing a pending standalone request prevents delayed autoplay',
    () async {
      final engine = _FakeAudioEngine()..blockNextSource();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      final load = controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
      );
      await engine.nextSourceStarted.future;
      final stop = controller.stopStandalone('dua:1');

      engine.releaseBlockedSource();
      await Future.wait(<Future<void>>[load, stop]);

      expect(engine.playCalls, 0);
      expect(controller.state.anyAudioActive, isFalse);
    },
  );

  test(
    'invalid standalone input never interrupts valid Quran playback',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );

      expect(
        () => controller.loadStandalone(
          id: 'dua:1',
          url: 'http://media.example.test/dua/1.mp3',
          title: 'Unsafe',
        ),
        throwsFormatException,
      );
      expect(controller.state.track?.id, 'track-1');
      expect(controller.state.standalone, isNull);
      expect(engine.stopCalls, 0);
    },
  );

  test('invalid Quran ranges never interrupt the current source', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
      autoplay: false,
    );

    expect(
      () => controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        startAyah: 1,
      ),
      throwsStateError,
    );
    expect(() => controller.setAyahRange(2, 1), throwsArgumentError);
    expect(controller.state.track?.id, 'track-1');
    expect(engine.stopCalls, 0);
  });

  test(
    'inconsistent Quran timings never interrupt the current source',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );
      const malformed = SurahPlayback(
        track: _playbackTrack,
        segments: <AudioSegment>[
          AudioSegment(
            ayahId: 'ayah-1',
            surah: 1,
            ayah: 1,
            start: Duration(seconds: 30),
            end: Duration(seconds: 40),
          ),
          AudioSegment(
            ayahId: 'ayah-2',
            surah: 1,
            ayah: 2,
            start: Duration(seconds: 10),
            end: Duration(seconds: 20),
          ),
        ],
      );

      expect(
        () => controller.loadPlayback(
          playback: malformed,
          reciter: _reciter,
          surahName: 'Malformed',
          startAyah: 1,
          endAyah: 2,
        ),
        throwsFormatException,
      );
      expect(controller.state.surahName, 'Al-Fatiha');
      expect(engine.stopCalls, 0);
    },
  );

  test('a Quran seek queued after a new source intent is ignored', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
      autoplay: false,
    );
    engine.blockNextSource();
    final load = controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      autoplay: false,
    );
    final staleSeek = controller.seek(const Duration(seconds: 25));

    await engine.nextSourceStarted.future;
    engine.releaseBlockedSource();
    await Future.wait(<Future<void>>[load, staleSeek]);

    expect(engine.seekCalls, isEmpty);
    expect(controller.state.standalone?.mediaItem.id, 'dua:1');
  });

  test(
    'standalone load errors are retryable and clear after success',
    () async {
      final engine = _FakeAudioEngine()
        ..nextSourceError = StateError('offline');
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await expectLater(
        controller.loadStandalone(
          id: 'dua:1',
          url: 'https://media.example.test/dua/1.mp3',
          title: 'Morning remembrance',
        ),
        throwsStateError,
      );
      expect(controller.state.standalone?.playing, isFalse);
      expect(controller.state.standalone?.error, contains('offline'));

      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
        autoplay: false,
      );

      expect(controller.state.standalone?.loading, isFalse);
      expect(controller.state.standalone?.error, isNull);
    },
  );

  test(
    'dispose cancels a pending source and disposes the engine once',
    () async {
      final engine = _FakeAudioEngine()..blockNextSource();
      final controller = AudioController(engine: engine);
      final load = controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
      );
      await engine.nextSourceStarted.future;

      controller.dispose();
      controller.dispose();
      await load;

      expect(engine.disposeCalls, 1);
      expect(engine.playCalls, 0);
    },
  );

  test('a sleep timer follows Quran source changes', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
      autoplay: false,
    );
    controller.setSleepTimer(const Duration(milliseconds: 20));
    await controller.loadPlayback(
      playback: _secondPlayback,
      reciter: _reciter,
      surahName: 'Al-Baqarah',
      autoplay: false,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.track?.id, 'track-2');
    expect(controller.state.sleepTimerMinutes, isNull);
    expect(engine.pauseCalls, 1);
  });

  test('stale same-track restore never seeks a manual load', () async {
    final database = await _audioStoreDatabase();
    addTearDown(database.close);
    final store = AudioPlaybackStore(database);
    await store.write(
      AudioPlaybackSnapshot(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Saved Al-Fatiha',
        position: const Duration(seconds: 25),
        speed: 1,
        repeatEnabled: false,
        savedAt: DateTime.utc(2026, 9, 3),
      ),
    );
    final engine = _FakeAudioEngine()..blockNextSource();
    final controller = AudioController(engine: engine, playbackStore: store);
    addTearDown(controller.dispose);

    final restore = controller.restore();
    await engine.nextSourceStarted.future;
    final manualLoad = controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Manual Al-Fatiha',
      autoplay: false,
    );
    engine.releaseBlockedSource();
    await Future.wait(<Future<void>>[restore, manualLoad]);

    expect(controller.state.track?.id, 'track-1');
    expect(controller.state.surahName, 'Manual Al-Fatiha');
    expect(controller.state.position, Duration.zero);
    expect(engine.seekCalls, isEmpty);
  });

  test('a failing restore cannot clear a manual source state', () async {
    final database = await _audioStoreDatabase();
    addTearDown(database.close);
    final store = _ControlledPlaybackStore(database);
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine, playbackStore: store);
    addTearDown(controller.dispose);

    final restore = controller.restore();
    await store.clearStarted.future;
    final manualLoad = controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Manual Al-Fatiha',
      autoplay: false,
    );
    store.releaseClear();
    await Future.wait(<Future<void>>[restore, manualLoad]);

    expect(controller.state.track?.id, 'track-1');
    expect(controller.state.surahName, 'Manual Al-Fatiha');
  });

  test(
    'a transient restore load failure preserves the saved snapshot',
    () async {
      final database = await _audioStoreDatabase();
      addTearDown(database.close);
      final store = AudioPlaybackStore(database);
      await store.write(
        AudioPlaybackSnapshot(
          playback: _playback,
          reciter: _reciter,
          surahName: 'Saved Al-Fatiha',
          position: const Duration(seconds: 12),
          speed: 1,
          repeatEnabled: false,
          savedAt: DateTime.utc(2026, 9, 3),
        ),
      );
      final engine = _FakeAudioEngine()
        ..nextSourceError = StateError('offline');
      final controller = AudioController(engine: engine, playbackStore: store);
      addTearDown(controller.dispose);

      await controller.restore();

      expect(await store.read(), isNotNull);
      expect(controller.state.error, contains('offline'));
    },
  );

  test('an old same-id owner cannot stop a newer standalone session', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);
    final firstOwner = Object();
    final secondOwner = Object();

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'First route',
      owner: firstOwner,
      autoplay: false,
    );
    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Second route',
      owner: secondOwner,
      autoplay: false,
    );
    final stopsBeforeStaleClose = engine.stopCalls;

    await controller.stopStandalone('dua:1', owner: firstOwner);

    expect(engine.stopCalls, stopsBeforeStaleClose);
    expect(controller.state.standalone?.mediaItem.title, 'Second route');

    await controller.stopStandalone('dua:1', owner: secondOwner);
    expect(controller.state.standalone, isNull);
    expect(engine.clearCalls, 1);
  });

  test('queued old-owner controls cannot affect a same-id reload', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);
    final oldOwner = Object();
    final newOwner = Object();

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Old session',
      owner: oldOwner,
      autoplay: false,
    );
    engine.blockNextSeek();
    final blockingSeek = controller.seekStandalone(
      'dua:1',
      const Duration(seconds: 5),
      owner: oldOwner,
    );
    await engine.nextSeekStarted.future;
    final queuedToggle = controller.toggleStandaloneRepeat(
      'dua:1',
      owner: oldOwner,
    );
    final reload = controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'New session',
      owner: newOwner,
      autoplay: false,
    );
    engine.releaseBlockedSeek();
    await Future.wait(<Future<void>>[blockingSeek, queuedToggle, reload]);

    expect(controller.state.standalone?.mediaItem.title, 'New session');
    expect(controller.state.standalone?.repeatEnabled, isFalse);
    expect(engine.loopMode, LoopMode.off);
  });
}

const _playbackTrack = AudioTrack(
  id: 'track-1',
  recitationId: 'recitation-1',
  surah: 1,
  url: 'https://media.example.test/quran/1.mp3',
  duration: Duration(minutes: 1),
  offlineDownloadAllowed: false,
);

const _playback = SurahPlayback(
  track: _playbackTrack,
  segments: <AudioSegment>[],
);

const _secondPlayback = SurahPlayback(
  track: AudioTrack(
    id: 'track-2',
    recitationId: 'recitation-1',
    surah: 2,
    url: 'https://media.example.test/quran/2.mp3',
    duration: Duration(minutes: 90),
    offlineDownloadAllowed: false,
  ),
  segments: <AudioSegment>[],
);

const _reciter = Reciter(
  id: 'reciter-1',
  slug: 'reciter',
  nameAr: 'قارئ',
  nameEn: 'Reader',
  nameRu: 'Чтец',
  nameTr: 'Okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

class _FakeAudioEngine implements IqroAudioEngine {
  final sources = <AudioSource>[];
  final seekCalls = <Duration>[];
  var speed = 1.0;
  var loopMode = LoopMode.off;
  var stopCalls = 0;
  var playCalls = 0;
  var pauseCalls = 0;
  var clearCalls = 0;
  var disposeCalls = 0;
  var disposed = false;
  Object? nextSourceError;
  Completer<void>? _blockedSource;
  Completer<void> nextSourceStarted = Completer<void>();
  Completer<void>? _blockedSeek;
  Completer<void> nextSeekStarted = Completer<void>();

  void blockNextSource() {
    _blockedSource = Completer<void>();
    nextSourceStarted = Completer<void>();
  }

  void releaseBlockedSource() {
    final blocked = _blockedSource;
    if (blocked != null && !blocked.isCompleted) blocked.complete();
  }

  void blockNextSeek() {
    _blockedSeek = Completer<void>();
    nextSeekStarted = Completer<void>();
  }

  void releaseBlockedSeek() {
    final blocked = _blockedSeek;
    if (blocked != null && !blocked.isCompleted) blocked.complete();
  }

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();
  @override
  Stream<PlayerException> get errorStream =>
      const Stream<PlayerException>.empty();
  @override
  Stream<PlayerState> get playerStateStream =>
      const Stream<PlayerState>.empty();
  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.ready;

  @override
  Future<void> clearAudioSources() async {
    clearCalls += 1;
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    disposed = true;
    releaseBlockedSource();
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    playing = false;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    playing = true;
  }

  @override
  Future<void> seek(Duration position) async {
    if (!nextSeekStarted.isCompleted) nextSeekStarted.complete();
    final blocked = _blockedSeek;
    if (blocked != null) {
      await blocked.future;
      if (identical(_blockedSeek, blocked)) _blockedSeek = null;
    }
    seekCalls.add(position);
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    sources.add(source);
    final blocked = _blockedSource;
    if (!nextSourceStarted.isCompleted) nextSourceStarted.complete();
    if (blocked != null) {
      await blocked.future;
      if (identical(_blockedSource, blocked)) _blockedSource = null;
    }
    final error = nextSourceError;
    nextSourceError = null;
    if (error != null) throw error;
    processingState = ProcessingState.ready;
    return const Duration(minutes: 1);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async => loopMode = mode;

  @override
  Future<void> setSpeed(double value) async => speed = value;

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playing = false;
    processingState = ProcessingState.idle;
  }
}

Future<LocalDatabase> _audioStoreDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('''
    CREATE TABLE app_state (
      state_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  return LocalDatabase.forTesting(database);
}

class _ControlledPlaybackStore extends AudioPlaybackStore {
  _ControlledPlaybackStore(super.database);

  final clearStarted = Completer<void>();
  final _clearGate = Completer<void>();

  @override
  Future<AudioPlaybackSnapshot?> read() async =>
      throw const FormatException('corrupt');

  @override
  Future<void> clear() async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await _clearGate.future;
  }

  @override
  Future<void> write(AudioPlaybackSnapshot snapshot) async {}

  void releaseClear() {
    if (!_clearGate.isCompleted) _clearGate.complete();
  }
}
