import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_controller.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/features/reminders/reminder_repository.dart';
import 'package:iqro_mobile/features/reminders/reminders_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_test_support.dart' show FakePlanRepository;

final _ru = lookupAppLocalizations(const Locale('ru'));

void main() {
  final banner = find.byKey(const Key('reminders-notification-access'));

  Future<(_Notifications, PreferencesStore)> pump(
    WidgetTester tester, {
    Map<String, Object> stored = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final store = PreferencesStore(
      (await tester.runAsync(SharedPreferences.getInstance))!,
    );
    final notifications = _Notifications();
    final database = _Database();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appPreferencesProvider.overrideWith(
            (ref) => AppPreferencesController(store, FakePlanRepository()),
          ),
          localDatabaseProvider.overrideWithValue(database),
          prayerRepositoryProvider.overrideWithValue(_Prayer()),
          // No account yet: the permission is asked all the same.
          reminderProvider.overrideWith(
            (ref) => ReminderController(
              repository: _Reminders(),
              notifications: notifications,
              prayerRepository: _Prayer(),
              database: database,
              accountScope: null,
              locale: () => 'ru',
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: IqroTheme.light(),
          home: const RemindersScreen(),
        ),
      ),
    );
    // The reminders are still loading: their spinner never settles.
    await tester.pump();
    return (notifications, store);
  }

  testWidgets('on Android the banner asks for notifications as before', (
    tester,
  ) async {
    final (notifications, store) = await pump(tester);
    expect(find.text(_ru.notificationAccess), findsOneWidget);
    await tester.tap(find.text(_ru.allowNotifications));
    await tester.pump();
    expect(notifications.requests, 1);
    // Refused, and asked again on the next tap: Android may still ask.
    await tester.tap(find.text(_ru.allowNotifications));
    await tester.pump();
    expect(notifications.requests, 2);
    expect(find.text(_ru.onboardingOpenSettings), findsNothing);
    expect(store.read().notificationsAsked, isFalse);
  });

  testWidgets('on iOS the banner leads to the one system question with one '
      'button, and after the answer to the settings', (tester) async {
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocator, (
      call,
    ) async {
      opened.add(call.method);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geolocator,
        null,
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final (notifications, store) = await pump(tester);
      // No «Allow» before the system's own question.
      expect(
        find.descendant(
          of: banner,
          matching: find.text(_ru.notificationsForReminders),
        ),
        findsOneWidget,
      );
      expect(find.text(_ru.notificationAccess), findsNothing);
      expect(find.text(_ru.allowNotifications), findsNothing);
      await tester.tap(
        find.descendant(of: banner, matching: find.text(_ru.continueLabel)),
      );
      await tester.pump();
      expect(notifications.requests, 1);
      expect(store.read().notificationsAsked, isTrue);

      // Refused: iOS will not ask again, and the button opens the settings.
      expect(
        find.descendant(of: banner, matching: find.text(_ru.notificationsOff)),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: banner,
          matching: find.text(_ru.onboardingOpenSettings),
        ),
      );
      await tester.pump();
      expect(opened, <String>['openAppSettings']);
      expect(notifications.requests, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on iOS a question asked before leads to the settings at once', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final (notifications, _) = await pump(
        tester,
        stored: const <String, Object>{'notifications_asked': true},
      );
      expect(
        find.descendant(of: banner, matching: find.text(_ru.notificationsOff)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.text(_ru.onboardingOpenSettings),
        ),
        findsOneWidget,
      );
      expect(notifications.requests, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// Notifications the test answers for: refused.
class _Notifications implements NotificationGateway {
  var requests = 0;

  @override
  Future<ReminderPermission> permissionStatus() async =>
      ReminderPermission.denied;

  @override
  Future<ReminderPermission> requestPermission({
    bool exactAlarms = true,
  }) async {
    requests++;
    return ReminderPermission.denied;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reminders implements ReminderRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Prayer implements PrayerRepository {
  @override
  Future<PrayerLocation?> storedLocation({
    AccountScopeSnapshot? accountScope,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('reminders');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
