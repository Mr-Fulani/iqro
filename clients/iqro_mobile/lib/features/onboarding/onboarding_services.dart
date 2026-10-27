import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers.dart';
import '../../core/auth/account_scope.dart';
import '../prayer/prayer_places.dart';
import '../prayer/prayer_repository.dart';
import '../reminders/reminder_controller.dart';
import '../reminders/reminder_models.dart';

const onboardingPrayerEvents = <String>[
  'fajr',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

/// What the prayer step starts from: the stored choice, if any.
class OnboardingPrayerSetup {
  const OnboardingPrayerSetup({
    required this.methods,
    required this.methodCode,
    required this.asrMethod,
    required this.location,
  });

  /// Empty when the catalog could not be loaded (first launch offline).
  final List<PrayerMethod> methods;
  final String? methodCode;
  final String asrMethod;
  final PrayerLocation? location;
}

/// Everything the onboarding does outside its own screen. Each call is safe to
/// skip: the app works without location, notifications and exact alarms.
abstract interface class OnboardingServices {
  Future<OnboardingPrayerSetup> loadPrayer();

  /// Asks for location once; throws [ApiException] with a `location_*` code.
  Future<PrayerLocation> useDeviceLocation(PrayerMethod method);

  Future<PrayerLocation> useCity(PrayerCity city, PrayerMethod method);

  Future<void> savePrayerProfile({
    required PrayerMethod method,
    required String asrMethod,
    required String locale,
  });

  Future<void> openLocationSettings();

  Future<void> openAppSettings();

  /// Whether notifications are allowed and any prayer reminder is on.
  Future<({ReminderPermission permission, bool prayerReminders})>
  reminderStatus();

  Future<ReminderPermission> requestNotifications();

  Future<void> enablePrayerReminders();

  Future<bool> needsExactReminderAccess();

  Future<bool> requestExactReminders();
}

final onboardingServicesProvider = Provider<OnboardingServices>(
  (ref) => AppOnboardingServices(ref),
);

class AppOnboardingServices implements OnboardingServices {
  AppOnboardingServices(this._ref);

  final Ref _ref;

  PrayerRepository get _prayer => _ref.read(prayerRepositoryProvider);

  AccountScopeSnapshot? get _scope =>
      _ref.read(localDatabaseProvider).accountScope.current;

  @override
  Future<OnboardingPrayerSetup> loadPrayer() async {
    final scope = _scope;
    final location = await _prayer.storedLocation(accountScope: scope);
    final code = await _prayer.selectedMethodCode(accountScope: scope);
    List<PrayerMethod> methods;
    try {
      methods = await _ref.read(prayerMethodsProvider.future);
    } on Object {
      methods = const <PrayerMethod>[];
    }
    final method = methods.isEmpty
        ? null
        : methods.where((item) => item.code == code).firstOrNull ??
              defaultPrayerMethod(methods);
    final preferences = method == null
        ? null
        : await _prayer.storedPreferences(method: method, accountScope: scope);
    return OnboardingPrayerSetup(
      methods: methods,
      methodCode: method?.code,
      asrMethod: preferences?.asrMethod ?? 'standard',
      location: location,
    );
  }

  @override
  Future<PrayerLocation> useDeviceLocation(PrayerMethod method) async {
    final scope = _scope;
    await _prayer.calculateForCurrentLocation(
      method: method,
      accountScope: scope,
    );
    return (await _prayer.storedLocation(accountScope: scope))!;
  }

  @override
  Future<PrayerLocation> useCity(PrayerCity city, PrayerMethod method) async {
    final location = PrayerLocation(
      latitude: city.latitude,
      longitude: city.longitude,
      timezone: city.timezone,
      cityId: city.id,
    );
    await _prayer.calculateForLocation(
      method: method,
      location: location,
      accountScope: _scope,
    );
    return location;
  }

  @override
  Future<void> savePrayerProfile({
    required PrayerMethod method,
    required String asrMethod,
    required String locale,
  }) async {
    final scope = _scope;
    if (scope == null) return;
    final current = await _prayer.storedPreferences(
      method: method,
      accountScope: scope,
    );
    await _prayer.saveProfile(
      method: method,
      preferences: current.copyWith(asrMethod: asrMethod),
      accountScope: scope,
    );
    final schedule = await _prayer.calculateForStoredLocation(
      method: method,
      accountScope: scope,
    );
    _ref.invalidate(prayerScheduleProvider(accountScopeKey(scope)));
    if (schedule == null) return;
    await _ref.read(reminderProvider.notifier).replan();
    try {
      await _ref
          .read(prayerWidgetServiceProvider)
          .update(locale: locale, accountScope: scope);
    } on Object catch (error, stackTrace) {
      debugPrint('IQRO onboarding: prayer widget update failed: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 4);
    }
  }

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<({ReminderPermission permission, bool prayerReminders})>
  reminderStatus() async {
    await _ref.read(reminderProvider.notifier).reload();
    final state = _ref.read(reminderProvider);
    return (
      permission: state.permission,
      prayerReminders: state.rules.any(
        (rule) => rule.type == ReminderType.prayer && rule.isEnabled,
      ),
    );
  }

  @override
  Future<ReminderPermission> requestNotifications() => _ref
      .read(reminderProvider.notifier)
      .requestPermission(exactAlarms: false);

  @override
  Future<void> enablePrayerReminders() async {
    final reminders = await _accountReminders();
    // Existing rules first: toggling before they load would duplicate them.
    await reminders.reload();
    for (final event in onboardingPrayerEvents) {
      await reminders.togglePrayer(event, true);
    }
  }

  /// Reminder rules are account data, and a fresh install has no guest
  /// account until something needs one: create it (this needs the network)
  /// and wait for the reminder controller bound to it.
  Future<ReminderController> _accountReminders() async {
    await _ref.read(localDatabaseProvider).captureAccount();
    if (_ref.read(activeAccountScopeKeyProvider) == null) {
      final bound = Completer<void>();
      final subscription = _ref.listen<AccountScopeKey?>(
        activeAccountScopeKeyProvider,
        (_, key) {
          if (key != null && !bound.isCompleted) bound.complete();
        },
        fireImmediately: true,
      );
      try {
        await bound.future.timeout(const Duration(seconds: 10));
      } finally {
        subscription.close();
      }
    }
    return _ref.read(reminderProvider.notifier);
  }

  @override
  Future<bool> needsExactReminderAccess() async =>
      !await _ref.read(notificationGatewayProvider).canScheduleExactReminders();

  @override
  Future<bool> requestExactReminders() async {
    final granted = await _ref
        .read(notificationGatewayProvider)
        .requestExactReminders();
    if (granted) await _ref.read(reminderProvider.notifier).replan();
    return granted;
  }
}
