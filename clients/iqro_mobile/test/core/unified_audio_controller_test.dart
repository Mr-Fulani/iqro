import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/audio/audio_playback_store.dart';
import 'package:iqro_mobile/core/audio/listening_media_service.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/listening_queue.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'a standalone clip plays only its part at the requested speed',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadStandalone(
        id: 'tajweed:1',
        url: 'https://media.example.test/112.mp3',
        title: 'يَكُن',
        contentType: 'tajweed',
        speed: .75,
        clipStart: const Duration(milliseconds: 9600),
        clipEnd: const Duration(milliseconds: 10100),
      );

      final source = engine.sources.single as ClippingAudioSource;
      expect(source.child.uri, Uri.parse('https://media.example.test/112.mp3'));
      expect(source.start, const Duration(milliseconds: 9600));
      expect(source.end, const Duration(milliseconds: 10100));
      expect(source.duration, const Duration(milliseconds: 500));
      expect(engine.speed, .75);
      expect(controller.state.standalone?.speed, .75);
      expect(controller.state.standalone?.playing, isTrue);

      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
      );
      expect(engine.sources.last, isA<UriAudioSource>());
      expect(engine.speed, 1);
    },
  );

  test('memorization playback is not exposed as primary audio playback', () {
    expect(
      isPrimaryAudioPlayback(IqroAudioState(track: _playbackTrack)),
      isTrue,
    );
    expect(
      isPrimaryAudioPlayback(
        IqroAudioState(
          track: _playbackTrack,
          source: AudioPlaybackSource.memorization,
        ),
      ),
      isFalse,
    );
  });

  test('audio presentation ignores timeline-only position updates', () {
    final current = IqroAudioState(
      track: _playback.track,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
      playing: true,
      duration: const Duration(minutes: 1),
      position: const Duration(seconds: 10),
    );

    expect(
      iqroAudioPresentation(
        current.copyWith(position: const Duration(seconds: 11)),
      ),
      iqroAudioPresentation(current),
    );
    expect(
      iqroAudioPresentation(current.copyWith(buffering: true)),
      isNot(iqroAudioPresentation(current)),
    );
  });

  test(
    'audio presentation exposes standalone playback without timeline churn',
    () {
      final standalone = IqroStandaloneAudioState(
        uri: Uri.https('media.example.test', '/dua/1.mp3'),
        mediaItem: buildIqroStandaloneMediaItem(
          id: 'dua:1',
          title: 'Morning remembrance',
          album: 'IQRO · Dua',
          artist: 'Reader',
          contentType: 'dua',
        ),
        playing: true,
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 1),
      );
      final current = IqroAudioState(standalone: standalone);
      final presentation = iqroAudioPresentation(current);

      expect(presentation.standalone, (
        id: 'dua:1',
        title: 'Morning remembrance',
        artist: 'Reader',
        album: 'IQRO · Dua',
        contentType: 'dua',
      ));
      expect(presentation.playing, isTrue);
      expect(presentation.buffering, isFalse);
      expect(
        iqroAudioPresentation(
          current.copyWith(
            standalone: standalone.copyWith(
              position: const Duration(seconds: 11),
            ),
          ),
        ),
        presentation,
      );
    },
  );

  test(
    'entering Quran pauses Quran playback without clearing its track',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      expect(controller.state.playing, isTrue);

      await controller.pauseForQuranEntry();

      expect(engine.pauseCalls, 1);
      expect(engine.playing, isFalse);
      expect(controller.state.playing, isFalse);
      expect(controller.state.buffering, isFalse);
      expect(controller.state.track?.id, _playback.track.id);
      await controller.pauseForQuranEntry();
      expect(engine.pauseCalls, 1);
    },
  );

  test(
    'entering Quran pauses memorization playback without clearing its track',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _memorizationReciter,
        source: AudioPlaybackSource.memorization,
        surahName: 'Memorization Al-Baqarah',
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      expect(controller.state.playing, isTrue);
      expect(controller.state.channel, AudioPlaybackChannel.memorization);

      await controller.pauseForQuranEntry();

      expect(engine.pauseCalls, 1);
      expect(engine.playing, isFalse);
      expect(controller.state.playing, isFalse);
      expect(controller.state.track?.id, _secondPlayback.track.id);
      expect(controller.state.channel, AudioPlaybackChannel.memorization);
    },
  );

  test('moving within Quran keeps its own Mushaf playback', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      channel: AudioPlaybackChannel.mushaf,
      surahName: 'Al-Fatiha',
    );
    engine.emitPlayerState(PlayerState(true, ProcessingState.ready));

    await controller.pauseForQuranEntry();

    expect(engine.pauseCalls, 0);
    expect(controller.state.playing, isTrue);
    expect(controller.state.channel, AudioPlaybackChannel.mushaf);
  });

  test(
    'entering Quran pauses standalone playback without clearing its item',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadStandalone(
        id: 'standalone:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
      );
      expect(controller.state.standalone?.playing, isTrue);

      await controller.pauseForQuranEntry();

      expect(engine.pauseCalls, 1);
      expect(engine.playing, isFalse);
      expect(controller.state.standalone?.playing, isFalse);
      expect(controller.state.standalone?.mediaItem.id, 'standalone:1');
    },
  );

  test(
    'entering Dua pauses Quran playback without clearing its track',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));

      await controller.pauseForDuaEntry();

      expect(engine.pauseCalls, 1);
      expect(engine.playing, isFalse);
      expect(controller.state.playing, isFalse);
      expect(controller.state.track?.id, _playback.track.id);
    },
  );

  test('a lesson video pauses Quran reading and keeps its track', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Al-Fatiha',
    );
    engine.emitPlayerState(PlayerState(true, ProcessingState.ready));

    await controller.pauseForLessonVideo();

    expect(engine.pauseCalls, 1);
    expect(controller.state.playing, isFalse);
    expect(controller.state.track?.id, _playback.track.id);
  });

  test('a lesson video pauses Dua and prayer audio too', () async {
    for (final type in ['dua', 'salah']) {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadStandalone(
        id: '$type:1',
        url: 'https://media.example.test/$type/1.mp3',
        title: 'Morning remembrance',
        contentType: type,
      );
      expect(controller.state.standalone?.playing, isTrue);

      await controller.pauseForLessonVideo();

      expect(engine.pauseCalls, 1, reason: type);
      expect(controller.state.standalone?.playing, isFalse, reason: type);
      expect(controller.state.standalone?.mediaItem.id, '$type:1');
    }
  });

  test('entering Dua preserves a currently playing Dua source', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      contentType: 'dua',
    );
    expect(controller.state.standalone?.playing, isTrue);

    await controller.pauseForDuaEntry();

    expect(engine.pauseCalls, 0);
    expect(engine.playing, isTrue);
    expect(controller.state.standalone?.playing, isTrue);
    expect(controller.state.standalone?.mediaItem.id, 'dua:1');
  });

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
    'a Dua speed belongs to its owner and the next item starts at 1x',
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

      await controller.setStandaloneSpeed('dua:1', 1.5);
      expect(controller.state.standalone?.speed, 1);

      await controller.setStandaloneSpeed('dua:1', 1.5, owner: owner);
      expect(controller.state.standalone?.speed, 1.5);
      expect(engine.speed, 1.5);

      await controller.loadStandalone(
        id: 'dua:2',
        url: 'https://media.example.test/dua/2.mp3',
        title: 'Next',
        owner: owner,
        autoplay: false,
      );
      expect(controller.state.standalone?.speed, 1);
      expect(engine.speed, 1);
    },
  );

  test('global player can toggle the current route-owned Dua source', () async {
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);
    final owner = Object();

    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      contentType: 'dua',
      owner: owner,
      autoplay: false,
    );

    await controller.toggleStandaloneFromGlobalPlayer('dua:1');
    expect(engine.playCalls, 1);
    expect(controller.state.standalone?.playing, isTrue);

    await controller.toggleStandaloneFromGlobalPlayer('old-dua:1');
    expect(engine.pauseCalls, 0);
    expect(controller.state.standalone?.playing, isTrue);

    await controller.toggleStandaloneFromGlobalPlayer('dua:1');
    expect(engine.pauseCalls, 1);
    expect(controller.state.standalone?.playing, isFalse);
  });

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

  test(
    'memorization playback does not replace or clear the regular audio snapshot',
    () async {
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
      final controller = AudioController(
        engine: _FakeAudioEngine(),
        playbackStore: store,
      );
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _memorizationReciter,
        source: AudioPlaybackSource.memorization,
        surahName: 'Memorization Al-Baqarah',
        autoplay: false,
      );

      expect(controller.state.source, AudioPlaybackSource.memorization);
      expect((await store.read())?.playback.track.id, 'track-1');

      await controller.stop();

      expect(await store.read(), isNotNull);
    },
  );

  test('audio presentation is stable across position ticks', () {
    final playing = const IqroAudioState().copyWith(
      track: _playbackTrack,
      reciter: _reciter,
      surahName: 'Audio Al-Fatiha',
      playing: true,
      position: const Duration(seconds: 1),
    );

    // Home and the mini player select this presentation; equality across
    // position ticks is what keeps them from rebuilding during playback.
    expect(
      iqroAudioPresentation(
        playing.copyWith(position: const Duration(seconds: 2), activeAyah: 2),
      ),
      iqroAudioPresentation(playing),
    );
    expect(
      iqroAudioPresentation(playing.copyWith(playing: false)),
      isNot(iqroAudioPresentation(playing)),
    );
  });

  test(
    'listening position is saved while position ticks keep arriving',
    () async {
      final database = await _audioStoreDatabase();
      addTearDown(database.close);
      final store = AudioPlaybackStore(database);
      final engine = _FakeAudioEngine();
      final controller = AudioController(
        engine: engine,
        playbackStore: store,
        persistenceDelay: const Duration(milliseconds: 40),
      );
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Audio Al-Fatiha',
        autoplay: false,
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));

      // Ticks arrive far more often than the persistence delay, as they do from
      // just_audio during playback; a debounce would never save the position.
      for (var tick = 1; tick <= 20; tick += 1) {
        engine.emitPosition(Duration(milliseconds: tick * 500));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final saved = await store.read();
      expect(saved?.playback.track.id, _playback.track.id);
      expect(saved!.position, greaterThan(Duration.zero));
    },
  );

  test(
    'leaving memorization restores the paused regular audio track',
    () async {
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
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine, playbackStore: store);
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _memorizationReciter,
        source: AudioPlaybackSource.memorization,
        surahName: 'Memorization Al-Baqarah',
        autoplay: false,
      );
      await controller.restoreAudioAfterMemorization();

      expect(controller.state.source, AudioPlaybackSource.audio);
      expect(controller.state.track?.id, 'track-1');
      expect(controller.state.reciter?.id, _reciter.id);
      expect(controller.state.playing, isFalse);
      expect(controller.state.position, const Duration(seconds: 25));
      expect(engine.pauseCalls, 1);
      expect((await store.read())?.reciter.id, _reciter.id);
    },
  );

  test(
    'leaving memorization restores an in-memory listening snapshot without a store',
    () async {
      final controller = AudioController(engine: _FakeAudioEngine());
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Audio Al-Fatiha',
        autoplay: false,
      );
      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _reciter,
        source: AudioPlaybackSource.memorization,
        surahName: 'Memorization Al-Baqarah',
        autoplay: false,
      );

      await controller.restoreAudioAfterMemorization();

      expect(controller.state.channel, AudioPlaybackChannel.listening);
      expect(controller.state.track?.id, 'track-1');
      expect(controller.state.surahName, 'Audio Al-Fatiha');
      expect(controller.state.playing, isFalse);
    },
  );

  test(
    'leaving memorization cancels a queued load before it replaces listening',
    () async {
      final controller = AudioController(engine: _FakeAudioEngine());
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Audio Al-Fatiha',
        autoplay: false,
      );
      final memorizationLoad = controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _reciter,
        source: AudioPlaybackSource.memorization,
        surahName: 'Memorization Al-Baqarah',
        autoplay: false,
      );
      final restore = controller.restoreAudioAfterMemorization();

      await Future.wait(<Future<void>>[memorizationLoad, restore]);

      expect(controller.state.channel, AudioPlaybackChannel.listening);
      expect(controller.state.track?.id, 'track-1');
      expect(controller.state.surahName, 'Audio Al-Fatiha');
    },
  );

  test('Audio can resume its saved reader after Mushaf playback', () async {
    final database = await _audioStoreDatabase();
    addTearDown(database.close);
    final store = AudioPlaybackStore(database);
    final engine = _FakeAudioEngine();
    final controller = AudioController(engine: engine, playbackStore: store);
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Audio Al-Fatiha',
      autoplay: false,
    );
    await controller.loadPlayback(
      playback: _secondPlayback,
      reciter: _memorizationReciter,
      channel: AudioPlaybackChannel.mushaf,
      surahName: 'Mushaf Al-Baqarah',
      autoplay: false,
    );
    expect((await store.read())?.reciter.id, _reciter.id);
    expect(controller.listeningSurah, 1);

    await controller.restoreLatestIfIdle();
    expect(controller.state.channel, AudioPlaybackChannel.mushaf);

    expect(await controller.activateListening(), isTrue);
    expect(controller.state.channel, AudioPlaybackChannel.listening);
    expect(controller.state.reciter?.id, _reciter.id);
    expect(controller.state.track?.id, _playback.track.id);
    expect((await store.read())?.reciter.id, _reciter.id);
  });

  test('Dua handoff retains the saved Audio session', () async {
    final database = await _audioStoreDatabase();
    addTearDown(database.close);
    final store = AudioPlaybackStore(database);
    final controller = AudioController(
      engine: _FakeAudioEngine(),
      playbackStore: store,
    );
    addTearDown(controller.dispose);

    await controller.loadPlayback(
      playback: _playback,
      reciter: _reciter,
      surahName: 'Audio Al-Fatiha',
      autoplay: false,
    );
    await controller.loadStandalone(
      id: 'dua:1',
      url: 'https://media.example.test/dua/1.mp3',
      title: 'Morning remembrance',
      contentType: 'dua',
      autoplay: false,
    );
    expect((await store.read())?.playback.track.id, _playback.track.id);

    expect(await controller.activateListening(), isTrue);
    expect(controller.state.standalone, isNull);
    expect(controller.state.track?.id, _playback.track.id);
    expect((await store.read())?.playback.track.id, _playback.track.id);
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
        ..nextSourceError = const FormatException(
          'decoder temporarily unavailable',
        );
      final controller = AudioController(engine: engine, playbackStore: store);
      addTearDown(controller.dispose);

      await controller.restore();

      expect(await store.read(), isNotNull);
      expect(
        controller.state.error,
        contains('decoder temporarily unavailable'),
      );
    },
  );

  test(
    'restore clears invalid ranges before loading an audio source',
    () async {
      final cases =
          <
            ({
              String name,
              SurahPlayback playback,
              int? startAyah,
              int? endAyah,
            })
          >[
            (
              name: 'missing end boundary',
              playback: _rangedPlayback,
              startAyah: 1,
              endAyah: null,
            ),
            (
              name: 'missing start boundary',
              playback: _rangedPlayback,
              startAyah: null,
              endAyah: 2,
            ),
            (
              name: 'reversed boundaries',
              playback: _rangedPlayback,
              startAyah: 3,
              endAyah: 1,
            ),
            (
              name: 'non-chronological timings',
              playback: _nonChronologicalPlayback,
              startAyah: 1,
              endAyah: 2,
            ),
          ];

      for (final invalidCase in cases) {
        final database = await _audioStoreDatabase();
        final store = AudioPlaybackStore(database);
        await store.write(
          AudioPlaybackSnapshot(
            playback: invalidCase.playback,
            reciter: _reciter,
            surahName: 'Saved range',
            position: Duration.zero,
            speed: 1,
            repeatEnabled: false,
            rangeStartAyah: invalidCase.startAyah,
            rangeEndAyah: invalidCase.endAyah,
            savedAt: DateTime.utc(2026, 9, 3),
          ),
        );
        final engine = _FakeAudioEngine();
        final controller = AudioController(
          engine: engine,
          playbackStore: store,
        );

        await controller.restore();

        expect(engine.sources, isEmpty, reason: invalidCase.name);
        expect(await store.read(), isNull, reason: invalidCase.name);
        controller.dispose();
        await database.close();
      }
    },
  );

  test('a stale completion cannot pause a newer pending source', () async {
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
    final newerLoad = controller.loadPlayback(
      playback: _secondPlayback,
      reciter: _reciter,
      surahName: 'Al-Baqarah',
    );
    await engine.nextSourceStarted.future;

    engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
    engine.releaseBlockedSource();
    await newerLoad;
    await pumpEventQueue(times: 5);

    expect(controller.state.track?.id, 'track-2');
    expect(engine.processingState, ProcessingState.ready);
    expect(engine.pauseCalls, 0);
    expect(engine.playCalls, 1);
  });

  test(
    'external playback after terminal standalone stop is rejected',
    () async {
      final engine = _FakeAudioEngine();
      final controller = AudioController(engine: engine);
      addTearDown(controller.dispose);

      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
        autoplay: false,
      );
      await controller.stopStandalone('dua:1');
      expect(controller.state.anyAudioActive, isFalse);
      expect(engine.clearCalls, 1);

      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue(times: 5);

      expect(controller.state.anyAudioActive, isFalse);
      expect(engine.playing, isFalse);
      expect(engine.pauseCalls, 1);
      expect(engine.clearCalls, 2);
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

  group('listening queue', () {
    test(
      'a surah that ends plays the next held one from the prefetch',
      () async {
        final queue = _FakeQueueSource(<int>[1, 36]);
        final engine = _FakeAudioEngine();
        final controller = AudioController(
          engine: engine,
          queueSource: queue.source,
        );
        addTearDown(controller.dispose);

        await controller.loadPlayback(
          playback: _playback,
          reciter: _reciter,
          surahName: 'Al-Fatiha',
        );
        expect(queue.entryRequests, isEmpty);
        engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
        await pumpEventQueue();
        expect(queue.entryRequests, <int>[36]);
        final stops = engine.stopCalls;

        engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
        await pumpEventQueue();

        expect(controller.state.channel, AudioPlaybackChannel.listening);
        expect(controller.state.track?.id, 'track-36');
        expect(controller.state.surahName, 'Surah 36');
        expect(controller.state.reciter?.id, _reciter.id);
        expect(engine.playCalls, 2);
        // The platform player is kept: no stop, and no request at the end.
        expect(engine.stopCalls, stops);
        expect(queue.entryRequests, <int>[36]);
      },
    );

    test('the last surah ends playback in the next mode, '
        'and starts the queue again in the loop mode', () async {
      final queue = _FakeQueueSource(<int>[1]);
      final engine = _FakeAudioEngine();
      final controller = AudioController(
        engine: engine,
        queueSource: queue.source,
      );
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();
      engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
      await pumpEventQueue();

      expect(engine.pauseCalls, 1);
      expect(engine.sources, hasLength(1));
      expect(queue.entryRequests, isEmpty);

      controller.setQueueMode(ListeningQueueMode.loop);
      await controller.toggle();
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();
      engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
      await pumpEventQueue();

      expect(queue.entryRequests, <int>[1]);
      expect(engine.sources, hasLength(2));
      expect(controller.state.track?.id, 'track-1');
      expect(engine.playing, isTrue);
    });

    test('the stop mode, repeat and other sections never move on', () async {
      final queue = _FakeQueueSource(<int>[1, 2]);
      final engine = _FakeAudioEngine();
      final controller = AudioController(
        engine: engine,
        queueSource: queue.source,
      );
      addTearDown(controller.dispose);
      Future<void> playToEnd() async {
        engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
        await pumpEventQueue();
        engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
        await pumpEventQueue();
      }

      controller.setQueueMode(ListeningQueueMode.stop);
      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
      );
      await playToEnd();
      expect(controller.state.track?.id, 'track-1');
      expect(engine.pauseCalls, 1);

      controller.setQueueMode(ListeningQueueMode.next);
      await controller.toggleRepeat();
      await playToEnd();
      expect(controller.state.track?.id, 'track-1');

      await controller.toggleRepeat();
      for (final channel in <AudioPlaybackChannel>[
        AudioPlaybackChannel.mushaf,
        AudioPlaybackChannel.memorization,
      ]) {
        await controller.loadPlayback(
          playback: _playback,
          reciter: _reciter,
          channel: channel,
          surahName: 'Al-Fatiha',
        );
        await playToEnd();
        expect(controller.state.track?.id, 'track-1');
        expect(controller.state.channel, channel);
      }
      expect(queue.entryRequests, isEmpty);
      expect(engine.sources, hasLength(3));
    });

    test('a surah not asked for yet is asked for at the end, '
        'unless the listener moved on meanwhile', () async {
      final queue = _FakeQueueSource(<int>[1, 36])..gate = Completer<void>();
      final engine = _FakeAudioEngine();
      final controller = AudioController(
        engine: engine,
        queueSource: queue.source,
      );
      addTearDown(controller.dispose);

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
      );
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
      await pumpEventQueue();
      // The finished surah pauses while the next one is on its way.
      expect(engine.pauseCalls, 1);
      expect(queue.entryRequests, <int>[36, 36]);

      queue.gate!.complete();
      await pumpEventQueue();
      expect(controller.state.track?.id, 'track-36');
      expect(engine.playing, isTrue);

      queue.gate = Completer<void>();
      queue.held = <int>[1, 36, 37];
      engine.emitPlayerState(PlayerState(true, ProcessingState.completed));
      await pumpEventQueue();
      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _reciter,
        surahName: 'Al-Baqarah',
      );
      queue.gate!.complete();
      await pumpEventQueue();

      expect(controller.state.track?.id, 'track-2');
    });

    test('the queue mode is kept with the listening snapshot', () async {
      final database = await _audioStoreDatabase();
      addTearDown(database.close);
      final store = AudioPlaybackStore(database);
      final first = AudioController(
        engine: _FakeAudioEngine(),
        playbackStore: store,
      );

      await first.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );
      first.setQueueMode(ListeningQueueMode.loop);
      await pumpEventQueue();
      expect((await store.read())?.queueMode, ListeningQueueMode.loop);
      first.dispose();
      await pumpEventQueue();

      final second = AudioController(
        engine: _FakeAudioEngine(),
        playbackStore: store,
      );
      addTearDown(second.dispose);
      await second.restore();
      expect(second.state.track?.id, 'track-1');
      expect(second.state.queueMode, ListeningQueueMode.loop);

      // A snapshot from before the queue keeps the default.
      await store.write(
        AudioPlaybackSnapshot(
          playback: _playback,
          reciter: _reciter,
          surahName: 'Al-Fatiha',
          position: Duration.zero,
          speed: 1,
          repeatEnabled: false,
          savedAt: DateTime.utc(2026, 10, 25),
        ),
      );
      final third = AudioController(
        engine: _FakeAudioEngine(),
        playbackStore: store,
      );
      addTearDown(third.dispose);
      await third.restore();
      expect(third.state.track?.id, 'track-1');
      expect(third.state.queueMode, ListeningQueueMode.next);
    });

    test('the lock screen switches listening surahs, '
        'and offers no surah buttons for another section', () async {
      final media = ListeningMediaService();
      final queue = _FakeQueueSource(<int>[1, 36]);
      final engine = _FakeAudioEngine();
      final controller = AudioController(
        engine: engine,
        mediaService: media,
        queueSource: queue.source,
      );
      addTearDown(controller.dispose);
      List<MediaAction> controls() => media.playbackState.value.controls
          .map((control) => control.action)
          .toList();

      await controller.loadPlayback(
        playback: _playback,
        reciter: _reciter,
        surahName: 'Al-Fatiha',
        autoplay: false,
      );
      expect(controls(), <MediaAction>[
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.skipToNext,
      ]);
      expect(media.playbackState.value.androidCompactActionIndices, <int>[
        0,
        1,
        2,
      ]);

      await media.skipToPrevious();
      expect(controller.state.track?.id, 'track-1');
      await media.skipToNext();
      expect(controller.state.track?.id, 'track-36');
      expect(engine.playing, isTrue);
      await media.skipToNext();
      expect(controller.state.track?.id, 'track-36');
      controller.setQueueMode(ListeningQueueMode.loop);
      await media.skipToNext();
      expect(controller.state.track?.id, 'track-1');

      await controller.loadPlayback(
        playback: _secondPlayback,
        reciter: _reciter,
        channel: AudioPlaybackChannel.mushaf,
        surahName: 'Al-Baqarah',
        autoplay: false,
      );
      expect(controls(), <MediaAction>[MediaAction.play]);
      await media.skipToNext();
      expect(controller.state.track?.id, 'track-2');
      expect(controller.state.channel, AudioPlaybackChannel.mushaf);
    });
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

