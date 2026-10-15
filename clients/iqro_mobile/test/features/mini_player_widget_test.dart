import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/mini_player.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  for (final locale in <String>['ru', 'en', 'ar', 'tr']) {
    testWidgets(
      'idle player opens reciter choice, not empty playback: $locale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final router = GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: IqroMiniPlayer(),
                ),
              ),
            ),
            GoRoute(
              path: '/app',
              builder: (context, state) => Scaffold(
                body: Text('tab=${state.uri.queryParameters['tab']}'),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              audioControllerProvider.overrideWith(
                (ref) => AudioController(engine: _IdleAudioEngine()),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(IqroMiniPlayer)),
        );
        expect(find.text(l10n.audioTitle), findsOneWidget);
        expect(find.text(l10n.chooseReciter), findsOneWidget);
        final collapse = find.byKey(const ValueKey('mini-player-collapse'));
        final expand = find.byKey(const ValueKey('mini-player-expand'));
        final expandedWidth = tester.getSize(find.byType(ListTile)).width;
        await tester.pumpAndSettle();
        expect(tester.getSize(expand), const Size(60, 60));
        expect(expand.hitTestable(), findsOneWidget);
        expect(collapse.hitTestable(), findsNothing);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(IqroMiniPlayer)),
        );
        expect(container.read(miniPlayerCollapsedProvider), isTrue);
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(container.read(miniPlayerCollapsedProvider), isFalse);
        expect(tester.getSize(find.byType(ListTile)).width, expandedWidth);
        expect(collapse.hitTestable(), findsOneWidget);
        expect(expand.hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(collapse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.getSize(expand), const Size(60, 60));
        expect(expand.hitTestable(), findsOneWidget);
        expect(collapse.hitTestable(), findsNothing);
        expect(container.read(miniPlayerCollapsedProvider), isTrue);
        expect(find.text('tab=3'), findsNothing);
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(container.read(miniPlayerCollapsedProvider), isFalse);
        expect(tester.getSize(find.byType(ListTile)).width, expandedWidth);
        expect(collapse.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip(l10n.play));
        await tester.pumpAndSettle();
        expect(find.text('tab=3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final channel in <AudioPlaybackChannel>[
    AudioPlaybackChannel.mushaf,
    AudioPlaybackChannel.memorization,
  ]) {
    testWidgets(
      'app-shell player restores listening instead of ${channel.name} playback',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final controller = AudioController(engine: _MiniPlayerAudioEngine());
        addTearDown(controller.dispose);
        await controller.loadPlayback(
          playback: const SurahPlayback(
            track: _miniPlayerTrack,
            segments: <AudioSegment>[],
          ),
          reciter: _miniPlayerReciter,
          surahName: 'Listening session',
          autoplay: false,
        );
        await controller.loadPlayback(
          playback: const SurahPlayback(
            track: _miniPlayerTrack,
            segments: <AudioSegment>[],
          ),
          reciter: _miniPlayerReciter,
          channel: channel,
          surahName: 'Al-Baqara',
          autoplay: false,
        );
        final router = GoRouter(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: IqroMiniPlayer(),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              audioControllerProvider.overrideWith((ref) => controller),
              appConfigProvider.overrideWithValue(
                const AppConfig(
                  apiBaseUrl: 'https://media.example.test',
                  fallbackDownloadUrl: 'https://iqro.forum',
                  environment: 'local',
                ),
              ),
              recitersProvider.overrideWith(
                (ref) async => <Reciter>[_miniPlayerReciter],
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mini-player-expand')));
        await tester.pumpAndSettle();

        expect(find.text('Al-Baqara'), findsNothing);
        expect(find.text('Listening session'), findsOneWidget);
        expect(controller.state.channel, channel);
        await tester.tap(find.byKey(const ValueKey('mini-player-play-toggle')));
        await tester.pumpAndSettle();
        expect(controller.state.channel, AudioPlaybackChannel.listening);
        expect(controller.state.surahName, 'Listening session');
        expect(controller.state.playing, isTrue);
      },
    );
  }

  testWidgets(
    'app-shell player restores listening instead of owned Dua audio',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = AudioController(engine: _MiniPlayerAudioEngine());
      addTearDown(controller.dispose);
      await controller.loadPlayback(
        playback: const SurahPlayback(
          track: _miniPlayerTrack,
          segments: <AudioSegment>[],
        ),
        reciter: _miniPlayerReciter,
        surahName: 'Listening session',
        autoplay: false,
      );
      await controller.loadStandalone(
        id: 'dua:1',
        url: 'https://media.example.test/dua/1.mp3',
        title: 'Morning remembrance',
        artist: 'Reader',
        album: 'IQRO · Dua',
        contentType: 'dua',
        owner: Object(),
      );
      final router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: IqroMiniPlayer(),
              ),
            ),
          ),
          GoRoute(
            path: '/app',
            builder: (context, state) =>
                Scaffold(body: Text('tab=${state.uri.queryParameters['tab']}')),
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) =>
                const Scaffold(body: Text('player-route')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioControllerProvider.overrideWith((ref) => controller),
            recitersProvider.overrideWith((ref) async => <Reciter>[]),
            appConfigProvider.overrideWithValue(
              const AppConfig(
                apiBaseUrl: 'https://media.example.test',
                fallbackDownloadUrl: 'https://iqro.forum',
                environment: 'local',
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mini-player-expand')));
      await tester.pumpAndSettle();

      expect(find.text('Morning remembrance'), findsNothing);
      expect(find.text('Listening session'), findsOneWidget);
      expect(controller.state.standalone?.mediaItem.id, 'dua:1');
      expect(find.text('Reader'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mini-player-play-toggle')));
      await tester.pumpAndSettle();
      expect(controller.state.standalone, isNull);
      expect(controller.state.channel, AudioPlaybackChannel.listening);
      expect(controller.state.playing, isTrue);
      expect(find.text('tab=3'), findsNothing);

      await tester.tap(find.text('Listening session'));
      await tester.pumpAndSettle();
      expect(find.text('player-route'), findsOneWidget);
      expect(controller.state.surahName, 'Listening session');
    },
  );
}

const _miniPlayerTrack = AudioTrack(
  id: 'mini-player-track',
  recitationId: 'mini-player-recitation',
  surah: 2,
  url: 'https://media.example.test/quran/2.mp3',
  duration: Duration(minutes: 1),
  offlineDownloadAllowed: false,
);

const _miniPlayerReciter = Reciter(
  id: 'mini-player-reciter',
  slug: 'mini-player-reciter',
  nameAr: 'قارئ',
  nameEn: 'Reader',
  nameRu: 'Чтец',
  nameTr: 'Okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

class _MiniPlayerAudioEngine extends _IdleAudioEngine {
  final _playerStates = StreamController<PlayerState>.broadcast(sync: true);
  @override
  var playing = false;
  @override
  var processingState = ProcessingState.idle;

  @override
  Stream<PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Future<void> dispose() => _playerStates.close();

  @override
  Future<void> clearAudioSources() async {
    processingState = ProcessingState.idle;
    _playerStates.add(PlayerState(playing, processingState));
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playerStates.add(PlayerState(playing, processingState));
  }

  @override
  Future<void> play() async {
    playing = true;
    _playerStates.add(PlayerState(playing, processingState));
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    processingState = ProcessingState.ready;
    _playerStates.add(PlayerState(playing, processingState));
    return const Duration(minutes: 1);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> seek(Duration position) async {}
}

class _IdleAudioEngine implements IqroAudioEngine {
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
