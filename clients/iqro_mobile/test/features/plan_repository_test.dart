import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_screen.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('prayer counter saves + and - and blocks overlapping taps', (
    tester,
  ) async {
    final database = _FakeLocalDatabase();
    final scope = await database.captureAccount();
    final remote = _FakePlanRemote();
    final repository = PlanRepository(
      database,
      remote: remote,
      timezoneLoader: () async => 'UTC',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(database),
          audioControllerProvider.overrideWith((ref) => _IdleAudio()),
          activeAccountScopeKeyProvider.overrideWithValue(
            accountScopeKey(scope),
          ),
          planProvider.overrideWith(
            (ref) => PlanController(
              repository,
              database: database,
              accountScope: scope,
              preferredTarget: 6,
              preferredMetric: ReadingGoalMetric.pages,
            ),
          ),
        ],
        child: MaterialApp(
          theme: IqroTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AfterPrayerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final plus = find
        .widgetWithIcon(IconButton, Icons.add_circle_outline)
        .first;
    final minus = find
        .widgetWithIcon(IconButton, Icons.remove_circle_outline)
        .first;
    remote.writeGate = Completer<void>();
    await tester.tap(plus);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    await tester.tap(plus);
    remote.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(remote.checkInCreates, 1);
    expect(remote.prayerCheckIn?['pages'], 1);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(remote.prayerCheckIn?['pages'], 2);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(minus);
    await tester.pumpAndSettle();
    expect(remote.prayerCheckIn?['pages'], 1);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(minus);
    await tester.pumpAndSettle();
    expect(remote.prayerCheckIn, isNull);
    expect(tester.widget<IconButton>(minus).onPressed, isNull);
    expect(find.text('0'), findsNWidgets(5));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AfterPrayerScreen)),
    );
    remote.offline = true;
    await container.read(planProvider.notifier).reload();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AfterPrayerScreen)),
    );
    expect(find.text(l10n.planUnavailable), findsOneWidget);
    remote.offline = false;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.planUnavailable), findsNothing);
    expect(tester.widget<IconButton>(plus).onPressed, isNotNull);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'prayer check-in uses its own timezone and date across midnight',
    () async {
      final remote = _FakePlanRemote()
        ..prayerTimezone = 'America/New_York'
        ..prayerDate = '2026-08-28'
        ..prayerPlan = {'revision': 1, 'pages_per_prayer': 2};
      final repository = PlanRepository(
        _FakeLocalDatabase(),
        remote: remote,
        timezoneLoader: () async => 'Europe/Istanbul',
      );
      final plan = await repository.setPrayerPages('fajr', 1);
      expect(remote.savedPrayerCheckIn?['timezone_name'], 'America/New_York');
      expect(remote.savedPrayerCheckIn?['local_date'], '2026-08-28');
      expect(plan.localDate, '2026-08-29');
      expect(plan.timezoneName, 'Europe/Istanbul');
      final restored = DailyPlan.fromJson(
        plan.copyWith(fromCache: true).toJson(),
      );
      expect(restored.prayerTimezoneName, 'America/New_York');
      expect(restored.prayerLocalDate, '2026-08-28');
    },
  );

  test(
    'offline prayer changes do not mutate from a stale cached revision',
    () async {
      final remote = _FakePlanRemote();
      final repository = PlanRepository(
        _FakeLocalDatabase(),
        remote: remote,
        timezoneLoader: () async => 'UTC',
      );
      await repository.load();
      remote.offline = true;
      await expectLater(repository.setPrayerPages('fajr', 1), throwsStateError);
      expect(remote.savedPrayerPlan, isNull);
      expect(remote.savedPrayerCheckIn, isNull);
    },
  );
  test(
    'server dashboard is authoritative and has a private offline cache',
    () async {
      final database = _FakeLocalDatabase();
      final remote = _FakePlanRemote(
        metric: ReadingGoalMetric.minutes,
        target: 10,
        achieved: 4,
      );
      final repository = PlanRepository(
        database,
        remote: remote,
        timezoneLoader: () async => 'Europe/Istanbul',
      );

      final online = await repository.load(
        preferredMetric: ReadingGoalMetric.pages,
        preferredTarget: 6,
      );
      remote.offline = true;
      final cached = await repository.load();

      expect(remote.requestedTimezone, 'Europe/Istanbul');
      expect(online.metric, ReadingGoalMetric.minutes);
      expect(online.target, 10);
      expect(online.achieved, 4);
      expect(online.streak, 3);
      expect(online.history, hasLength(1));
      expect(cached.fromCache, isTrue);
      expect(cached.metric, ReadingGoalMetric.minutes);
    },
  );

  test(
    'goal edit and manual reading use revisioned backend payloads',
    () async {
      final remote = _FakePlanRemote();
      final repository = PlanRepository(
        _FakeLocalDatabase(),
        remote: remote,
        timezoneLoader: () async => 'Europe/Istanbul',
      );
      final current = await repository.load(
        preferredMetric: ReadingGoalMetric.pages,
        preferredTarget: 6,
      );

      final edited = await repository.setGoal(
        ReadingGoalMetric.ayahs,
        12,
        baseRevision: current.goalRevision,
      );
      final progressed = await repository.addReading(
        5,
        metric: ReadingGoalMetric.ayahs,
      );

      expect(remote.savedGoal?['metric'], 'ayahs');
      expect(remote.savedGoal?['target_amount'], 12);
      expect(remote.savedGoal?['base_revision'], current.goalRevision);
      expect(remote.savedGoal?['timezone_name'], 'Europe/Istanbul');
      expect(edited.metric, ReadingGoalMetric.ayahs);
      expect(remote.savedManual?['metric'], 'ayahs');
      expect(remote.savedManual?['amount'], 5);
      expect(remote.savedManual?['id'], isNotEmpty);
      expect(progressed.achieved, 5);
    },
  );

  test('after-prayer stepper creates a backend plan and check-in', () async {
    final remote = _FakePlanRemote(target: 10);
    final repository = PlanRepository(
      _FakeLocalDatabase(),
      remote: remote,
      timezoneLoader: () async => 'UTC',
    );
    await repository.load(
      preferredMetric: ReadingGoalMetric.pages,
      preferredTarget: 10,
    );

    final updated = await repository.setPrayerPages('fajr', 2);

    expect(remote.savedPrayerPlan?['pages_per_prayer'], 2);
    expect(remote.savedPrayerPlan?['base_revision'], 0);
    expect(remote.savedPrayerCheckIn?['prayer'], 'fajr');
    expect(remote.savedPrayerCheckIn?['pages'], 2);
    expect(remote.savedPrayerCheckIn?['session_id'], isNotEmpty);
    expect(updated.prayerPages['fajr'], 2);
  });

  test('history grouping keeps prayer check-ins out of manual records', () {
    final day = ReadingHistoryDay(
      localDate: DateTime.utc(2026, 9, 21),
      state: 'completed',
      hasReading: true,
      metric: ReadingGoalMetric.pages,
      target: 1,
      achieved: 2,
      automaticSeconds: 120,
      automaticPages: 1,
      automaticAyahs: 4,
      prayerPages: 1,
      prayerCount: 1,
      automaticSessions: 1,
      prayerCheckIns: const <PrayerReadingCheckIn>[
        PrayerReadingCheckIn(
          id: 'check-in-1',
          prayer: 'fajr',
          pages: 1,
          revision: 1,
          readingSessionId: 'prayer-session-1',
        ),
      ],
    );
    final plan = DailyPlan(
      metric: ReadingGoalMetric.pages,
      target: 1,
      achieved: 2,
      prayerPages: const <String, int>{
        'fajr': 1,
        'dhuhr': 0,
        'asr': 0,
        'maghrib': 0,
        'isha': 0,
      },
      streak: 1,
      localDate: '2026-09-21',
      history: <ReadingHistoryDay>[day],
      sessions: <ReadingSession>[
        const ReadingSession(
          id: 'prayer-session-1',
          source: 'manual',
          status: 'completed',
          timezoneName: 'UTC',
          localDate: '2026-09-21',
          activeSeconds: 0,
          creditedPages: 0,
          creditedAyahs: 0,
          manualMetric: ReadingGoalMetric.pages,
          manualAmount: 1,
          revision: 1,
        ),
        const ReadingSession(
          id: 'manual-session-1',
          source: 'manual',
          status: 'completed',
          timezoneName: 'UTC',
          localDate: '2026-09-21',
          activeSeconds: 0,
          creditedPages: 0,
          creditedAyahs: 0,
          manualMetric: ReadingGoalMetric.pages,
          manualAmount: 1,
          revision: 1,
        ),
      ],
    );

    expect(plan.daysForRange(30), hasLength(1));
    final groups = plan.historyGroupsForRange(30);

    expect(groups, hasLength(1));
    expect(groups.single.automaticSessions, 1);
    expect(groups.single.manualSessions.map((item) => item.id), <String>[
      'manual-session-1',
    ]);
  });

  test(
    'automatic session counts active time and only sequential progress',
    () async {
      final remote = _FakePlanRemote();
      final database = _FakeLocalDatabase();
      var now = DateTime.utc(2026, 8, 29, 10);
      final repository = PlanRepository(
        database,
        remote: remote,
        timezoneLoader: () async => 'Europe/Istanbul',
      );
      final session = repository.startReadingSession(
        accountScope: await database.captureAccount(),
        clock: () => now,
      );

      session.observe(page: 1, surah: 1, ayah: 1);
      session.observe(page: 300, surah: 50, ayah: 1);
      session.observe(page: 301, surah: 50, ayah: 4);
      now = now.add(const Duration(seconds: 30));
      session.pause();
      now = now.add(const Duration(minutes: 2));
      session.resume();
      now = now.add(const Duration(seconds: 40));
      await session.finish();
      await session.finish();

      expect(remote.automaticPayloads, hasLength(1));
      expect(remote.automaticPayloads.single['active_seconds'], 70);
      expect(remote.automaticPayloads.single['credited_pages'], 1);
      expect(remote.automaticPayloads.single['credited_ayahs'], 3);
      expect(
        remote.automaticPayloads.single['timezone_name'],
        'Europe/Istanbul',
      );
    },
  );

  test('failed automatic session is delivered on the next refresh', () async {
    final database = _FakeLocalDatabase();
    final remote = _FakePlanRemote()..offline = true;
    var now = DateTime.utc(2026, 8, 29, 10);
    final repository = PlanRepository(
      database,
      remote: remote,
      timezoneLoader: () async => 'UTC',
    );
    final session = repository.startReadingSession(
      accountScope: await database.captureAccount(),
      clock: () => now,
    );
    session.observe(page: 1, surah: 1, ayah: 1);
    session.observe(page: 2, surah: 2, ayah: 1);
    now = now.add(const Duration(seconds: 10));

    await session.finish();
    expect(
      (database.states['reading:pending-automatic-sessions']?['items'] as List),
      hasLength(1),
    );

    remote.offline = false;
    await repository.load();

    expect(remote.automaticPayloads, hasLength(1));
    expect(
      (database.states['reading:pending-automatic-sessions']?['items'] as List),
      isEmpty,
    );
  });

  test('opening and closing a reader does not create fake progress', () async {
    final database = _FakeLocalDatabase();
    final remote = _FakePlanRemote();
    var now = DateTime.utc(2026, 8, 29, 10);
    final session =
        PlanRepository(
          database,
          remote: remote,
          timezoneLoader: () async => 'UTC',
        ).startReadingSession(
          accountScope: await database.captureAccount(),
          clock: () => now,
        );
    session.observe(page: 20, surah: 2, ayah: 15);
    now = now.add(const Duration(seconds: 10));

    await session.finish();

    expect(remote.automaticPayloads, isEmpty);
    expect(database.states['reading:pending-automatic-sessions'], isNull);
  });

  test('new daily plan uses onboarding target with zero progress', () async {
    final database = _FakeLocalDatabase();
    final plan = await PlanRepository(database).load(preferredTarget: 1);

    expect(plan.target, 1);
    expect(plan.achieved, 0);
    expect(plan.streak, 0);
    expect(plan.prayerPages.values, everyElement(0));
  });

  test('stored daily plan is aligned with the current pages target', () async {
    final database = _FakeLocalDatabase(<String, Map<String, Object?>>{
      'daily_plan': const DailyPlan.initial(target: 6).toJson(),
    });
    final repository = PlanRepository(database);

    final plan = await repository.load(preferredTarget: 1);

    expect(plan.target, 1);
    expect(database.states['daily_plan']?['target'], 1);
  });

  test(
    'onboarding initializes a clean plan and removes stale progress',
    () async {
      final database = _FakeLocalDatabase(<String, Map<String, Object?>>{
        'daily_plan': <String, Object?>{
          ...const DailyPlan.initial(target: 6).toJson(),
          'achieved': 5,
        },
      });
      final repository = PlanRepository(database);

      final plan = await repository.initialize(target: 1);

      expect(plan.target, 1);
      expect(plan.achieved, 0);
      expect(plan.prayerPages.values, everyElement(0));
      expect(database.states['daily_plan']?['achieved'], 0);
    },
  );

  test(
    'an action captured by A cannot update the plan after switching to B',
    () async {
      final database = _FakeLocalDatabase(<String, Map<String, Object?>>{
        'daily_plan': const DailyPlan.initial(target: 6).toJson(),
      });
      final repository = PlanRepository(database);
      final scopeA = await database.captureAccount();
      database.accountScope.activate('owner-b');

      await expectLater(
        repository.addPages(2, accountScope: scopeA),
        throwsA(isA<AccountScopeChanged>()),
      );

      expect(database.states['daily_plan']?['achieved'], 0);
    },
  );
}

