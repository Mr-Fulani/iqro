import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
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
        await tester.tap(find.byTooltip(l10n.play));
        await tester.pumpAndSettle();
        expect(find.text('tab=3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
