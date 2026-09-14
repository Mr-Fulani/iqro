import 'dart:async';

import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/timezone.dart' as tz;

import '../../core/auth/account_scope.dart';
import '../../core/widgets/home_widget_pinning.dart';
import '../../core/storage/local_database.dart';
import '../../core/widgets/prayer_times.home_widget.dart';
import 'prayer_places.dart';
import 'prayer_repository.dart';

const prayerWidgetVisibleDays = 8;

class PrayerWidgetStaticData {
  const PrayerWidgetStaticData({
    required this.title,
    required this.locale,
    required this.sunriseLabel,
    required this.fajrLabel,
    required this.dhuhrLabel,
    required this.asrLabel,
    required this.maghribLabel,
    required this.ishaLabel,
  });

  final String title;
  final String locale;
  final String sunriseLabel;
  final String fajrLabel;
  final String dhuhrLabel;
  final String asrLabel;
  final String maghribLabel;
  final String ishaLabel;
}

class PrayerWidgetTimelineEntry {
  const PrayerWidgetTimelineEntry({
    required this.dateLocation,
    required this.nextLabel,
    required this.nextPrayer,
    this.nextName = '',
    this.nextHour = '—',
    this.nextMinute = '—',
    this.nextEpoch = '',
    this.period = 'day',
    this.sunriseTime = '—',
    required this.fajrTime,
    required this.dhuhrTime,
    required this.asrTime,
    required this.maghribTime,
    required this.ishaTime,
  });

  final String dateLocation;
  final String nextLabel;
  final String nextPrayer;
  final String nextName;
  final String nextHour;
  final String nextMinute;
  final String nextEpoch;
  final String period;
  final String sunriseTime;
  final String fajrTime;
  final String dhuhrTime;
  final String asrTime;
  final String maghribTime;
  final String ishaTime;
}

abstract interface class PrayerWidgetGateway {
  Future<void> write({
    required PrayerWidgetStaticData labels,
    required Map<DateTime, PrayerWidgetTimelineEntry> timeline,
  });

  Future<HomeWidgetPinResult> requestPin();
}

class HomePrayerWidgetGateway implements PrayerWidgetGateway {
  const HomePrayerWidgetGateway();

  @override
  Future<void> write({
    required PrayerWidgetStaticData labels,
    required Map<DateTime, PrayerWidgetTimelineEntry> timeline,
  }) async {
    await PrayerTimesHomeWidget.saveData(
      title: labels.title,
      locale: labels.locale,
      sunriseLabel: labels.sunriseLabel,
      fajrLabel: labels.fajrLabel,
      dhuhrLabel: labels.dhuhrLabel,
      asrLabel: labels.asrLabel,
      maghribLabel: labels.maghribLabel,
      ishaLabel: labels.ishaLabel,
      timedData: <DateTime, PrayerTimesTimedData>{
        for (final item in timeline.entries)
          item.key: PrayerTimesTimedData(
            dateLocation: item.value.dateLocation,
            nextLabel: item.value.nextLabel,
            nextPrayer: item.value.nextPrayer,
            nextName: item.value.nextName,
            nextHour: item.value.nextHour,
            nextMinute: item.value.nextMinute,
            nextEpoch: item.value.nextEpoch,
            period: item.value.period,
            sunriseTime: item.value.sunriseTime,
            fajrTime: item.value.fajrTime,
            dhuhrTime: item.value.dhuhrTime,
            asrTime: item.value.asrTime,
            maghribTime: item.value.maghribTime,
            ishaTime: item.value.ishaTime,
          ),
      },
    );
    await PrayerTimesHomeWidget.updateWidget();
  }

  @override
  Future<HomeWidgetPinResult> requestPin() =>
      homeWidgetPinning.request('PrayerTimesHomeWidgetReceiver');
}

class PrayerWidgetUpdateResult {
  const PrayerWidgetUpdateResult({
    required this.hasSchedule,
    required this.timelineEntries,
  });

  final bool hasSchedule;
  final int timelineEntries;
}

class PrayerWidgetService {
  PrayerWidgetService({
    required PrayerRepository prayer,
    required LocalDatabase database,
    PrayerWidgetGateway gateway = const HomePrayerWidgetGateway(),
    DateTime Function()? clock,
  }) : _prayer = prayer,
       _database = database,
       _gateway = gateway,
       _clock = clock ?? DateTime.now;

  final PrayerRepository _prayer;
  final LocalDatabase _database;
  final PrayerWidgetGateway _gateway;
  final DateTime Function() _clock;
  Future<void> _writeQueue = Future<void>.value();