class _FakeLocalDatabase implements LocalDatabase {
  _FakeLocalDatabase([Map<String, Map<String, Object?>>? values])
    : states = values ?? <String, Map<String, Object?>>{};

  final Map<String, Map<String, Object?>> states;
  CachedValue? cached;

  @override
  final AccountScope accountScope = AccountScope.forTesting('test-owner');

  @override
  Future<AccountScopeSnapshot> captureAccount() => accountScope.capture();

  @override
  void ensureCurrent(AccountScopeSnapshot scope) =>
      accountScope.ensureCurrent(scope);

  @override
  Future<Map<String, Object?>?> readState(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (accountScope != null) ensureCurrent(accountScope);
    return states[key];
  }

  @override
  Future<void> writeState(
    String key,
    Map<String, Object?> value, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (accountScope != null) ensureCurrent(accountScope);
    states[key] = value;
  }

  @override
  Future<CachedValue?> readAccountCache(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (accountScope != null) ensureCurrent(accountScope);
    return cached;
  }

  @override
  Future<void> writeAccountCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
    AccountScopeSnapshot? accountScope,
  }) async {
    if (accountScope != null) ensureCurrent(accountScope);
    final now = DateTime.now().toUtc();
    cached = CachedValue(
      value: value,
      updatedAt: now,
      etag: etag,
      expiresAt: now.add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlanRemote implements PlanRemoteGateway {
  _FakePlanRemote({
    this.metric = ReadingGoalMetric.pages,
    this.target = 6,
    this.achieved = 0,
  });

  ReadingGoalMetric metric;
  int target;
  int achieved;
  int goalRevision = 1;
  bool offline = false;
  String? prayerTimezone;
  String prayerDate = '2026-08-29';
  Completer<void>? writeGate;
  int checkInCreates = 0;
  String? requestedTimezone;
  Map<String, Object?>? savedGoal;
  Map<String, Object?>? savedManual;
  Map<String, Object?>? savedPrayerPlan;
  Map<String, Object?>? savedPrayerCheckIn;
  Map<String, Object?>? prayerPlan;
  Map<String, Object?>? prayerCheckIn;
  final List<Map<String, Object?>> automaticPayloads = <Map<String, Object?>>[];

  void _check(String timezoneName) {
    requestedTimezone = timezoneName;
    if (offline) throw StateError('offline');
  }

  @override
  Future<Object?> today(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) async {
    _check(timezoneName);
    return <String, Object?>{
      'local_date': '2026-08-29',
      'timezone_name': timezoneName,
      'continue_reading': null,
      'goal': <String, Object?>{
        'id': 'goal-1',
        'metric': metric.wireValue,
        'target_amount': '$target.00',
        'revision': goalRevision,
      },
      'progress': <String, Object?>{
        'achieved_amount': '$achieved.00',
        'remaining_amount': '${(target - achieved).clamp(0, target)}.00',
        'is_completed': achieved >= target,
      },
      'streak': const <String, Object?>{'current_count': 3, 'longest_count': 8},
    };
  }

  @override
  Future<Object?> planner(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) async {
    _check(timezoneName);
    return <String, Object?>{
      'local_date': '2026-08-29',
      'timezone_name': timezoneName,
      'days': <Object?>[
        <String, Object?>{
          'local_date': '2026-08-29',
          'state': achieved >= target ? 'completed' : 'partial',
          'has_reading': achieved > 0,
          'goal': <String, Object?>{
            'metric': metric.wireValue,
            'target_amount': '$target.00',
            'achieved_amount': '$achieved.00',
          },
          'automatic_active_seconds': 120,
          'automatic_pages': 1,
          'automatic_ayahs': 4,
          'prayer_pages': prayerCheckIn?['pages'] ?? 0,
        },
      ],
    };
  }

  @override
  Future<Object?> sessions({
    int limit = 100,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    return const <String, Object?>{'results': <Object?>[]};
  }

  @override
  Future<Object?> prayerDay(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) async {
    _check(timezoneName);
    return <String, Object?>{
      'local_date': prayerDate,
      'timezone_name': prayerTimezone ?? timezoneName,
      'plan': prayerPlan,
      'check_ins': <Object?>[?prayerCheckIn],
    };
  }

  @override
  Future<Object?> updateManualSession(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    return <String, Object?>{'id': id, ...payload};
  }

  @override
  Future<void> deleteManualSession(
    String id,
    int revision,
    DateTime updatedAt, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
  }

  @override
  Future<Object?> setGoal(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    savedGoal = payload;
    metric = ReadingGoalMetric.fromWire(payload['metric']);
    target = (payload['target_amount'] as num).toInt();
    goalRevision++;
    achieved = 0;
    return <String, Object?>{'revision': goalRevision};
  }

  @override
  Future<Object?> recordManual(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    savedManual = payload;
    if (payload['metric'] == metric.wireValue) {
      achieved += (payload['amount'] as num).toInt();
    }
    return <String, Object?>{'id': payload['id']};
  }

  @override
  Future<Object?> recordAutomatic(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    automaticPayloads.add(payload);
    return <String, Object?>{'id': payload['id']};
  }

  @override
  Future<Object?> setPrayerPlan(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    savedPrayerPlan = payload;
    prayerPlan = <String, Object?>{
      'id': 'prayer-plan-1',
      'pages_per_prayer': payload['pages_per_prayer'],
      'revision': 1,
    };
    return prayerPlan;
  }

  @override
  Future<Object?> createPrayerCheckIn(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    await writeGate?.future;
    checkInCreates++;
    if (prayerTimezone != null && payload['timezone_name'] != prayerTimezone) {
      throw StateError('Timezone must match the active prayer reading plan.');
    }
    savedPrayerCheckIn = payload;
    prayerCheckIn = <String, Object?>{
      'id': payload['id'],
      'prayer': payload['prayer'],
      'pages': payload['pages'],
      'revision': 1,
    };
    achieved += (payload['pages'] as num).toInt();
    return prayerCheckIn;
  }

  @override
  Future<Object?> updatePrayerCheckIn(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (payload['base_revision'] != prayerCheckIn?['revision']) {
      throw StateError('Prayer check-in revision conflict');
    }
    prayerCheckIn = <String, Object?>{
      'id': id,
      'prayer': prayerCheckIn?['prayer'],
      'pages': payload['pages'],
      'revision': (payload['base_revision'] as int) + 1,
    };
    return prayerCheckIn;
  }

  @override
  Future<void> deletePrayerCheckIn(
    String id,
    int revision,
    DateTime updatedAt, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (revision != prayerCheckIn?['revision']) {
      throw StateError('Prayer check-in revision conflict');
    }
    prayerCheckIn = null;
  }
}

class _IdleAudio extends StateNotifier<IqroAudioState>
    implements AudioController {
  _IdleAudio() : super(const IqroAudioState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
