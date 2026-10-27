import 'dart:async';

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

    await _tap(tester, 'onboarding-later');
    expect(find.text(_ru.onboardingExactTitle), findsNothing);
    expect(find.text(_ru.analyticsTitle), findsOneWidget);
    expect(services.notificationRequests, 1);
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
