import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'onboarding_test_support.dart';

final _ru = lookupAppLocalizations(const Locale('ru'));
final _en = lookupAppLocalizations(const Locale('en'));
final _ar = lookupAppLocalizations(const Locale('ar'));

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch starts in the phone language and switches live', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[
      Locale('en', 'US'),
    ];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final harness = await pumpOnboarding(tester);

    expect(find.text(_en.onboardingWelcomeTitle), findsOneWidget);
    expect(harness.store.read().locale, 'en');

    await _tap(tester, 'onboarding-language-ar');
    expect(find.text(_ar.onboardingWelcomeTitle), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(_ar.onboardingWelcomeTitle))),
      TextDirection.rtl,
    );

    await _tap(tester, 'onboarding-language-ru');
    expect(find.text(_ru.onboardingWelcomeTitle), findsOneWidget);
    expect(harness.store.read().locale, 'ru');
  });

  testWidgets('a stored language is never replaced by the phone language', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('tr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final harness = await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ar'},
    );
    expect(harness.store.read().locale, 'ar');
    expect(find.text(_ar.onboardingWelcomeTitle), findsOneWidget);
  });

  testWidgets('skipping everything finishes with nothing requested', (
    tester,
  ) async {
    final harness = await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
    );

    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingTourQuranTitle), findsOneWidget);
    await _tap(tester, 'onboarding-skip-tour');
    expect(find.text(_ru.onboardingGoalTitle), findsOneWidget);
    await _tap(tester, 'onboarding-goal-memorization');
    await _tap(tester, 'onboarding-next');

    expect(find.text(_ru.onboardingPrayerTitle), findsOneWidget);
    // New users start with the Muslim World League, not the first catalog
    // entry.
    expect(find.text('Всемирная исламская лига'), findsOneWidget);
    await _tap(tester, 'onboarding-later');

    expect(find.text(_ru.onboardingRemindersTitle), findsOneWidget);
    await _tap(tester, 'onboarding-later');

    expect(find.text(_ru.analyticsTitle), findsOneWidget);
    await _tap(tester, 'onboarding-later');
    expect(harness.store.analyticsConsent, AnalyticsConsent.denied.name);

    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
    expect(find.text(_ru.onboardingLater), findsNWidgets(2));
    await _tap(tester, 'onboarding-next');

    expect(find.text('home'), findsOneWidget);
    final preferences = harness.store.read();
    expect(preferences.onboardingComplete, isTrue);
    expect(preferences.goal, 'memorization');
    expect(harness.plan.initialized, <int>[6]);
    expect(harness.services.notificationRequests, 0);
    expect(harness.services.savedProfiles, isEmpty);
  });

  testWidgets('the plan step starts from the stored goal', (tester) async {
    final harness = await pumpOnboarding(
      tester,
      stored: const <String, Object>{
        'locale': 'ru',
        'daily_unit': 'pages',
        'daily_target': 5,
      },
      initialStep: OnboardingStep.plan,
    );
    expect(find.text(_ru.onboardingPerDay(_ru.planPages(5))), findsOneWidget);
    expect(harness.store.read().dailyTarget, 5);
  });

  testWidgets('a short step sits at the top of a tall screen', (tester) async {
    await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.exactReminders,
      size: const Size(400, 1600),
    );
    expect(
      tester.getTopLeft(find.text(_ru.onboardingExactTitle)).dy,
      lessThan(260),
    );
  });

  // iPad 11" upright: the step was as wide as the screen, with a switch at
  // the far edge from its label.
  testWidgets('a tablet keeps a step in a centred column', (tester) async {
    await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.exactReminders,
      size: const Size(834, 1194),
    );
    final title = tester.getRect(find.text(_ru.onboardingExactTitle));
    expect(title.left, (834 - 600) / 2);
    expect(title.right, lessThanOrEqualTo((834 + 600) / 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tour pages through all four slides', (tester) async {
    await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.tour,
    );
    for (final title in <String>[
      _ru.onboardingTourQuranTitle,
      _ru.onboardingTourAudioTitle,
      _ru.onboardingTourStudyTitle,
      _ru.onboardingTourDailyTitle,
    ]) {
      expect(find.text(title), findsOneWidget);
      await _tap(tester, 'onboarding-next');
    }
    expect(find.text(_ru.onboardingGoalTitle), findsOneWidget);
  });

  testWidgets('a denied location keeps the step usable and saves the method', (
    tester,
  ) async {
    final services = FakeOnboardingServices(locationError: locationDenied);
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.prayer,
    );

    await _tap(tester, 'onboarding-use-location');
    expect(find.text(_ru.locationPermissionRequiredBody), findsOneWidget);

    await tester.tap(find.text(_ru.asrHanafi));
    await tester.pumpAndSettle();
    await _tap(tester, 'onboarding-next');

    expect(services.savedProfiles, <(String, String)>[
      ('muslim-world-league', 'hanafi'),
    ]);
    expect(find.text(_ru.onboardingRemindersTitle), findsOneWidget);
  });

  testWidgets('a chosen location shows up in the summary', (tester) async {
    final services = FakeOnboardingServices();
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.prayer,
      analytics: false,
    );
    await _tap(tester, 'onboarding-use-location');
    expect(
      find.text(_ru.onboardingLocationSelected(_ru.currentLocation)),
      findsOneWidget,
    );
    await _tap(tester, 'onboarding-next');
    await _tap(tester, 'onboarding-later');
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
    expect(find.text(_ru.currentLocation), findsOneWidget);
  });

  testWidgets('offline prayer setup can still be skipped', (tester) async {
    await pumpOnboarding(
      tester,
      services: FakeOnboardingServices(methods: const <PrayerMethod>[]),
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.prayer,
    );
    expect(find.text(_ru.onboardingPrayerOffline), findsOneWidget);
    expect(find.byKey(const Key('onboarding-use-location')), findsNothing);
    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingRemindersTitle), findsOneWidget);
  });

  testWidgets('refused notifications are explained, never retried', (
    tester,
  ) async {
    final services = FakeOnboardingServices(
      notificationResult: ReminderPermission.denied,
    );
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
    );

    await _tap(tester, 'onboarding-next');
    expect(services.notificationRequests, 1);
    expect(services.remindersEnabled, 0);
    expect(find.text(_ru.onboardingNotificationsBlocked), findsOneWidget);
    // Android may ask again itself: no way to the settings here.
    expect(find.text(_ru.onboardingOpenSettings), findsNothing);

    await _tap(tester, 'onboarding-later');
    expect(find.text(_ru.onboardingExactTitle), findsNothing);
    expect(find.text(_ru.analyticsTitle), findsOneWidget);
    expect(services.notificationRequests, 1);
  });

  testWidgets('on iOS the reminders step leads to the system question with '
      'one button and goes on after the answer, never asking again', (
    tester,
  ) async {
    final services = FakeOnboardingServices(
      notificationResult: ReminderPermission.denied,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final harness = await pumpOnboarding(
        tester,
        services: services,
        stored: const <String, Object>{'locale': 'ru'},
        initialStep: OnboardingStep.reminders,
      );
      // Not «Allow», and no way past the question.
      expect(find.byKey(const Key('onboarding-later')), findsNothing);
      expect(find.text(_ru.allowNotifications), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('onboarding-next')),
          matching: find.text(_ru.continueLabel),
        ),
        findsOneWidget,
      );

      await _tap(tester, 'onboarding-next');
      expect(services.notificationRequests, 1);
      expect(harness.store.read().notificationsAsked, isTrue);
      expect(find.text(_ru.analyticsTitle), findsOneWidget);

      // Back on the step: the answer stands, the settings change it.
      await _tap(tester, 'onboarding-back');
      expect(find.text(_ru.onboardingNotificationsBlocked), findsOneWidget);
      await tester.tap(find.text(_ru.onboardingOpenSettings));
      await tester.pumpAndSettle();
      expect(services.soundSettingsOpened, 1);
      expect(services.notificationRequests, 1);

      // Allowed there: back in the app the step says so, asking nothing.
      services.permissionNow = ReminderPermission.granted;
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text(_ru.onboardingNotificationsOn), findsOneWidget);
      expect(find.text(_ru.onboardingNotificationsBlocked), findsNothing);
      expect(services.notificationRequests, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on Android coming back to the reminders step after a refusal '
      'reads nothing again', (tester) async {
    final services = FakeOnboardingServices(
      notificationResult: ReminderPermission.denied,
    );
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
    );
    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingNotificationsBlocked), findsOneWidget);
    final reads = services.statusReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(services.statusReads, reads);
    expect(find.text(_ru.onboardingNotificationsBlocked), findsOneWidget);
  });

  testWidgets('on iOS a replay after a refusal shows the way to the settings '
      'from the start', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpOnboarding(
        tester,
        stored: const <String, Object>{
          'locale': 'ru',
          'notifications_asked': true,
        },
        initialStep: OnboardingStep.reminders,
      );
      expect(find.text(_ru.onboardingNotificationsBlocked), findsOneWidget);
      expect(find.text(_ru.onboardingOpenSettings), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('allowed reminders explain exact alarms before settings', (
    tester,
  ) async {
    final services = FakeOnboardingServices(needsExact: true);
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );

    await _tap(tester, 'onboarding-next');
    expect(services.remindersEnabled, 1);
    expect(find.text(_ru.onboardingExactTitle), findsOneWidget);

    await _tap(tester, 'onboarding-later');
    expect(services.exactRequests, 0);
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
    expect(find.text(_ru.onboardingRemindersOn), findsOneWidget);
  });

  testWidgets('muted reminders warn after exact alarms and offer the switch', (
    tester,
  ) async {
    final services = FakeOnboardingServices(
      needsExact: true,
      soundAllowed: false,
    );
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );

    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingExactTitle), findsOneWidget);

    await _tap(tester, 'onboarding-later');
    expect(find.text(_ru.onboardingSoundBody), findsOneWidget);

    await _tap(tester, 'onboarding-reminder-sound');
    expect(services.soundSettingsOpened, 1);

    services.soundAllowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_ru.onboardingSoundOn), findsOneWidget);

    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('reminders that sound skip the sound step', (tester) async {
    await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );

    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingSoundTitle), findsNothing);
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('without prayer reminders the sound step stays away', (
    tester,
  ) async {
    final services = FakeOnboardingServices(soundAllowed: false);
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );

    await _tap(tester, 'onboarding-five-prayers');
    await _tap(tester, 'onboarding-next');
    expect(find.text(_ru.onboardingSoundTitle), findsNothing);
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('the button shows progress while reminders are set up', (
    tester,
  ) async {
    final gate = Completer<void>();
    final services = FakeOnboardingServices()..remindersGate = gate.future;
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('onboarding-next')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(services.remindersEnabled, 1);
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('turning the prayer switch off only asks for notifications', (
    tester,
  ) async {
    final services = FakeOnboardingServices(needsExact: true);
    await pumpOnboarding(
      tester,
      services: services,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.reminders,
      analytics: false,
    );
    await _tap(tester, 'onboarding-five-prayers');
    await _tap(tester, 'onboarding-next');
    expect(services.notificationRequests, 1);
    expect(services.remindersEnabled, 0);
    expect(find.text(_ru.onboardingExactTitle), findsNothing);
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
  });

  testWidgets('replay from settings skips the plan and keeps progress', (
    tester,
  ) async {
    final harness = await pumpOnboarding(
      tester,
      replay: true,
      stored: <String, Object>{
        'locale': 'ru',
        'onboarding_complete': true,
        'iqro_analytics_consent_v1': AnalyticsConsent.granted.name,
      },
      services: FakeOnboardingServices(
        initialPermission: ReminderPermission.granted,
      ),
    );
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();

    await _tap(tester, 'onboarding-next');
    await _tap(tester, 'onboarding-skip-tour');
    expect(find.text(_ru.onboardingPrayerTitle), findsOneWidget);
    await _tap(tester, 'onboarding-later');
    // Already allowed: the button continues instead of asking again.
    expect(find.text(_ru.onboardingNotificationsOn), findsOneWidget);
    await _tap(tester, 'onboarding-later');
    // Answered before: no second question about statistics.
    expect(find.text(_ru.onboardingDoneTitle), findsOneWidget);
    await _tap(tester, 'onboarding-next');

    expect(find.text('home'), findsOneWidget);
    expect(harness.plan.initialized, isEmpty);
    expect(harness.store.read().onboardingComplete, isTrue);
  });

  testWidgets('system back returns to the previous step', (tester) async {
    await pumpOnboarding(
      tester,
      stored: const <String, Object>{'locale': 'ru'},
      initialStep: OnboardingStep.plan,
    );
    await _tap(tester, 'onboarding-back');
    expect(find.text(_ru.onboardingTourQuranTitle), findsOneWidget);
  });

  testWidgets('large text keeps every step scrollable without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final step in OnboardingStep.values) {
      await pumpOnboarding(
        tester,
        stored: const <String, Object>{'locale': 'ru'},
        initialStep: step,
        size: const Size(360, 740),
      );
      expect(tester.takeException(), isNull, reason: step.name);
    }
  });

  test('default prayer method prefers the Muslim World League', () {
    expect(defaultPrayerMethod(testPrayerMethods).code, 'muslim-world-league');
    expect(
      defaultPrayerMethod(<PrayerMethod>[
        testPrayerMethod('egyptian', 'E'),
      ]).code,
      'egyptian',
    );
  });

  test('every onboarding string exists in all four languages', () {
    for (final locale in PreferencesStore.supportedLocales) {
      final l10n = lookupAppLocalizations(Locale(locale));
      expect(l10n.onboardingWelcomeTitle, isNotEmpty);
      expect(l10n.onboardingReplay, isNotEmpty);
    }
  });
}