  Future<PrayerWidgetUpdateResult> update({
    required String locale,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final values = await (
      _prayer.calculateHorizon(
        days: prayerWidgetVisibleDays + 1,
        accountScope: scope,
      ),
      _prayer.storedLocation(accountScope: scope),
    ).wait;
    _database.ensureCurrent(scope);
    final copy = PrayerWidgetCopy.forLocale(locale);
    final city = prayerCityById(values.$2?.cityId);
    final locationName = city?.nameFor(copy.locale) ?? copy.currentLocation;
    final timeline = buildPrayerWidgetTimeline(
      schedules: values.$1,
      locationName: locationName,
      copy: copy,
      now: _clock(),
    );
    final hasSchedule = values.$1.length > 1;
    await _enqueueWrite(scope, labels: copy.staticData, timeline: timeline);
    return PrayerWidgetUpdateResult(
      hasSchedule: hasSchedule,
      timelineEntries: timeline.length,
    );
  }

  Future<HomeWidgetPinResult> requestPin() => _gateway.requestPin();

  Future<void> _enqueueWrite(
    AccountScopeSnapshot scope, {
    required PrayerWidgetStaticData labels,
    required Map<DateTime, PrayerWidgetTimelineEntry> timeline,
  }) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.catchError((Object _) {}).then((_) async {
      try {
        _database.ensureCurrent(scope);
        await _gateway.write(labels: labels, timeline: timeline);
        _database.ensureCurrent(scope);
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class PrayerWidgetCopy {
  const PrayerWidgetCopy({
    required this.locale,
    required this.nextPrayer,
    required this.currentLocation,
    required this.locationRequired,
    required this.staticData,
  });

  factory PrayerWidgetCopy.forLocale(String locale) {
    final normalized = switch (locale
        .toLowerCase()
        .split(RegExp('[-_]'))
        .first) {
      'ar' => 'ar',
      'tr' => 'tr',
      'ru' => 'ru',
      _ => 'en',
    };
    return switch (normalized) {
      'ru' => const PrayerWidgetCopy(
        locale: 'ru',
        nextPrayer: 'через',
        currentLocation: 'Текущее местоположение',
        locationRequired: 'Откройте IQRO и выберите местоположение',
        staticData: PrayerWidgetStaticData(
          title: 'IQRO',
          locale: 'ru',
          sunriseLabel: 'Восход',
          fajrLabel: 'Фаджр',
          dhuhrLabel: 'Зухр',
          asrLabel: 'Аср',
          maghribLabel: 'Магриб',
          ishaLabel: 'Иша',
        ),
      ),
      'ar' => const PrayerWidgetCopy(
        locale: 'ar',
        nextPrayer: 'بعد',
        currentLocation: 'الموقع الحالي',
        locationRequired: 'افتح IQRO واختر موقعك',
        staticData: PrayerWidgetStaticData(
          title: 'IQRO',
          locale: 'ar',
          sunriseLabel: 'الشروق',
          fajrLabel: 'الفجر',
          dhuhrLabel: 'الظهر',
          asrLabel: 'العصر',
          maghribLabel: 'المغرب',
          ishaLabel: 'العشاء',
        ),
      ),
      'tr' => const PrayerWidgetCopy(
        locale: 'tr',
        nextPrayer: 'Kalan süre',
        currentLocation: 'Mevcut konum',
        locationRequired: 'IQRO\'yu açın ve konumunuzu seçin',
        staticData: PrayerWidgetStaticData(
          title: 'IQRO',
          locale: 'tr',
          sunriseLabel: 'Güneş',
          fajrLabel: 'İmsak',
          dhuhrLabel: 'Öğle',
          asrLabel: 'İkindi',
          maghribLabel: 'Akşam',
          ishaLabel: 'Yatsı',
        ),
      ),
      _ => const PrayerWidgetCopy(
        locale: 'en',
        nextPrayer: 'in',
        currentLocation: 'Current location',
        locationRequired: 'Open IQRO and choose your location',
        staticData: PrayerWidgetStaticData(
          title: 'IQRO',
          locale: 'en',
          sunriseLabel: 'Sunrise',
          fajrLabel: 'Fajr',
          dhuhrLabel: 'Dhuhr',
          asrLabel: 'Asr',
          maghribLabel: 'Maghrib',
          ishaLabel: 'Isha',
        ),
      ),
    };
  }

  final String locale;
  final String nextPrayer;
  final String currentLocation;
  final String locationRequired;
  final PrayerWidgetStaticData staticData;

  String prayerName(String code) => switch (code) {
    'fajr' => staticData.fajrLabel,
    'dhuhr' => staticData.dhuhrLabel,
    'asr' => staticData.asrLabel,
    'maghrib' => staticData.maghribLabel,
    _ => staticData.ishaLabel,
  };
}

Map<DateTime, PrayerWidgetTimelineEntry> buildPrayerWidgetTimeline({
  required List<PrayerSchedule> schedules,
  required String locationName,
  required PrayerWidgetCopy copy,
  required DateTime now,
}) {
  if (schedules.length < 2) {
    return <DateTime, PrayerWidgetTimelineEntry>{
      now.subtract(const Duration(seconds: 1)): PrayerWidgetTimelineEntry(
        dateLocation: copy.locationRequired,
        nextLabel: '',
        nextPrayer: '',
        fajrTime: '—',
        dhuhrTime: '—',
        asrTime: '—',
        maghribTime: '—',
        ishaTime: '—',
      ),
    };
  }
  final timeline = <DateTime, PrayerWidgetTimelineEntry>{};
  for (
    var index = 0;
    index < prayerWidgetVisibleDays && index + 1 < schedules.length;
    index++
  ) {
    final schedule = schedules[index];
    final nextDay = schedules[index + 1];
    final zone = tz.getLocation(schedule.timezone);
    final dayStart = tz.TZDateTime(
      zone,
      schedule.date.year,
      schedule.date.month,
      schedule.date.day,
    );
    final nextCodes = <String>['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
    timeline[dayStart] = _timelineEntry(
      schedule: schedule,
      nextCode: 'fajr',
      nextSchedule: schedule,
      locationName: locationName,
      copy: copy,
    );
    for (var prayerIndex = 0; prayerIndex < nextCodes.length; prayerIndex++) {
      final code = nextCodes[prayerIndex];
      final transition = _prayerInstant(schedule, code, zone);
      if (transition == null) continue;
      final hasPrayerToday = prayerIndex + 1 < nextCodes.length;
      timeline[transition] = _timelineEntry(
        schedule: schedule,
        nextCode: hasPrayerToday ? nextCodes[prayerIndex + 1] : 'fajr',
        nextSchedule: hasPrayerToday ? schedule : nextDay,
        locationName: locationName,
        copy: copy,
      );
    }
  }
  return timeline;
}

PrayerWidgetTimelineEntry _timelineEntry({
  required PrayerSchedule schedule,
  required String nextCode,
  required PrayerSchedule nextSchedule,
  required String locationName,
  required PrayerWidgetCopy copy,
}) {
  final date = DateFormat.MMMEd(copy.locale).format(schedule.date);
  final nextTime = _formatPrayerTime(nextSchedule, nextCode, copy.locale);
  final nextInstant = _prayerInstant(
    nextSchedule,
    nextCode,
    tz.getLocation(nextSchedule.timezone),
  );
  final nextParts = nextTime.split(':');
  return PrayerWidgetTimelineEntry(
    dateLocation: '$date · $locationName',
    nextLabel: copy.nextPrayer,
    nextPrayer: '${copy.prayerName(nextCode)} $nextTime',
    nextName: copy.prayerName(nextCode),
    nextHour: nextParts.first,
    nextMinute: nextParts.length == 2 ? nextParts.last : '—',
    nextEpoch: nextInstant?.millisecondsSinceEpoch.toString() ?? '',
    period: nextCode == 'isha' ? 'night' : 'day',
    sunriseTime: _formatPrayerTime(schedule, 'sunrise', copy.locale),
    fajrTime: _formatPrayerTime(schedule, 'fajr', copy.locale),
    dhuhrTime: _formatPrayerTime(schedule, 'dhuhr', copy.locale),
    asrTime: _formatPrayerTime(schedule, 'asr', copy.locale),
    maghribTime: _formatPrayerTime(schedule, 'maghrib', copy.locale),
    ishaTime: _formatPrayerTime(schedule, 'isha', copy.locale),
  );
}

DateTime? _prayerInstant(
  PrayerSchedule schedule,
  String code,
  tz.Location zone,
) {
  final utc = schedule.timesUtc[code];
  if (utc != null) return utc;
  final wallTime = schedule.times[code];
  if (wallTime == null) return null;
  return tz.TZDateTime(
    zone,
    wallTime.year,
    wallTime.month,
    wallTime.day,
    wallTime.hour,
    wallTime.minute,
    wallTime.second,
  );
}

String _formatPrayerTime(PrayerSchedule schedule, String code, String locale) {
  final time = schedule.times[code];
  return time == null ? '—' : DateFormat.Hm(locale).format(time);
}