const _rangedPlayback = SurahPlayback(
  track: _playbackTrack,
  segments: <AudioSegment>[
    AudioSegment(
      ayahId: 'ayah-1',
      surah: 1,
      ayah: 1,
      start: Duration.zero,
      end: Duration(seconds: 10),
    ),
    AudioSegment(
      ayahId: 'ayah-2',
      surah: 1,
      ayah: 2,
      start: Duration(seconds: 10),
      end: Duration(seconds: 20),
    ),
    AudioSegment(
      ayahId: 'ayah-3',
      surah: 1,
      ayah: 3,
      start: Duration(seconds: 20),
      end: Duration(seconds: 30),
    ),
  ],
);

const _nonChronologicalPlayback = SurahPlayback(
  track: _playbackTrack,
  segments: <AudioSegment>[
    AudioSegment(
      ayahId: 'ayah-1',
      surah: 1,
      ayah: 1,
      start: Duration(seconds: 20),
      end: Duration(seconds: 30),
    ),
    AudioSegment(
      ayahId: 'ayah-2',
      surah: 1,
      ayah: 2,
      start: Duration.zero,
      end: Duration(seconds: 10),
    ),
  ],
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

const _memorizationReciter = Reciter(
  id: 'reciter-2',
  slug: 'memorization-reciter',
  nameAr: 'قارئ الحفظ',
  nameEn: 'Memorization Reader',
  nameRu: 'Чтец для заучивания',
  nameTr: 'Ezber okuyucusu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

class _FakeQueueSource {
  _FakeQueueSource(this.held);

  List<int> held;
  final entryRequests = <int>[];

  /// Holds every surah request until completed.
  Completer<void>? gate;

  late final source = ListeningQueueSource(
    heldSurahs: (_) async => held,
    entry: (recitationId, surah) async {
      entryRequests.add(surah);
      await gate?.future;
      return (
        playback: SurahPlayback(
          track: AudioTrack(
            id: 'track-$surah',
            recitationId: recitationId,
            surah: surah,
            url: 'https://media.example.test/quran/$surah.mp3',
            duration: const Duration(minutes: 1),
            offlineDownloadAllowed: false,
          ),
          segments: const <AudioSegment>[],
        ),
        surahName: 'Surah $surah',
      );
    },
  );
}

class _FakeAudioEngine implements IqroAudioEngine {
  final _playerStates = StreamController<PlayerState>.broadcast(sync: true);
  final _positions = StreamController<Duration>.broadcast(sync: true);
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

  void emitPlayerState(PlayerState state) {
    playing = state.playing;
    processingState = state.processingState;
    _playerStates.add(state);
  }

  void emitPosition(Duration position) => _positions.add(position);

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();
  @override
  Stream<PlayerException> get errorStream =>
      const Stream<PlayerException>.empty();
  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
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
    await _playerStates.close();
    await _positions.close();
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
      owner_id TEXT NOT NULL,
      state_key TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, state_key)
    )
  ''');
  return LocalDatabase.forTesting(database);
}

class _ControlledPlaybackStore extends AudioPlaybackStore {
  _ControlledPlaybackStore(super.database);

  final clearStarted = Completer<void>();
  final _clearGate = Completer<void>();

  @override
  Future<AudioPlaybackSnapshot?> read({
    AccountScopeSnapshot? accountScope,
  }) async => throw const FormatException('corrupt');

  @override
  Future<void> clear({AccountScopeSnapshot? accountScope}) async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await _clearGate.future;
  }

  @override
  Future<void> write(
    AudioPlaybackSnapshot snapshot, {
    AccountScopeSnapshot? accountScope,
  }) async {}

  void releaseClear() {
    if (!_clearGate.isCompleted) _clearGate.complete();
  }
}
