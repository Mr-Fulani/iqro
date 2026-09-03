import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer/prayer_repository.dart';
import '../../features/reminders/reminder_models.dart';
import '../auth/account_scope.dart';
import '../storage/local_database.dart';

class ReminderSchedulingResult {
  const ReminderSchedulingResult({
    required this.permission,
    required this.exact,
    required this.scheduled,
  });

  final ReminderPermission permission;
  final bool exact;
  final int scheduled;
}

class _PlannedReminderNotification {
  const _PlannedReminderNotification({
    required this.id,
    required this.rule,
    required this.scheduledDate,
    this.matchDateTimeComponents,
  });

  final int id;
  final ReminderRule rule;
  final tz.TZDateTime scheduledDate;
  final DateTimeComponents? matchDateTimeComponents;
}

class _ManagedNotificationPlan {
  const _ManagedNotificationPlan({
    required this.ids,
    required this.ownerId,
    required this.generation,
    required this.inProgress,
  });

  factory _ManagedNotificationPlan.fromState(Map<String, Object?> state) {
    final owner = state['owner_id']?.toString().trim();
    final rawGeneration = (state['generation'] as num?)?.toInt() ?? 0;
    return _ManagedNotificationPlan(
      ids: ((state['ids'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((item) => item.toInt())
          .where((id) => id >= 0 && id <= 0x7fffffff)
          .toSet(),
      ownerId: owner == null || owner.isEmpty ? null : owner,
      generation: rawGeneration < 0 ? 0 : rawGeneration,
      inProgress: state['in_progress'] == true,
    );
  }

  final Set<int> ids;
  final String? ownerId;
  final int generation;
  final bool inProgress;
}

class _ValidatedNotificationRoute {
  const _ValidatedNotificationRoute({required this.route, required this.scope});

  final String route;
  final AccountScopeSnapshot scope;
}

class NotificationGateway {
  NotificationGateway({
    required LocalDatabase database,
    FlutterLocalNotificationsPlugin? plugin,
    Future<void> Function()? initializeForTesting,
    Future<void> Function(int id)? cancelForTesting,
  }) : _database = database,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _initializeForTesting = initializeForTesting,
       _cancelForTesting = cancelForTesting;

  final LocalDatabase _database;
  final FlutterLocalNotificationsPlugin _plugin;
  final Future<void> Function()? _initializeForTesting;
  final Future<void> Function(int id)? _cancelForTesting;
  final StreamController<String> _routeController =
      StreamController<String>.broadcast(sync: true);
  String? _initialRoute;
  AccountScopeSnapshot? _initialRouteScope;
  static const _managedIdsStateKey = 'managed_notification_ids_v1';
  Future<void> _operationTail = Future<void>.value();

  Stream<String> get routeRequests => _routeController.stream;

  String? takeInitialRoute() {
    final value = _initialRoute;
    final scope = _initialRouteScope;
    _initialRoute = null;
    _initialRouteScope = null;
    return value != null &&
            scope != null &&
            _database.accountScope.isCurrent(scope)
        ? value
        : null;
  }

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(zone));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }
    String? launchPayload;
    int? launchNotificationId;
    final initializeOverride = _initializeForTesting;
    if (initializeOverride != null) {
      await initializeOverride();
    } else {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          unawaited(
            _acceptNotificationPayload(
              response.payload,
              notificationId: response.id,
              initial: false,
            ),
          );
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        launchPayload = launch?.notificationResponse?.payload;
        launchNotificationId = launch?.notificationResponse?.id;
      }
    }
    final currentScope = _database.accountScope.current;
    final managedPlan = await _managedPlan();
    if (managedPlan != null) {
      if (managedPlan.inProgress ||
          (managedPlan.ids.isNotEmpty &&
              managedPlan.ownerId != currentScope?.userId)) {
        // A process can stop after an auth handoff but before the foreground
        // controller cancels the former owner's OS notifications. The owner
        // stamp makes cold-start cleanup deterministic.
        final failed = await _cancelIds(managedPlan.ids);
        await _writeManagedPlan(
          failed,
          ownerId: failed.isEmpty ? null : managedPlan.ownerId,
          generation: managedPlan.generation + 1,
          inProgress: failed.isNotEmpty,
        );
      }
    } else if (currentScope != null) {
      try {
        final legacyPlan = await _database.readState(
          'reminder_notification_plan',
          accountScope: currentScope,
        );
        final ids = (legacyPlan?['ids'] as List?)?.whereType<num>().toList();
        if (ids != null && ids.isNotEmpty) {
          await _writeManagedPlan(
            ids.map((item) => item.toInt()).toSet(),
            ownerId: currentScope.userId,
            generation: 1,
            inProgress: false,
          );
        }
      } on Object {
        // Legacy adoption is best effort and must not make offline startup fail.
      }
    }
    if (launchPayload != null) {
      await _acceptNotificationPayload(
        launchPayload,
        notificationId: launchNotificationId,
        initial: true,
      );
    }
  }

  Future<ReminderPermission> permissionStatus() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled();
      return enabled == true
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final options = await ios?.checkPermissions();
      return options?.isEnabled == true
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    return ReminderPermission.denied;
  }

  Future<ReminderPermission> requestPermission() async {
    bool? granted;
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      granted = await android?.requestNotificationsPermission();
      if (granted == true &&
          await android?.canScheduleExactNotifications() != true) {
        await android?.requestExactAlarmsPermission();
      }
    } else if (Platform.isIOS) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return granted == true
        ? ReminderPermission.granted
        : ReminderPermission.denied;
  }

  Future<ReminderSchedulingResult> reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) => _serialize(
    () => _reschedule(
      rules: rules,
      prayerRepository: prayerRepository,
      locale: locale,
      accountScope: accountScope,
    ),
  );

  Future<ReminderSchedulingResult> _reschedule({
    required List<ReminderRule> rules,
    required PrayerRepository prayerRepository,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) async {
    final scope = accountScope;
    _database.ensureCurrent(scope);
    final permission = await permissionStatus();
    _database.ensureCurrent(scope);
    if (permission != ReminderPermission.granted) {
      await _cancelManagedNotifications(accountScope: scope);
      return ReminderSchedulingResult(
        permission: permission,
        exact: false,
        scheduled: 0,
      );
    }

    var exact = true;
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      exact = await android?.canScheduleExactNotifications() ?? false;
    }
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final copy = ReminderNotificationCopy.forLocale(locale);
    final candidates = <_PlannedReminderNotification>[];

    for (final rule in rules.where(
      (item) =>
          item.active && item.isEnabled && item.type != ReminderType.prayer,
    )) {
      final location = _locationFor(rule);
      for (var weekday = 1; weekday <= 7; weekday++) {
        if (!reminderRunsOnWeekday(rule.weekdaysMask, weekday)) continue;
        final id = reminderNotificationId(rule.id, 'weekday:$weekday');
        final time = rule.schedule.timeParts;
        candidates.add(
          _PlannedReminderNotification(
            id: id,
            rule: rule,
            scheduledDate: nextWeeklyOccurrence(
              location: location,
              weekday: weekday,
              hour: time.hour,
              minute: time.minute,
            ),
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          ),
        );
      }
    }

    final prayerRules = rules
        .where(
          (item) =>
              item.active && item.isEnabled && item.type == ReminderType.prayer,
        )
        .toList(growable: false);
    if (prayerRules.isNotEmpty) {
      final schedules = await prayerRepository.calculateHorizon(
        days: prayerSchedulingHorizonDays(isIOS: Platform.isIOS),
        accountScope: scope,
      );
      _database.ensureCurrent(scope);
      for (final rule in prayerRules) {
        for (final schedule in schedules) {
          if (!reminderRunsOnWeekday(
            rule.weekdaysMask,
            schedule.date.weekday,
          )) {
            continue;
          }
          final prayerEvent = rule.schedule.prayerEvent ?? 'fajr';
          final prayerTime = schedule.times[prayerEvent];
          if (prayerTime == null) continue;
          final location = _safeLocation(schedule.timezone);
          final utcInstant = schedule.timesUtc[prayerEvent];
          final scheduledDate =
              (utcInstant == null
                      ? tz.TZDateTime(
                          location,
                          prayerTime.year,
                          prayerTime.month,
                          prayerTime.day,
                          prayerTime.hour,
                          prayerTime.minute,
                        )
                      : tz.TZDateTime.from(utcInstant, location))
                  .add(Duration(minutes: rule.schedule.prayerOffsetMinutes));
          if (!scheduledDate.isAfter(tz.TZDateTime.now(location))) continue;
          final occurrence =
              '${schedule.date.year}-${schedule.date.month}-${schedule.date.day}:$prayerEvent';
          final id = reminderNotificationId(rule.id, occurrence);
          candidates.add(
            _PlannedReminderNotification(
              id: id,
              rule: rule,
              scheduledDate: scheduledDate,
            ),
          );
        }
      }
    }

    candidates.sort(
      (left, right) =>
          left.scheduledDate.toUtc().compareTo(right.scheduledDate.toUtc()),
    );
    final selected = limitPendingNotificationPlan(
      candidates,
      isIOS: Platform.isIOS,
    );
    final plannedIds = selected.map((item) => item.id).toSet();
    final previousPlan =
        await _managedPlan() ??
        const _ManagedNotificationPlan(
          ids: <int>{},
          ownerId: null,
          generation: 0,
          inProgress: false,
        );
    _database.ensureCurrent(scope);
    final previous = previousPlan.ids;
    final generation = previousPlan.generation + 1;
    // Record every ID that may exist before mutating the OS schedule. If the
    // process stops mid-plan, the next cancellation still knows all IDs.
    await _writeManagedPlan(
      <int>{...previous, ...plannedIds},
      ownerId: scope.userId,
      generation: generation,
      inProgress: true,
    );
    _database.ensureCurrent(scope);
    final failedStaleIds = <int>{};
    for (final staleId in previous.difference(plannedIds)) {
      _database.ensureCurrent(scope);
      failedStaleIds.addAll(
        await _cancelIds(<int>{staleId}, accountScope: scope),
      );
    }
    for (final item in selected) {
      _database.ensureCurrent(scope);
      await _plugin.zonedSchedule(
        id: item.id,
        title: copy.titleFor(item.rule),
        body: copy.bodyFor(item.rule),
        scheduledDate: item.scheduledDate,
        notificationDetails: _details(item.rule.signal),
        androidScheduleMode: mode,
        matchDateTimeComponents: item.matchDateTimeComponents,
        payload: _payloadFor(
          item.rule,
          ownerId: scope.userId,
          generation: generation,
        ),
      );
    }
    _database.ensureCurrent(scope);
    final incompleteIds = <int>{...plannedIds, ...failedStaleIds};
    await _writeManagedPlan(
      incompleteIds,
      ownerId: scope.userId,
      generation: generation,
      inProgress: failedStaleIds.isNotEmpty,
    );
    _database.ensureCurrent(scope);
    await _database.writeState('reminder_notification_plan', <String, Object?>{
      'ids': plannedIds.toList(growable: false),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'prayer_horizon_days': prayerRules.isEmpty
          ? 0
          : prayerSchedulingHorizonDays(isIOS: Platform.isIOS),
      'candidate_count': candidates.length,
      'capacity_limit': Platform.isIOS ? iosPendingNotificationLimit : null,
      'timezone': tz.local.name,
    }, accountScope: scope);
    return ReminderSchedulingResult(
      permission: permission,
      exact: exact,
      scheduled: plannedIds.length,
    );
  }

  Future<void> cancelAllManaged() => _serialize(_cancelManagedNotifications);

  Future<void> _cancelManagedNotifications({
    AccountScopeSnapshot? accountScope,
  }) async {
    if (accountScope != null) _database.ensureCurrent(accountScope);
    final plan = await _managedPlan();
    if (accountScope != null) _database.ensureCurrent(accountScope);
    final generation = (plan?.generation ?? 0) + 1;
    if (plan != null && plan.ids.isNotEmpty) {
      // Cancellation is also a two-phase OS mutation. A crash between IDs
      // must leave a recoverable union rather than a falsely completed plan.
      await _writeManagedPlan(
        plan.ids,
        ownerId: plan.ownerId,
        generation: generation,
        inProgress: true,
      );
      if (accountScope != null) _database.ensureCurrent(accountScope);
    }
    final failed = await _cancelIds(
      plan?.ids ?? const <int>{},
      accountScope: accountScope,
    );
    if (accountScope != null) _database.ensureCurrent(accountScope);
    await _writeManagedPlan(
      failed,
      ownerId: failed.isEmpty ? null : plan?.ownerId,
      generation: generation,
      inProgress: failed.isNotEmpty,
    );
    if (accountScope != null) _database.ensureCurrent(accountScope);
  }

  Future<Set<int>> _cancelIds(
    Set<int> ids, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final failed = <int>{};
    for (final id in ids) {
      if (accountScope != null) _database.ensureCurrent(accountScope);
      try {
        final cancelOverride = _cancelForTesting;
        if (cancelOverride == null) {
          await _plugin.cancel(id: id);
        } else {
          await cancelOverride(id);
        }
      } on Object {
        failed.add(id);
      }
    }
    return failed;
  }

  Future<_ManagedNotificationPlan?> _managedPlan() async {
    final state = await _database.readDeviceState(_managedIdsStateKey);
    return state == null ? null : _ManagedNotificationPlan.fromState(state);
  }

  Future<void> _writeManagedPlan(
    Set<int> ids, {
    required String? ownerId,
    required int generation,
    required bool inProgress,
  }) => _database.writeDeviceState(_managedIdsStateKey, <String, Object?>{
    'ids': ids.toList(growable: false),
    'owner_id': ownerId,
    'generation': generation,
    'in_progress': inProgress,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  tz.Location _locationFor(ReminderRule rule) =>
      rule.timezoneMode == ReminderTimezoneMode.fixed &&
          rule.timezoneName != null
      ? _safeLocation(rule.timezoneName!)
      : tz.local;

  tz.Location _safeLocation(String value) {
    try {
      return tz.getLocation(value);
    } on Object {
      return tz.local;
    }
  }

  NotificationDetails _details(ReminderSignal signal) {
    final silent = signal == ReminderSignal.silent;
    final vibrate = signal != ReminderSignal.silent;
    final sound = signal == ReminderSignal.sound;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'iqro_reminders_${signal.name}',
        switch (signal) {
          ReminderSignal.sound => 'IQRO reminders with sound',
          ReminderSignal.vibration => 'IQRO vibrating reminders',
          ReminderSignal.silent => 'IQRO silent reminders',
        },
        channelDescription: 'Prayer and Quran reminders',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        playSound: sound,
        enableVibration: vibrate,
        silent: silent,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: sound,
      ),
    );
  }

  String _routeFor(ReminderRule rule) => switch (rule.type) {
    ReminderType.prayer => '/prayer',
    ReminderType.quranReading => '/app?tab=1',
    ReminderType.quranReview =>
      '/reader/${rule.reviewTarget?.start.surah ?? 1}?ayah=${rule.reviewTarget?.start.ayah ?? 1}',
  };

  String _payloadFor(
    ReminderRule rule, {
    required String ownerId,
    required int generation,
  }) => jsonEncode(<String, Object?>{
    'version': 1,
    'owner_id': ownerId,
    'generation': generation,
    'route': _routeFor(rule),
  });

  @visibleForTesting
  Future<void> acceptNotificationPayloadForTesting(
    String? payload, {
    int? notificationId,
    bool initial = false,
  }) => _acceptNotificationPayload(
    payload,
    notificationId: notificationId,
    initial: initial,
  );

  Future<void> _acceptNotificationPayload(
    String? payload, {
    required int? notificationId,
    required bool initial,
  }) async {
    final validated = await _validatedRoute(
      payload,
      notificationId: notificationId,
    );
    if (validated == null) return;
    try {
      _database.ensureCurrent(validated.scope);
    } on AccountScopeChanged {
      return;
    }
    if (initial) {
      _initialRoute = validated.route;
      _initialRouteScope = validated.scope;
    } else {
      _routeController.add(validated.route);
    }
  }

  Future<_ValidatedNotificationRoute?> _validatedRoute(
    String? payload, {
    required int? notificationId,
  }) async {
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['version'] != 1) return null;
      final ownerId = decoded['owner_id']?.toString();
      final generation = (decoded['generation'] as num?)?.toInt();
      final route = decoded['route']?.toString();
      if (ownerId == null ||
          ownerId.isEmpty ||
          generation == null ||
          generation < 1 ||
          route == null ||
          !route.startsWith('/') ||
          route.startsWith('//')) {
        return null;
      }
      final scope = _database.accountScope.current;
      if (scope == null || scope.userId != ownerId) return null;
      final plan = await _managedPlan();
      _database.ensureCurrent(scope);
      if (plan == null ||
          plan.inProgress ||
          plan.ownerId != ownerId ||
          plan.generation != generation ||
          (notificationId != null && !plan.ids.contains(notificationId))) {
        return null;
      }
      return _ValidatedNotificationRoute(route: route, scope: scope);
    } on Object {
      return null;
    }
  }
}

