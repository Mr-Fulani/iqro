import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/quran/surah_open_reporter.dart';
import 'package:iqro_mobile/features/settings/analytics_consent.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AnalyticsBackend {
  final calls = <String>[];
  final events = <List<Object>>[];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async =>
      events.add(<Object>[name, parameters]);
}

Future<PreferencesStore> _store([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return PreferencesStore(await SharedPreferences.getInstance());
}

const _reciter = Reciter(
  id: 'r1',
  slug: 'alafasy',
  nameAr: 'مشاري العفاسي',
  nameEn: 'Mishary Alafasy',
  nameRu: 'Мишари Афаси',
  nameTr: 'Mişari Afasi',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('firebaseOptionsFor', () {
    test('a build without IDs has no Firebase app', () {
      expect(firebaseOptionsFor(TargetPlatform.android), isNull);
      expect(
        firebaseOptionsFor(
          TargetPlatform.android,
          projectId: 'iqro',
          senderId: '1',
          androidAppId: '',
          androidApiKey: 'key',
        ),
        isNull,
      );
    });

    test('each platform gets its own app', () {
      (String, String, String?) options(TargetPlatform platform) {
        final value = firebaseOptionsFor(
          platform,
          projectId: 'iqro',
          senderId: '42',
          androidAppId: 'android-app',
          androidApiKey: 'android-key',
          iosAppId: 'ios-app',
          iosApiKey: 'ios-key',
        )!;
        return (value.appId, value.apiKey, value.iosBundleId);
      }

      expect(options(TargetPlatform.android), (
        'android-app',
        'android-key',
        null,
      ));
      expect(options(TargetPlatform.iOS), (
        'ios-app',
        'ios-key',
        'forum.iqro.app',
      ));
    });
  });

  group('AnalyticsController', () {
    test('drops events until the user accepts', () async {
      final backend = _FakeBackend();
      final store = await _store();
      final controller = AnalyticsController(store, backend);
      expect(controller.available, isTrue);
      expect(controller.state, isNull);

      controller.track(AnalyticsEvent.surahOpen, {'surah': 2});
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, isEmpty);
      expect(backend.calls, isEmpty);

      await controller.setConsent(AnalyticsConsent.granted);
      controller.track(AnalyticsEvent.share, {
        'content_type': 'ayah',
        'method': 'native',
      });
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, ['enable']);
      expect(backend.events, [
        [
          'share',
          {'content_type': 'ayah', 'method': 'native'},
        ],
      ]);
      expect(store.analyticsConsent, 'granted');
    });

    test('withdrawing stops collection and further events', () async {
      final backend = _FakeBackend();
      final controller = AnalyticsController(
        await _store({'iqro_analytics_consent_v1': 'granted'}),
        backend,
      );
      expect(controller.state, AnalyticsConsent.granted);

      await controller.setConsent(AnalyticsConsent.denied);
      controller.track(AnalyticsEvent.login, {'method': 'email'});
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, ['enable', 'disable']);
      expect(backend.events, isEmpty);
    });

    test('a build without Firebase ignores any stored choice', () async {
      final controller = AnalyticsController.disabled();
      expect(controller.available, isFalse);
      expect(controller.state, isNull);
      controller.track(AnalyticsEvent.login, {'method': 'email'});
    });

    test('event names match the site', () {
      expect(AnalyticsEvent.values.map((event) => event.id), [
        'surah_open',
        'audio_play',
        'lesson_complete',
        'share',
        'login',
      ]);
    });
  });

  test('audio_play tells a surah, one ayah and a range apart', () {
    const track = AudioTrack(
      id: 't',
      recitationId: 'r1',
      surah: 18,
      url: 'https://example.com/18.mp3',
      duration: Duration(minutes: 30),
      offlineDownloadAllowed: false,
    );
    Map<String, Object> parameters({int? start, int? end}) =>
        audioPlayParameters(
          IqroAudioState(
            track: track,
            reciter: _reciter,
            rangeStartAyah: start,
            rangeEndAyah: end,
          ),
          locale: 'ru',
        );

    expect(parameters(), {
      'kind': 'surah',
      'surah': 18,
      'reciter': 'Мишари Афаси',
    });
    expect(parameters(start: 10, end: 10)['kind'], 'ayah');
    expect(parameters(start: 1, end: 10)['kind'], 'range');
  });

  group('consent card', () {
    Future<(_FakeBackend, PreferencesStore)> pump(
      WidgetTester tester, {
      bool configured = true,
    }) async {
      final backend = _FakeBackend();
      final store = await _store();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            preferencesStoreProvider.overrideWithValue(store),
            analyticsBackendProvider.overrideWithValue(
              configured ? backend : null,
            ),
          ],
          child: MaterialApp(
            theme: IqroTheme.light(),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Column(
                children: <Widget>[
                  AnalyticsConsentCard(),
                  AnalyticsConsentTile(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (backend, store);
    }

    testWidgets('asks once and remembers the answer', (tester) async {
      final (backend, store) = await pump(tester);
      expect(find.byKey(const ValueKey('analytics-consent')), findsOneWidget);
      expect(
        find.text(
          'Вы ещё не выбрали. Пока выбора нет, Google Analytics выключен.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Принять'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analytics-consent')), findsNothing);
      expect(store.analyticsConsent, 'granted');
      expect(backend.calls, ['enable']);
      expect(
        find.text(
          'Вы разрешили статистику: Google Analytics включён на этом устройстве.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('analytics-consent-setting')));
      await tester.pumpAndSettle();
      expect(store.analyticsConsent, 'denied');
      expect(backend.calls, ['enable', 'disable']);
    });

    testWidgets('declining hides the card and starts nothing', (tester) async {
      final (backend, store) = await pump(tester);
      await tester.tap(find.text('Отклонить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analytics-consent')), findsNothing);
      expect(store.analyticsConsent, 'denied');
      expect(backend.calls, isNot(contains('enable')));
    });

    testWidgets('builds without Firebase never ask', (tester) async {
      await pump(tester, configured: false);
      expect(find.byKey(const ValueKey('analytics-consent')), findsNothing);
    });
  });

  testWidgets('surah_open waits three seconds and reports a surah once', (
    tester,
  ) async {
    final backend = _FakeBackend();
    final store = await _store({'iqro_analytics_consent_v1': 'granted'});
    Widget reader(int surah) => ProviderScope(
      overrides: <Override>[
        preferencesStoreProvider.overrideWithValue(store),
        analyticsBackendProvider.overrideWithValue(backend),
      ],
      child: SurahOpenReporter(surah: surah),
    );

    await tester.pumpWidget(reader(1));
    await tester.pump(const Duration(seconds: 2));
    // Paged on before three seconds: surah 1 does not count.
    await tester.pumpWidget(reader(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(reader(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(reader(2));
    await tester.pump(const Duration(seconds: 3));

    expect(backend.events, [
      [
        'surah_open',
        {'surah': 2},
      ],
      [
        'surah_open',
        {'surah': 1},
      ],
    ]);
  });
}
