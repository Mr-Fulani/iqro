import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_services.dart';
import 'package:iqro_mobile/features/reminders/reminder_sound_dialog.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations_ru.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_test_support.dart';

final _ru = AppLocalizationsRu();

Future<PreferencesStore> _pump(
  WidgetTester tester,
  FakeOnboardingServices services, {
  Map<String, Object> stored = const <String, Object>{},
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'locale': 'ru',
    ...stored,
  });
  final store = PreferencesStore(
    (await tester.runAsync(SharedPreferences.getInstance))!,
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        appPreferencesProvider.overrideWith(
          (ref) => AppPreferencesController(store, FakePlanRepository()),
        ),
        onboardingServicesProvider.overrideWithValue(services),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => checkReminderSoundOnce(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('muted reminders warn once and offer the switch', (tester) async {
    final services = FakeOnboardingServices(soundAllowed: false)
      ..soundingReminders = true;
    final store = await _pump(tester, services);

    expect(find.text(_ru.onboardingSoundBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('reminder-sound-switch')));
    expect(services.soundSettingsOpened, 1);

    services.soundAllowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_ru.onboardingSoundOn), findsOneWidget);

    await tester.tap(find.byKey(const Key('reminder-sound-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSoundDialog), findsNothing);
    expect(store.read().reminderSoundChecked, isTrue);
  });

  testWidgets('sounding reminders stay quiet and are not checked again', (
    tester,
  ) async {
    final services = FakeOnboardingServices()..soundingReminders = true;
    final store = await _pump(tester, services);

    expect(find.byType(ReminderSoundDialog), findsNothing);
    expect(services.soundChecks, 1);
    expect(store.read().reminderSoundChecked, isTrue);
  });

  testWidgets('a device already checked is left alone', (tester) async {
    final services = FakeOnboardingServices(soundAllowed: false)
      ..soundingReminders = true;
    await _pump(
      tester,
      services,
      stored: const <String, Object>{'reminder_sound_checked': true},
    );

    expect(services.soundChecks, 0);
    expect(find.byType(ReminderSoundDialog), findsNothing);
  });

  testWidgets('without sounding reminders the check waits for a later launch', (
    tester,
  ) async {
    final services = FakeOnboardingServices(soundAllowed: false);
    final store = await _pump(tester, services);

    expect(services.soundChecks, 0);
    expect(store.read().reminderSoundChecked, isFalse);
  });

  testWidgets('the dialog stays compact on a tablet', (tester) async {
    final services = FakeOnboardingServices(soundAllowed: false)
      ..soundingReminders = true;
    await _pump(tester, services, size: const Size(1280, 800));

    expect(
      tester
          .getSize(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .width,
      lessThanOrEqualTo(560),
    );
    expect(tester.takeException(), isNull);
  });
}
