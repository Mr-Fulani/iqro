import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_screen.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_services.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

PrayerMethod testPrayerMethod(
  String code,
  String name, {
  Map<String, String> names = const <String, String>{},
}) => PrayerMethod.fromJson(<String, Object?>{
  'id': code,
  'code': code,
  'available': true,
  'name': <String, Object?>{'en': name, ...names},
});

// The server's names: Arabic, English and Russian; Turkish falls back.
final testPrayerMethods = <PrayerMethod>[
  testPrayerMethod(
    'dubai',
    'Dubai',
    names: const <String, String>{'ru': 'Дубай', 'ar': 'طريقة دبي'},
  ),
  testPrayerMethod(
    'muslim-world-league',
    'Muslim World League',
    names: const <String, String>{
      'ru': 'Всемирная исламская лига',
      'ar': 'رابطة العالم الإسلامي',
    },
  ),
];

class FakeOnboardingServices implements OnboardingServices {
  FakeOnboardingServices({
    this.methods,
    this.location,
    this.locationError,
    this.notificationResult = ReminderPermission.granted,
    this.initialPermission = ReminderPermission.denied,
    this.needsExact = false,
  });

  final List<PrayerMethod>? methods;
  PrayerLocation? location;
  final Object? locationError;
  final ReminderPermission notificationResult;
  final ReminderPermission initialPermission;
  final bool needsExact;

  var notificationRequests = 0;
  var remindersEnabled = 0;
  var exactRequests = 0;
  final savedProfiles = <(String, String)>[];

  @override
  Future<OnboardingPrayerSetup> loadPrayer() async {
    final available = methods ?? testPrayerMethods;
    return OnboardingPrayerSetup(
      methods: available,
      methodCode: available.isEmpty
          ? null
          : defaultPrayerMethod(available).code,
      asrMethod: 'standard',
      location: location,
    );
  }

  @override
  Future<PrayerLocation> useDeviceLocation(PrayerMethod method) async {
    final error = locationError;
    if (error != null) throw error;
    return location = const PrayerLocation(
      latitude: 55.79,
      longitude: 49.12,
      timezone: 'Europe/Moscow',
    );
  }

  @override
  Future<PrayerLocation> useCity(PrayerCity city, PrayerMethod method) async =>
      location = PrayerLocation(
        latitude: city.latitude,
        longitude: city.longitude,
        timezone: city.timezone,
        cityId: city.id,
      );

  @override
  Future<void> savePrayerProfile({
    required PrayerMethod method,
    required String asrMethod,
    required String locale,
  }) async {
    savedProfiles.add((method.code, asrMethod));
  }

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<({ReminderPermission permission, bool prayerReminders})>
  reminderStatus() async => (
    permission: initialPermission,
    prayerReminders: initialPermission == ReminderPermission.granted,
  );

  @override
  Future<ReminderPermission> requestNotifications() async {
    notificationRequests++;
    return notificationResult;
  }

  /// Holds the reminder setup open until completed, when set.
  Future<void>? remindersGate;

  @override
  Future<void> enablePrayerReminders() async {
    await remindersGate;
    remindersEnabled++;
  }

  @override
  Future<bool> needsExactReminderAccess() async => needsExact;

  @override
  Future<bool> requestExactReminders() async {
    exactRequests++;
    return true;
  }
}

class FakePlanRepository implements PlanRepository {
  final initialized = <int>[];

  @override
  Future<DailyPlan> initialize({
    required int target,
    ReadingGoalMetric metric = ReadingGoalMetric.pages,
    AccountScopeSnapshot? accountScope,
  }) async {
    initialized.add(target);
    return DailyPlan.initial(target: target.toDouble(), metric: metric);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoopAnalyticsBackend implements AnalyticsBackend {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {}
}

class OnboardingHarness {
  OnboardingHarness(this.store, this.plan, this.services);

  final PreferencesStore store;
  final FakePlanRepository plan;
  final FakeOnboardingServices services;
}

/// The onboarding inside a router with a stand-in home screen; the app's
/// locale follows the stored preference like the real app does.
Future<OnboardingHarness> pumpOnboarding(
  WidgetTester tester, {
  FakeOnboardingServices? services,
  Map<String, Object> stored = const <String, Object>{},
  bool replay = false,
  bool analytics = true,
  bool dark = false,
  OnboardingStep? initialStep,
  int initialTourSlide = 0,
  ThemeData Function(ThemeData theme)? themed,
  Size? size,
  double pixelRatio = 1,
  Key? boundary,
  List<Override> overrides = const <Override>[],
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
  }
  SharedPreferences.setMockInitialValues(stored);
  final store = PreferencesStore(
    (await tester.runAsync(SharedPreferences.getInstance))!,
  );
  final plan = FakePlanRepository();
  final fake = services ?? FakeOnboardingServices();
  final router = GoRouter(
    initialLocation: replay ? '/app' : '/onboarding',
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(
          replay: state.uri.queryParameters['replay'] == '1',
          initialStep: initialStep,
          initialTourSlide: initialTourSlide,
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/onboarding?replay=1'),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final theme = themed ?? (value) => value;
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: ProviderScope(
        // A fresh scope per pump: Riverpod keeps overrideWith factories of a
        // reused scope.
        key: UniqueKey(),
        overrides: <Override>[
          appPreferencesProvider.overrideWith(
            (ref) => AppPreferencesController(store, plan),
          ),
          analyticsProvider.overrideWith(
            (ref) => analytics
                ? AnalyticsController(store, NoopAnalyticsBackend())
                : AnalyticsController.disabled(),
          ),
          onboardingServicesProvider.overrideWithValue(fake),
          ...overrides,
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: theme(IqroTheme.light()),
            darkTheme: theme(IqroTheme.dark()),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: router,
            locale: Locale(ref.watch(appPreferencesProvider).locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return OnboardingHarness(store, plan, fake);
}

const locationDenied = ApiException(
  message: 'Location permission was denied',
  code: 'location_denied',
);