const iosPendingNotificationLimit = 64;

List<T> limitPendingNotificationPlan<T>(
  List<T> chronologicallyOrdered, {
  required bool isIOS,
}) {
  if (!isIOS || chronologicallyOrdered.length <= iosPendingNotificationLimit) {
    return List<T>.unmodifiable(chronologicallyOrdered);
  }
  return List<T>.unmodifiable(
    chronologicallyOrdered.take(iosPendingNotificationLimit),
  );
}

int prayerSchedulingHorizonDays({required bool isIOS}) => isIOS ? 8 : 32;

int reminderNotificationId(String ruleId, String occurrence) {
  final bytes = sha256.convert(utf8.encode('$ruleId|$occurrence')).bytes;
  return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
      0x7fffffff;
}

tz.TZDateTime nextWeeklyOccurrence({
  required tz.Location location,
  required int weekday,
  required int hour,
  required int minute,
  tz.TZDateTime? now,
}) {
  final current = now ?? tz.TZDateTime.now(location);
  final delta = (weekday - current.weekday + 7) % 7;
  var candidate = tz.TZDateTime(
    location,
    current.year,
    current.month,
    current.day + delta,
    hour,
    minute,
  );
  if (!candidate.isAfter(current)) {
    candidate = candidate.add(const Duration(days: 7));
  }
  return candidate;
}

