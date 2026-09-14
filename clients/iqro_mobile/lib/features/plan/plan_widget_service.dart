import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/auth/account_scope.dart';
import '../../core/widgets/home_widget_pinning.dart';
import '../../core/storage/local_database.dart';
import '../../l10n/generated/app_localizations.dart';
import 'plan_repository.dart';

const planWidgetDataKey = 'home_widget.ReadingPlan.snapshot';
const planWidgetGroup = 'group.forum.iqro.app';

abstract interface class PlanWidgetGateway {
  Future<void> write(Map<String, Object?> snapshot);
  Future<HomeWidgetPinResult> requestPin();
}

class HomePlanWidgetGateway implements PlanWidgetGateway {
  const HomePlanWidgetGateway();

  @override
  Future<void> write(Map<String, Object?> snapshot) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await HomeWidget.saveWidgetData<String>(
      planWidgetDataKey,
      jsonEncode(snapshot),
      appGroupId: planWidgetGroup,
    );
    await HomeWidget.updateWidget(
      androidName: 'ReadingPlanHomeWidgetReceiver',
      iOSName: 'ReadingPlanHomeWidget',
    );
    // Expire yesterday's progress even when Flutter is not running.
    if (Platform.isAndroid) {
      final expiry = snapshot['validUntil'] as int?;
      if (expiry != null && expiry > DateTime.now().millisecondsSinceEpoch) {
        await HomeWidget.scheduleWidgetUpdates([
          DateTime.fromMillisecondsSinceEpoch(expiry),
        ], androidName: 'ReadingPlanHomeWidgetReceiver');
      } else {
        await HomeWidget.cancelScheduledWidgetUpdates(
          androidName: 'ReadingPlanHomeWidgetReceiver',
        );
      }
    }
  }

  @override
  Future<HomeWidgetPinResult> requestPin() =>
      homeWidgetPinning.request('ReadingPlanHomeWidgetReceiver');
}

class PlanWidgetService {
  PlanWidgetService({
    required LocalDatabase database,
    PlanWidgetGateway gateway = const HomePlanWidgetGateway(),
    DateTime Function()? clock,
  }) : _database = database,
       _gateway = gateway,
       _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final PlanWidgetGateway _gateway;
  final DateTime Function() _clock;
  Future<void> _queue = Future<void>.value();

  Future<void> update({
    required DailyPlan plan,
    required String locale,
    required AccountScopeSnapshot accountScope,
  }) => _enqueue(() async {
    _database.ensureCurrent(accountScope);
    await _gateway.write(
      buildPlanWidgetSnapshot(plan: plan, locale: locale, now: _clock()),
    );
    _database.ensureCurrent(accountScope);
  });

  // Serialized with writes, so a previous account cannot overwrite the clear.
  Future<void> clear({required String locale}) => _enqueue(
    () => _gateway.write(
      buildPlanWidgetSnapshot(plan: null, locale: locale, now: _clock()),
    ),
  );

  Future<HomeWidgetPinResult> requestPin() => _gateway.requestPin();

  Future<void> _enqueue(Future<void> Function() write) {
    final next = _queue.catchError((Object _) {}).then((_) => write());
    _queue = next;
    return next;
  }
}

Map<String, Object?> buildPlanWidgetSnapshot({
  required DailyPlan? plan,
  required String locale,
  required DateTime now,
}) {
  final language = locale.toLowerCase().split(RegExp('[-_]')).first;
  final normalized = ['ru', 'en', 'ar', 'tr'].contains(language)
      ? language
      : 'en';
  final copy = lookupAppLocalizations(Locale(normalized));
  final result = <String, Object?>{
    'locale': normalized,
    'title': copy.dailyPlan,
    'emptyLabel': copy.openPlan,
    'afterPrayerLabel': copy.afterPrayer,
    'pageUnit': copy.pages,
    'validUntil': 0,
    'isCurrent': false,
  };
  if (plan == null || plan.localDate.isEmpty) return result;
  late final tz.Location zone;
  try {
    zone = tz.getLocation(plan.timezoneName);
  } on Object {
    return result;
  }
  final localNow = tz.TZDateTime.from(now, zone);
  if (plan.localDate != DateFormat('yyyy-MM-dd').format(localNow)) {
    return result;
  }
  if (!plan.target.isFinite || plan.target <= 0 || !plan.achieved.isFinite) {
    return result;
  }
  final achieved = plan.achieved.clamp(0.0, double.infinity);
  final remaining = (plan.target - achieved).clamp(0.0, plan.target);
  final number = NumberFormat('0.#', normalized);
  final unit = switch (plan.metric) {
    ReadingGoalMetric.pages => copy.pages,
    ReadingGoalMetric.minutes => copy.minutes,
    ReadingGoalMetric.ayahs => copy.ayahs,
  };
  final prayerNames = [
    copy.fajr,
    copy.dhuhr,
    copy.asr,
    copy.maghrib,
    copy.isha,
  ];
  const codes = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
  result.addAll({
    'isCurrent': true,
    'validUntil': tz.TZDateTime(
      zone,
      localNow.year,
      localNow.month,
      localNow.day + 1,
    ).millisecondsSinceEpoch,
    'achieved': number.format(achieved),
    'targetLine': '/ ${number.format(plan.target)}',
    'unit': unit,
    'remainingLabel': remaining == 0 ? copy.completed : copy.remaining,
    'remaining': number.format(remaining),
    'progress': ((achieved / plan.target).clamp(0.0, 1.0) * 100).round(),
    'rows': [
      for (var i = 0; i < codes.length; i++)
        {
          'label': prayerNames[i],
          'value': number.format(
            (plan.prayerPages[codes[i]] ?? 0).clamp(0, 1000000),
          ),
        },
    ],
  });
  return result;
}
