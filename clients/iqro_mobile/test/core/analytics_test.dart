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

  group('reminder after a refusal', () {
    var now = DateTime(2026, 11, 21, 9);
    setUp(() => now = DateTime(2026, 11, 21, 9));

    Future<(AnalyticsController, PreferencesStore, _FakeBackend)> controller([
      Map<String, Object> values = const {},
    ]) async {
      final backend = _FakeBackend();
      final store = await _store(values);
      return (
        AnalyticsController(store, backend, clock: () => now),
        store,
        backend,
      );
    }

    /// Opens the app on [days] more days, one day apart.
    void openOn(AnalyticsController controller, int days) {
      for (var i = 0; i < days; i++) {
        now = now.add(const Duration(days: 1));
        controller.noteVisit();
      }
    }

    test('the limits are 30 days and 5 days of use', () {
      expect(analyticsReminderAfterDays, 30);
      expect(analyticsReminderActiveDays, 5);
    });

    test('a refusal remembers its day', () async {
      final (analytics, store, _) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      await Future<void>.delayed(Duration.zero);
      final reminder = AnalyticsReminder.parse(store.analyticsReminder);
      expect(reminder.declinedOn, '2026-11-21');
      expect(reminder.days, 1);
      expect(reminder.done, isFalse);
      expect(analytics.reminderDue.value, isFalse);
    });

    test('not before 30 days, however often the app is opened', () async {
      final (analytics, _, _) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 29);
      expect(analytics.reminderDue.value, isFalse);
      openOn(analytics, 1);
      expect(analytics.reminderDue.value, isTrue);
    });

    test('not with fewer than 5 days of use, however long ago', () async {
      final (analytics, _, _) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 3); // four days with the day of the refusal
      now = now.add(const Duration(days: 60));
      // The same day again does not count twice.
      analytics.noteVisit();
      analytics.noteVisit();
      expect(analytics.reminderDue.value, isTrue);
    });

    test('four days of use are not enough', () async {
      final (analytics, _, _) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 2);
      now = now.add(const Duration(days: 60));
      analytics.noteVisit();
      expect(analytics.reminderDue.value, isFalse);
    });

    test('a second refusal is final, also after a restart', () async {
      final (analytics, store, backend) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 30);
      expect(analytics.reminderDue.value, isTrue);

      await analytics.setConsent(AnalyticsConsent.denied);
      await Future<void>.delayed(Duration.zero);
      expect(analytics.reminderDue.value, isFalse);
      expect(store.analyticsConsent, 'denied');
      expect(backend.calls, isNot(contains('enable')));

      final restarted = AnalyticsController(store, backend, clock: () => now);
      openOn(restarted, 400);
      expect(restarted.reminderDue.value, isFalse);
    });

    test('the reminder waits for an answer across restarts', () async {
      final (analytics, store, backend) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 30);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(days: 1));
      final restarted = AnalyticsController(store, backend, clock: () => now);
      expect(restarted.reminderDue.value, isTrue);
    });

    test('agreeing on the reminder turns statistics on for good', () async {
      final (analytics, store, backend) = await controller();
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 30);
      await analytics.setConsent(AnalyticsConsent.granted);
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, ['disable', 'enable']);
      expect(store.analyticsConsent, 'granted');
      expect(analytics.reminderDue.value, isFalse);

      // Switching it off in Settings later is not asked about again.
      await analytics.setConsent(AnalyticsConsent.denied);
      openOn(analytics, 60);
      expect(analytics.reminderDue.value, isFalse);
    });

    test('an old refusal without a date counts from the first run', () async {
      final (analytics, store, _) = await controller({
        'iqro_analytics_consent_v1': 'denied',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        AnalyticsReminder.parse(store.analyticsReminder).declinedOn,
        '2026-11-21',
      );
      openOn(analytics, 29);
      expect(analytics.reminderDue.value, isFalse);
      openOn(analytics, 1);
      expect(analytics.reminderDue.value, isTrue);
    });

    test('nobody who agreed or has not answered is reminded', () async {
      final (granted, _, _) = await controller({
        'iqro_analytics_consent_v1': 'granted',
      });
      openOn(granted, 60);
      expect(granted.reminderDue.value, isFalse);

      final (unanswered, store, _) = await controller();
      openOn(unanswered, 60);
      expect(unanswered.reminderDue.value, isFalse);
      expect(store.analyticsReminder, isNull);
    });

    test(
      'a refusal in Settings before the reminder restarts the count',
      () async {
        final (analytics, _, _) = await controller();
        await analytics.setConsent(AnalyticsConsent.denied);
        openOn(analytics, 20);
        await analytics.setConsent(AnalyticsConsent.granted);
        await analytics.setConsent(AnalyticsConsent.denied);
        openOn(analytics, 29);
        expect(analytics.reminderDue.value, isFalse);
        openOn(analytics, 1);
        expect(analytics.reminderDue.value, isTrue);
      },
    );
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
      Map<String, Object> values = const {},
      Locale locale = const Locale('ru'),
    }) async {
      final backend = _FakeBackend();
      final store = await _store(values);
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
            locale: locale,
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

    testWidgets('a month after a refusal the card asks once more', (
      tester,
    ) async {
      final (backend, store) = await pump(
        tester,
        values: {
          'iqro_analytics_consent_v1': 'denied',
          'iqro_analytics_reminder_v1':
              '{"declinedOn":"2020-01-01","lastDay":"2020-02-01","days":5,"done":false}',
        },
      );
      expect(find.byKey(const ValueKey('analytics-consent')), findsNothing);
      expect(find.byKey(const ValueKey('analytics-reminder')), findsOneWidget);
      expect(find.textContaining('Вы пользуетесь IQRO уже месяц'), findsOne);
      expect(find.text('Политика конфиденциальности'), findsOneWidget);
      // Nothing is promised or held back.
      expect(find.textContaining('прогресс'), findsNothing);
      expect(find.textContaining('курс'), findsNothing);

      await tester.tap(find.text('Нет, спасибо'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analytics-reminder')), findsNothing);
      expect(store.analyticsConsent, 'denied');
      expect(AnalyticsReminder.parse(store.analyticsReminder).done, isTrue);
      expect(backend.calls, isEmpty);
      // The switch in Settings stays.
      expect(
        find.byKey(const ValueKey('analytics-consent-setting')),
        findsOneWidget,
      );
    });

    testWidgets('«Разрешить» on the reminder turns statistics on', (
      tester,
    ) async {
      final (backend, store) = await pump(
        tester,
        values: {
          'iqro_analytics_consent_v1': 'denied',
          'iqro_analytics_reminder_v1':
              '{"declinedOn":"2020-01-01","lastDay":"2020-02-01","days":5,"done":false}',
        },
      );
      await tester.tap(find.text('Разрешить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analytics-reminder')), findsNothing);
      expect(store.analyticsConsent, 'granted');
      expect(backend.calls, ['enable']);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('the reminder fits a narrow phone in $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          locale: locale,
          values: {
            'iqro_analytics_consent_v1': 'denied',
            'iqro_analytics_reminder_v1':
                '{"declinedOn":"2020-01-01","lastDay":"2020-02-01","days":5,"done":false}',
          },
        );
        expect(
          find.byKey(const ValueKey('analytics-reminder')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

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