class ReminderNotificationCopy {
  const ReminderNotificationCopy(this.locale);

  factory ReminderNotificationCopy.forLocale(String locale) =>
      ReminderNotificationCopy(
        const <String>{'ru', 'ar', 'tr'}.contains(locale) ? locale : 'en',
      );

  final String locale;

  String titleFor(ReminderRule rule) => switch ((locale, rule.type)) {
    ('ru', ReminderType.prayer) => 'Время намаза',
    ('ru', ReminderType.quranReview) => 'Повторение Корана',
    ('ru', _) => 'Время чтения Корана',
    ('ar', ReminderType.prayer) => 'وقت الصلاة',
    ('ar', ReminderType.quranReview) => 'مراجعة القرآن',
    ('ar', _) => 'وقت قراءة القرآن',
    ('tr', ReminderType.prayer) => 'Namaz vakti',
    ('tr', ReminderType.quranReview) => 'Kur’an tekrarı',
    ('tr', _) => 'Kur’an okuma zamanı',
    (_, ReminderType.prayer) => 'Prayer time',
    (_, ReminderType.quranReview) => 'Quran review',
    _ => 'Time to read the Quran',
  };

  String bodyFor(ReminderRule rule) {
    if (rule.type == ReminderType.prayer) {
      final name = _prayerName(rule.schedule.prayerEvent ?? 'fajr');
      return switch (locale) {
        'ru' => 'Наступило время молитвы: $name',
        'ar' => 'حان وقت صلاة $name',
        'tr' => '$name namazının vakti geldi',
        _ => 'It is time for $name prayer',
      };
    }
    final target = rule.reviewTarget;
    if (target != null) {
      final range =
          '${target.start.surah}:${target.start.ayah}–${target.end.surah}:${target.end.ayah}';
      return switch (locale) {
        'ru' => 'Пора повторить аяты $range',
        'ar' => 'حان وقت مراجعة الآيات $range',
        'tr' => '$range ayetlerini tekrar etme zamanı',
        _ => 'Time to review verses $range',
      };
    }
    return switch (locale) {
      'ru' => 'Небольшое чтение поддержит ежедневную привычку',
      'ar' => 'قراءة قصيرة تحافظ على عادتك اليومية',
      'tr' => 'Kısa bir okuma günlük alışkanlığını korur',
      _ => 'A short reading keeps your daily habit going',
    };
  }

  String _prayerName(String code) {
    const names = <String, Map<String, String>>{
      'ru': <String, String>{
        'fajr': 'Фаджр',
        'dhuhr': 'Зухр',
        'asr': 'Аср',
        'maghrib': 'Магриб',
        'isha': 'Иша',
      },
      'ar': <String, String>{
        'fajr': 'الفجر',
        'dhuhr': 'الظهر',
        'asr': 'العصر',
        'maghrib': 'المغرب',
        'isha': 'العشاء',
      },
      'tr': <String, String>{
        'fajr': 'Sabah',
        'dhuhr': 'Öğle',
        'asr': 'İkindi',
        'maghrib': 'Akşam',
        'isha': 'Yatsı',
      },
      'en': <String, String>{
        'fajr': 'Fajr',
        'dhuhr': 'Dhuhr',
        'asr': 'Asr',
        'maghrib': 'Maghrib',
        'isha': 'Isha',
      },
    };
    return names[locale]?[code] ?? names['en']![code] ?? code;
  }
}
