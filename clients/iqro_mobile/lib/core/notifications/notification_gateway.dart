import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer/prayer_repository.dart';
import '../../features/reminders/reminder_models.dart';
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

class NotificationGateway {
  NotificationGateway({
    required LocalDatabase database,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _database = database,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final LocalDatabase _database;
  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _routeController =
      StreamController<String>.broadcast();
  String? _initialRoute;

  Stream<String> get routeRequests => _routeController.stream;

  String? takeInitialRoute() {
    final value = _initialRoute;
    _initialRoute = null;
    return value;
  }

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(zone));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }
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
        final route = response.payload;
        if (route != null && route.startsWith('/')) {
          _routeController.add(route);
        }
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final route = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        route != null &&
        route.startsWith('/')) {
      _initialRoute = route;
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
  }) async {
    final permission = await permissionStatus();
    if (permission != ReminderPermission.granted) {
      await _cancelManagedNotifications();
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
    final plannedIds = <int>{};

    for (final rule in rules.where(
      (item) =>
          item.active && item.isEnabled && item.type != ReminderType.prayer,
    )) {
      final location = _locationFor(rule);
      for (var weekday = 1; weekday <= 7; weekday++) {
        if (!reminderRunsOnWeekday(rule.weekdaysMask, weekday)) continue;
        final id = reminderNotificationId(rule.id, 'weekday:$weekday');
        plannedIds.add(id);
        final time = rule.schedule.timeParts;
        await _plugin.zonedSchedule(
          id: id,
          title: copy.titleFor(rule),
          body: copy.bodyFor(rule),
          scheduledDate: nextWeeklyOccurrence(
            location: location,
            weekday: weekday,
            hour: time.hour,
            minute: time.minute,
          ),
          notificationDetails: _details(rule.signal),
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: _payloadFor(rule),
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
      final schedules = await prayerRepository.calculateHorizon();
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
          final scheduledDate = tz.TZDateTime(
            location,
            prayerTime.year,
            prayerTime.month,
            prayerTime.day,
            prayerTime.hour,
            prayerTime.minute,
          ).add(Duration(minutes: rule.schedule.prayerOffsetMinutes));
          if (!scheduledDate.isAfter(tz.TZDateTime.now(location))) continue;
          final occurrence =
              '${schedule.date.year}-${schedule.date.month}-${schedule.date.day}:$prayerEvent';
          final id = reminderNotificationId(rule.id, occurrence);
          plannedIds.add(id);
          await _plugin.zonedSchedule(
            id: id,
            title: copy.titleFor(rule),
            body: copy.bodyFor(rule),
            scheduledDate: scheduledDate,
            notificationDetails: _details(rule.signal),
            androidScheduleMode: mode,
            payload: _payloadFor(rule),
          );
        }
      }
    }

    final previous = await _plannedIds();
    for (final staleId in previous.difference(plannedIds)) {
      await _plugin.cancel(id: staleId);
    }
    await _database.writeState('reminder_notification_plan', <String, Object?>{
      'ids': plannedIds.toList(growable: false),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return ReminderSchedulingResult(
      permission: permission,
      exact: exact,
      scheduled: plannedIds.length,
    );
  }

  Future<void> _cancelManagedNotifications() async {
    for (final id in await _plannedIds()) {
      await _plugin.cancel(id: id);
    }
    await _database.writeState('reminder_notification_plan', <String, Object?>{
      'ids': const <int>[],
    });
  }

  Future<Set<int>> _plannedIds() async {
    final state = await _database.readState('reminder_notification_plan');
    return ((state?['ids'] as List?) ?? const <Object?>[])
        .whereType<num>()
        .map((item) => item.toInt())
        .toSet();
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

  String _payloadFor(ReminderRule rule) => switch (rule.type) {
    ReminderType.prayer => '/prayer',
    ReminderType.quranReading => '/app?tab=1',
    ReminderType.quranReview =>
      '/reader/${rule.reviewTarget?.start.surah ?? 1}?ayah=${rule.reviewTarget?.start.ayah ?? 1}',
  };
}

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
