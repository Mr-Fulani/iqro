import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:iqro_mobile/features/reminders/reminder_repository.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('only retryable reminder failures are persisted to outbox', () {
    expect(
      shouldPersistReminderMutation(const ApiException(message: 'offline')),
      isTrue,
    );
    expect(
      shouldPersistReminderMutation(
        const ApiException(message: 'busy', statusCode: 503),
      ),
      isTrue,
    );
    expect(
      shouldPersistReminderMutation(
        const ApiException(message: 'rate limited', statusCode: 429),
      ),
      isTrue,
    );
    expect(
      shouldPersistReminderMutation(
        const ApiException(message: 'invalid', statusCode: 400),
      ),
      isFalse,
    );
    expect(
      shouldPersistReminderMutation(
        const ApiException(message: 'unauthorized', statusCode: 401),
      ),
      isFalse,
    );
  });

  test('parses the authoritative backend reminder shape', () {
    final rule = ReminderRule.fromJson(<String, Object?>{
      'id': '01900000-0000-7000-8000-000000000001',
      'reminder_type': 'quran_review',
      'schedule': <String, Object?>{
        'kind': 'local_time',
        'local_time': '07:30:00',
      },
      'review_target': <String, Object?>{
        'start': <String, Object?>{
          'id': 'a',
          'surah_number': 2,
          'ayah_number': 1,
        },
        'end': <String, Object?>{
          'id': 'b',
          'surah_number': 2,
          'ayah_number': 7,
        },
      },
      'weekdays_mask': 31,
      'timezone': <String, Object?>{'mode': 'fixed', 'name': 'Europe/Istanbul'},
      'signal': 'vibration',
      'is_enabled': true,
      'revision': 4,
      'client_updated_at': '2026-08-31T06:00:00Z',
      'deleted_at': null,
    });

    expect(rule.type, ReminderType.quranReview);
    expect(rule.schedule.timeParts, (hour: 7, minute: 30));
    expect(rule.reviewTarget?.end.ayah, 7);
    expect(rule.timezoneMode, ReminderTimezoneMode.fixed);
    expect(rule.signal, ReminderSignal.vibration);
    expect(reminderRunsOnWeekday(rule.weekdaysMask, DateTime.friday), isTrue);
    expect(
      reminderRunsOnWeekday(rule.weekdaysMask, DateTime.saturday),
      isFalse,
    );
  });

  test('serializes a complete create payload without server-only fields', () {
    final rule = ReminderRule(
      id: '01900000-0000-7000-8000-000000000001',
      type: ReminderType.prayer,
      schedule: const ReminderSchedule.prayer(
        prayerEvent: 'fajr',
        prayerOffsetMinutes: -10,
      ),
      weekdaysMask: 127,
      timezoneMode: ReminderTimezoneMode.deviceLocal,
      signal: ReminderSignal.sound,
      isEnabled: true,
      revision: 0,
      clientUpdatedAt: DateTime.utc(2026, 8, 31),
    );

    expect(rule.functionalJson['reminder_type'], 'prayer');
    expect(rule.functionalJson['delivery_mode'], isNull);
    expect(rule.schedule.toJson(), <String, Object?>{
      'kind': 'prayer',
      'prayer_event': 'fajr',
      'prayer_offset_minutes': -10,
    });
  });

  test('only a sounding reminder at the prayer time calls the adhan', () {
    ReminderRule rule({
      ReminderType type = ReminderType.prayer,
      int offset = 0,
      ReminderSignal signal = ReminderSignal.sound,
    }) => ReminderRule(
      id: '01900000-0000-7000-8000-000000000002',
      type: type,
      schedule: ReminderSchedule.prayer(
        prayerEvent: 'fajr',
        prayerOffsetMinutes: offset,
      ),
      weekdaysMask: 127,
      timezoneMode: ReminderTimezoneMode.deviceLocal,
      signal: signal,
      isEnabled: true,
      revision: 0,
      clientUpdatedAt: DateTime.utc(2026, 11, 1),
    );

    const selected = ReminderAdhan.madinah;
    expect(rule().adhanFor(selected), ReminderAdhan.madinah);
    expect(rule(offset: -10).adhanFor(selected), ReminderAdhan.none);
    expect(
      rule(signal: ReminderSignal.vibration).adhanFor(selected),
      ReminderAdhan.none,
    );
    expect(
      rule(type: ReminderType.quranReading).adhanFor(selected),
      ReminderAdhan.none,
    );
    expect(rule().adhanFor(ReminderAdhan.none), ReminderAdhan.none);
  });

  test('weekly planner preserves local wall-clock time across DST', () {
    final location = tz.getLocation('Europe/Berlin');
    final beforeDst = tz.TZDateTime(location, 2026, 3, 23, 9);
    final occurrence = nextWeeklyOccurrence(
      location: location,
      weekday: DateTime.sunday,
      hour: 8,
      minute: 15,
      now: beforeDst,
    );

    expect(occurrence.weekday, DateTime.sunday);
    expect(occurrence.hour, 8);
    expect(occurrence.minute, 15);
  });

  test('notification identity is stable and occurrence-specific', () {
    final first = reminderNotificationId('rule', 'weekday:1');
    expect(reminderNotificationId('rule', 'weekday:1'), first);
    expect(reminderNotificationId('rule', 'weekday:2'), isNot(first));
    expect(first, inInclusiveRange(0, 0x7fffffff));
  });

  test('prayer horizon respects Android continuity and iOS pending cap', () {
    expect(prayerSchedulingHorizonDays, 32);

    final candidates = List<int>.generate(80, (index) => index);
    expect(
      limitPendingNotificationPlan(candidates, isIOS: true),
      orderedEquals(List<int>.generate(64, (index) => index)),
    );
    expect(
      limitPendingNotificationPlan(candidates, isIOS: false),
      orderedEquals(candidates),
    );
  });

  test(
    'on iOS weekly reminders keep their places and prayers fill the rest',
    () {
      // 160 prayers in time order (0-159) and two weekly reminders whose next
      // time is late (500, 501): each repeats and takes one place for good.
      final candidates = <int>[
        ...List<int>.generate(160, (index) => index),
        500,
        501,
      ];
      bool weekly(int item) => item >= 500;

      final kept = limitPendingNotificationPlan(
        candidates,
        isIOS: true,
        repeats: weekly,
        reserved: 1,
      );

      expect(kept, hasLength(63));
      expect(kept.where(weekly), <int>[500, 501]);
      // One place stays for the note that the prayer reminders run out.
      expect(
        kept.where((item) => !weekly(item)),
        List<int>.generate(61, (i) => i),
      );
      expect(
        limitPendingNotificationPlan(
          candidates,
          isIOS: false,
          repeats: weekly,
          reserved: 1,
        ),
        orderedEquals(candidates),
      );
    },
  );

  test('the note that prayer reminders run out comes a day ahead', () {
    final now = tz.TZDateTime.utc(2026, 11, 27, 10);
    expect(
      prayerPlanEndNoticeTime(tz.TZDateTime.utc(2026, 12, 9, 19, 2), now: now),
      tz.TZDateTime.utc(2026, 12, 8, 19, 2),
    );
    // A plan shorter than a day: right after its last reminder.
    expect(
      prayerPlanEndNoticeTime(tz.TZDateTime.utc(2026, 11, 27, 22), now: now),
      tz.TZDateTime.utc(2026, 11, 27, 22, 1),
    );
  });

  test('the note has copy in every app language', () {
    for (final locale in <String>['ru', 'en', 'ar', 'tr', 'de']) {
      final copy = ReminderNotificationCopy.forLocale(locale);
      expect(copy.planEndTitle, isNotEmpty);
      expect(copy.planEndBody, contains('IQRO'));
    }
    expect(
      ReminderNotificationCopy.forLocale('ru').planEndBody,
      'Откройте IQRO, чтобы они приходили дальше.',
    );
  });
}
