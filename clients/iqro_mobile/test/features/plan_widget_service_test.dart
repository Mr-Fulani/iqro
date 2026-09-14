import 'dart:async';
import 'package:iqro_mobile/core/widgets/home_widget_pinning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_widget_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);
  final now = DateTime.utc(2026, 9, 14, 10);
  DailyPlan plan({
    ReadingGoalMetric metric = ReadingGoalMetric.pages,
    double achieved = 3,
    String date = '2026-09-14',
    String zone = 'Europe/Istanbul',
  }) => DailyPlan(
    metric: metric,
    target: 6,
    achieved: achieved,
    prayerPages: const {'fajr': 2, 'dhuhr': 1},
    streak: 4,
    localDate: date,
    timezoneName: zone,
  );

  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    for (final metric in ReadingGoalMetric.values) {
      test('$locale $metric uses real goal units and five localized rows', () {
        final snapshot = buildPlanWidgetSnapshot(
          plan: plan(metric: metric),
          locale: locale,
          now: now,
        );
        expect(snapshot['isCurrent'], true);
        expect(snapshot['locale'], locale);
        expect(snapshot['progress'], 50);
        expect(snapshot['achieved'], '3');
        expect(snapshot['remaining'], '3');
        expect(snapshot['unit'], isNotEmpty);
        expect(snapshot['rows'], hasLength(5));
        final rows = snapshot['rows'] as List;
        expect(rows[0]['value'], '2');
        expect(rows[4]['value'], '0');
        expect(
          snapshot['validUntil'],
          DateTime.utc(2026, 9, 14, 21).millisecondsSinceEpoch,
        );
      });
    }
  }
  test('yesterday and unknown dates never masquerade as today', () {
    for (final stale in [plan(date: '2026-09-13'), plan(date: ''), null]) {
      final snapshot = buildPlanWidgetSnapshot(
        plan: stale,
        locale: 'ru',
        now: now,
      );
      expect(snapshot['isCurrent'], false);
      expect(snapshot.containsKey('achieved'), false);
      expect(snapshot.containsKey('rows'), false);
      expect(snapshot['emptyLabel'], isNotEmpty);
    }
  });
  test(
    'goal completion clamps progress but preserves actual achieved amount',
    () {
      final snapshot = buildPlanWidgetSnapshot(
        plan: plan(achieved: 8),
        locale: 'en',
        now: now,
      );
      expect(snapshot['achieved'], '8');
      expect(snapshot['remaining'], '0');
      expect(snapshot['progress'], 100);
    },
  );
  test('expiry uses plan timezone across daylight-saving changes', () {
    final snapshot = buildPlanWidgetSnapshot(
      plan: plan(date: '2026-03-29', zone: 'Europe/Berlin'),
      locale: 'en',
      now: DateTime.utc(2026, 3, 28, 23),
    );
    expect(snapshot['isCurrent'], true);
    expect(
      snapshot['validUntil'],
      DateTime.utc(2026, 3, 29, 22).millisecondsSinceEpoch,
    );
  });
  test('invalid timezones and invalid goals produce safe empty snapshots', () {
    for (final value in [plan(zone: 'invalid'), plan(achieved: double.nan)]) {
      expect(
        buildPlanWidgetSnapshot(
          plan: value,
          locale: 'en',
          now: now,
        )['isCurrent'],
        false,
      );
    }
  });
  test(
    'queued account clear wins over an in-flight previous-account write',
    () async {
      final database = _Database();
      final gateway = _Gateway();
      final service = PlanWidgetService(
        database: database,
        gateway: gateway,
        clock: () => now,
      );
      final old = database.accountScope.current!;
      final write = service.update(
        plan: plan(),
        locale: 'ru',
        accountScope: old,
      );
      final rejected = expectLater(write, throwsA(isA<AccountScopeChanged>()));
      await gateway.started.future;
      database.accountScope.activate('new-account');
      final clear = service.clear(locale: 'ar');
      gateway.release.complete();
      await rejected;
      await clear;
      expect(gateway.snapshots.last['locale'], 'ar');
      expect(gateway.snapshots.last['isCurrent'], false);
      expect(gateway.snapshots.last.containsKey('achieved'), false);
    },
  );
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('old-account');
  @override
  void ensureCurrent(AccountScopeSnapshot snapshot) =>
      accountScope.ensureCurrent(snapshot);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements PlanWidgetGateway {
  final snapshots = <Map<String, Object?>>[];
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(Map<String, Object?> snapshot) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    snapshots.add(snapshot);
  }

  @override
  Future<HomeWidgetPinResult> requestPin() async =>
      HomeWidgetPinResult.requested;
}
