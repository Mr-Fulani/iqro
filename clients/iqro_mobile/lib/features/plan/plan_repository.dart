import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';

enum ReadingGoalMetric {
  minutes,
  pages,
  ayahs;

  String get wireValue => name;

  static ReadingGoalMetric fromWire(Object? value) => values.firstWhere(
    (metric) => metric.wireValue == value?.toString(),
    orElse: () => ReadingGoalMetric.pages,
  );
}

class ReadingHistoryDay {
  const ReadingHistoryDay({
    required this.localDate,
    required this.state,
    required this.hasReading,
    required this.metric,
    required this.target,
    required this.achieved,
    required this.automaticSeconds,
    required this.automaticPages,
    required this.automaticAyahs,
    required this.prayerPages,
  });

  factory ReadingHistoryDay.fromJson(Map<String, Object?> json) {
    final goal = json['goal'] is Map
        ? Map<String, Object?>.from(json['goal']! as Map)
        : null;
    return ReadingHistoryDay(
      localDate: DateTime.tryParse(json['local_date']?.toString() ?? ''),
      state: json['state']?.toString() ?? 'no_goal',
      hasReading: json['has_reading'] == true,
      metric: goal == null ? null : ReadingGoalMetric.fromWire(goal['metric']),
      target: _amount(goal?['target_amount']),
      achieved: _amount(goal?['achieved_amount']),
      automaticSeconds:
          (json['automatic_active_seconds'] as num?)?.toInt() ?? 0,
      automaticPages: (json['automatic_pages'] as num?)?.toInt() ?? 0,
      automaticAyahs: (json['automatic_ayahs'] as num?)?.toInt() ?? 0,
      prayerPages: (json['prayer_pages'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime? localDate;
  final String state;
  final bool hasReading;
  final ReadingGoalMetric? metric;
  final double target;
  final double achieved;
  final int automaticSeconds;
  final int automaticPages;
  final int automaticAyahs;
  final int prayerPages;
}

class PrayerReadingCheckIn {
  const PrayerReadingCheckIn({
    required this.id,
    required this.prayer,
    required this.pages,
    required this.revision,
  });

  factory PrayerReadingCheckIn.fromJson(Map<String, Object?> json) =>
      PrayerReadingCheckIn(
        id: json['id']?.toString() ?? '',
        prayer: json['prayer']?.toString() ?? '',
        pages: (json['pages'] as num?)?.toInt() ?? 0,
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String prayer;
  final int pages;
  final int revision;
}

class DailyPlan {
  const DailyPlan({
    required this.metric,
    required this.target,
    required this.achieved,
    required this.prayerPages,
    required this.streak,
    this.longestStreak = 0,
    this.goalRevision = 0,
    this.timezoneName = 'UTC',
    this.localDate = '',
    this.history = const <ReadingHistoryDay>[],
    this.prayerCheckIns = const <String, PrayerReadingCheckIn>{},
    this.prayerPlanRevision,
    this.prayerPlanPages,
    this.fromCache = false,
  });

  const DailyPlan.initial({
    this.target = 6,
    this.metric = ReadingGoalMetric.pages,
  }) : achieved = 0,
       prayerPages = const <String, int>{
         'fajr': 0,
         'dhuhr': 0,
         'asr': 0,
         'maghrib': 0,
         'isha': 0,
       },
       streak = 0,
       longestStreak = 0,
       goalRevision = 0,
       timezoneName = 'UTC',
       localDate = '',
       history = const <ReadingHistoryDay>[],
       prayerCheckIns = const <String, PrayerReadingCheckIn>{},
       prayerPlanRevision = null,
       prayerPlanPages = null,
       fromCache = false;

  factory DailyPlan.fromJson(Map<String, Object?> json) {
    final prayer = json['prayer_pages'] is Map
        ? Map<String, Object?>.from(json['prayer_pages']! as Map)
        : const <String, Object?>{};
    return DailyPlan(
      metric: ReadingGoalMetric.fromWire(json['metric']),
      target: _amount(json['target'], fallback: 6),
      achieved: _amount(json['achieved']),
      prayerPages: <String, int>{
        for (final code in _prayerCodes)
          code: (prayer[code] as num?)?.toInt() ?? 0,
      },
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
      goalRevision: (json['goal_revision'] as num?)?.toInt() ?? 0,
      timezoneName: json['timezone_name']?.toString() ?? 'UTC',
      localDate: json['local_date']?.toString() ?? '',
      fromCache: json['from_cache'] == true,
    );
  }

  factory DailyPlan.fromRemote(Map<String, Object?> snapshot) {
    final today = jsonMap(snapshot['today']);
    final planner = jsonMap(snapshot['planner']);
    final prayer = jsonMap(snapshot['prayer']);
    final goal = today['goal'] is Map
        ? Map<String, Object?>.from(today['goal']! as Map)
        : const <String, Object?>{};
    final progress = today['progress'] is Map
        ? Map<String, Object?>.from(today['progress']! as Map)
        : const <String, Object?>{};
    final streak = today['streak'] is Map
        ? Map<String, Object?>.from(today['streak']! as Map)
        : const <String, Object?>{};
    final rawPlan = prayer['plan'] is Map
        ? Map<String, Object?>.from(prayer['plan']! as Map)
        : null;
    final checkIns = <String, PrayerReadingCheckIn>{};
    for (final raw in (prayer['check_ins'] as List?) ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final checkIn = PrayerReadingCheckIn.fromJson(
        Map<String, Object?>.from(raw),
      );
      if (_prayerCodes.contains(checkIn.prayer) && checkIn.id.isNotEmpty) {
        checkIns[checkIn.prayer] = checkIn;
      }
    }
    final history = <ReadingHistoryDay>[];
    for (final raw in (planner['days'] as List?) ?? const <Object?>[]) {
      if (raw is Map) {
        history.add(ReadingHistoryDay.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    return DailyPlan(
      metric: ReadingGoalMetric.fromWire(goal['metric']),
      target: _amount(goal['target_amount'], fallback: 6),
      achieved: _amount(progress['achieved_amount']),
      prayerPages: <String, int>{
        for (final code in _prayerCodes) code: checkIns[code]?.pages ?? 0,
      },
      streak: (streak['current_count'] as num?)?.toInt() ?? 0,
      longestStreak: (streak['longest_count'] as num?)?.toInt() ?? 0,
      goalRevision: (goal['revision'] as num?)?.toInt() ?? 0,
      timezoneName:
          today['timezone_name']?.toString() ??
          planner['timezone_name']?.toString() ??
          'UTC',
      localDate: today['local_date']?.toString() ?? '',
      history: history.reversed.toList(growable: false),
      prayerCheckIns: checkIns,
      prayerPlanRevision: (rawPlan?['revision'] as num?)?.toInt(),
      prayerPlanPages: (rawPlan?['pages_per_prayer'] as num?)?.toInt(),
    );
  }

  final ReadingGoalMetric metric;
  final double target;
  final double achieved;
  final Map<String, int> prayerPages;
  final int streak;
  final int longestStreak;
  final int goalRevision;
  final String timezoneName;
  final String localDate;
  final List<ReadingHistoryDay> history;
  final Map<String, PrayerReadingCheckIn> prayerCheckIns;
  final int? prayerPlanRevision;
  final int? prayerPlanPages;
  final bool fromCache;

  DailyPlan copyWith({
    ReadingGoalMetric? metric,
    double? target,
    double? achieved,
    Map<String, int>? prayerPages,
    int? streak,
    int? longestStreak,
    int? goalRevision,
    String? timezoneName,
    String? localDate,
    List<ReadingHistoryDay>? history,
    Map<String, PrayerReadingCheckIn>? prayerCheckIns,
    int? prayerPlanRevision,
    int? prayerPlanPages,
    bool? fromCache,
  }) => DailyPlan(
    metric: metric ?? this.metric,
    target: target ?? this.target,
    achieved: achieved ?? this.achieved,
    prayerPages: prayerPages ?? this.prayerPages,
    streak: streak ?? this.streak,
    longestStreak: longestStreak ?? this.longestStreak,
    goalRevision: goalRevision ?? this.goalRevision,
    timezoneName: timezoneName ?? this.timezoneName,
    localDate: localDate ?? this.localDate,
    history: history ?? this.history,
    prayerCheckIns: prayerCheckIns ?? this.prayerCheckIns,
    prayerPlanRevision: prayerPlanRevision ?? this.prayerPlanRevision,
    prayerPlanPages: prayerPlanPages ?? this.prayerPlanPages,
    fromCache: fromCache ?? this.fromCache,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'metric': metric.wireValue,
    'target': target,
    'achieved': achieved,
    'prayer_pages': prayerPages,
    'streak': streak,
    'longest_streak': longestStreak,
    'goal_revision': goalRevision,
    'timezone_name': timezoneName,
    'local_date': localDate,
    'from_cache': fromCache,
  };
}

abstract interface class PlanRemoteGateway {
  Future<Object?> today(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> planner(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> prayerDay(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> setGoal(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> recordManual(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> setPrayerPlan(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> createPrayerCheckIn(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> updatePrayerCheckIn(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<void> deletePrayerCheckIn(
    String id,
    int revision,
    DateTime updatedAt, {
    AccountScopeSnapshot? accountScope,
  });
}

class ApiPlanRemoteGateway implements PlanRemoteGateway {
  const ApiPlanRemoteGateway(this._api);

  final ApiClient _api;

  @override
  Future<Object?> today(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/today',
    query: <String, Object?>{'timezone_name': timezoneName},
    accountScope: accountScope,
  );

  @override
  Future<Object?> planner(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/reading-planner',
    query: <String, Object?>{'days': 14, 'timezone_name': timezoneName},
    accountScope: accountScope,
  );

  @override
  Future<Object?> prayerDay(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/prayer-reading-plan',
    query: <String, Object?>{'timezone_name': timezoneName},
    accountScope: accountScope,
  );

  @override
  Future<Object?> setGoal(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.put('/me/reading-goal', data: payload, accountScope: accountScope);

  @override
  Future<Object?> recordManual(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/reading-sessions/manual',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<Object?> setPrayerPlan(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.put(
    '/me/prayer-reading-plan',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<Object?> createPrayerCheckIn(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/prayer-reading-check-ins',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<Object?> updatePrayerCheckIn(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.patch(
    '/me/prayer-reading-check-ins/$id',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<void> deletePrayerCheckIn(
    String id,
    int revision,
    DateTime updatedAt, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final query = Uri(
      queryParameters: <String, String>{
        'base_revision': '$revision',
        'client_updated_at': updatedAt.toUtc().toIso8601String(),
      },
    ).query;
    await _api.delete(
      '/me/prayer-reading-check-ins/$id?$query',
      accountScope: accountScope,
    );
  }
}

class PlanRepository {
  PlanRepository(
    this._database, {
    ApiClient? api,
    PlanRemoteGateway? remote,
    Future<String> Function()? timezoneLoader,
    Uuid uuid = const Uuid(),
  }) : _remote = remote ?? (api == null ? null : ApiPlanRemoteGateway(api)),
       _timezoneLoader = timezoneLoader ?? _deviceTimezone,
       _uuid = uuid;

  static const _cacheKey = 'reading:plan-dashboard';
  final LocalDatabase _database;
  final PlanRemoteGateway? _remote;
  final Future<String> Function() _timezoneLoader;
  final Uuid _uuid;

  Future<DailyPlan> initialize({
    required int target,
    ReadingGoalMetric metric = ReadingGoalMetric.pages,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final plan = DailyPlan.initial(target: target.toDouble(), metric: metric);
    await _storeLocal(plan, scope);
    final remote = _remote;
    if (remote == null) return plan;
    try {
      await _setRemoteGoal(
        remote,
        metric: metric,
        target: target.toDouble(),
        baseRevision: 0,
        timezoneName: await _safeTimezone(),
        scope: scope,
      );
      return _loadRemote(
        scope,
        preferredMetric: metric,
        preferredTarget: target,
      );
    } on Object {
      _database.ensureCurrent(scope);
      return plan.copyWith(fromCache: true);
    }
  }

  Future<DailyPlan> load({
    int? preferredTarget,
    ReadingGoalMetric? preferredMetric,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final remote = _remote;
    if (remote == null) {
      return _loadLocal(
        scope,
        preferredTarget: preferredTarget,
        preferredMetric: preferredMetric,
      );
    }
    try {
      return await _loadRemote(
        scope,
        preferredTarget: preferredTarget,
        preferredMetric: preferredMetric,
      );
    } on Object {
      _database.ensureCurrent(scope);
      final cached = await _cachedRemote(scope);
      if (cached != null) return cached.copyWith(fromCache: true);
      return (await _loadLocal(
        scope,
        preferredTarget: preferredTarget,
        preferredMetric: preferredMetric,
      )).copyWith(fromCache: true);
    }
  }

  Future<DailyPlan> _loadRemote(
    AccountScopeSnapshot scope, {
    int? preferredTarget,
    ReadingGoalMetric? preferredMetric,
  }) async {
    final remote = _remote!;
    final timezoneName = await _safeTimezone();
    _database.ensureCurrent(scope);
    var today = jsonMap(await remote.today(timezoneName, accountScope: scope));
    _database.ensureCurrent(scope);
    if (today['goal'] == null && preferredTarget != null) {
      await _setRemoteGoal(
        remote,
        metric: preferredMetric ?? ReadingGoalMetric.pages,
        target: preferredTarget.toDouble(),
        baseRevision: 0,
        timezoneName: timezoneName,
        scope: scope,
      );
      today = jsonMap(await remote.today(timezoneName, accountScope: scope));
    }
    final results = await Future.wait<Object?>(<Future<Object?>>[
      remote.planner(timezoneName, accountScope: scope),
      remote.prayerDay(timezoneName, accountScope: scope),
    ]);
    _database.ensureCurrent(scope);
    final snapshot = <String, Object?>{
      'today': today,
      'planner': jsonMap(results[0]),
      'prayer': jsonMap(results[1]),
    };
    final plan = DailyPlan.fromRemote(snapshot);
    await _database.writeAccountCache(
      _cacheKey,
      snapshot,
      maxAge: const Duration(days: 30),
      accountScope: scope,
    );
    await _storeLocal(plan, scope);
    return plan;
  }

  Future<DailyPlan> setGoal(
    ReadingGoalMetric metric,
    int target, {
    required int baseRevision,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    if (target < 1 || target > maximumReadingTarget(metric)) {
      throw const FormatException('Daily reading target is out of range');
    }
    final remote = _remote;
    if (remote == null) {
      final current = await _loadLocal(scope);
      final next = current.copyWith(metric: metric, target: target.toDouble());
      await _storeLocal(next, scope);
      return next;
    }
    final timezoneName = await _safeTimezone();
    await _setRemoteGoal(
      remote,
      metric: metric,
      target: target.toDouble(),
      baseRevision: baseRevision,
      timezoneName: timezoneName,
      scope: scope,
    );
    return _loadRemote(scope);
  }

  Future<DailyPlan> addReading(
    int amount, {
    required ReadingGoalMetric metric,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    if (amount < 1 || amount > maximumReadingTarget(metric)) {
      throw const FormatException('Reading amount is out of range');
    }
    final remote = _remote;
    if (remote == null) {
      final current = await _loadLocal(scope);
      final next = current.copyWith(achieved: current.achieved + amount);
      await _storeLocal(next, scope);
      return next;
    }
    final now = DateTime.now().toUtc();
    final timezoneName = await _safeTimezone();
    final localDate = await _currentLocalDate(scope, timezoneName);
    await remote.recordManual(<String, Object?>{
      'id': _uuid.v7(),
      'timezone_name': timezoneName,
      'local_date': localDate,
      'metric': metric.wireValue,
      'amount': amount,
      'client_updated_at': now.toIso8601String(),
    }, accountScope: scope);
    return _loadRemote(scope);
  }

  Future<DailyPlan> addPages(int pages, {AccountScopeSnapshot? accountScope}) =>
      addReading(
        pages,
        metric: ReadingGoalMetric.pages,
        accountScope: accountScope,
      );

  Future<DailyPlan> setPrayerPages(
    String prayer,
    int pages, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (!_prayerCodes.contains(prayer) || pages < 0 || pages > 604) {
      throw const FormatException('Prayer reading value is invalid');
    }
    final scope = accountScope ?? await _database.captureAccount();
    final remote = _remote;
    final current = await load(accountScope: scope);
    if (remote == null) {
      final values = Map<String, int>.of(current.prayerPages)..[prayer] = pages;
      final next = current.copyWith(
        prayerPages: values,
        achieved: values.values
            .fold<int>(0, (sum, value) => sum + value)
            .toDouble(),
      );
      await _storeLocal(next, scope);
      return next;
    }
    final timezoneName = current.timezoneName.isEmpty
        ? await _safeTimezone()
        : current.timezoneName;
    var plan = current;
    if (plan.prayerPlanRevision == null) {
      final defaultPages = plan.metric == ReadingGoalMetric.pages
          ? (plan.target / _prayerCodes.length).ceil().clamp(1, 20)
          : 1;
      await remote.setPrayerPlan(<String, Object?>{
        'pages_per_prayer': defaultPages,
        'notifications_enabled': true,
        'timezone_name': timezoneName,
        'base_revision': 0,
        'client_updated_at': DateTime.now().toUtc().toIso8601String(),
      }, accountScope: scope);
      plan = await _loadRemote(scope);
    }
    final existing = plan.prayerCheckIns[prayer];
    final now = DateTime.now().toUtc();
    if (pages == 0) {
      if (existing != null) {
        await remote.deletePrayerCheckIn(
          existing.id,
          existing.revision,
          now,
          accountScope: scope,
        );
      }
    } else if (existing == null) {
      await remote.createPrayerCheckIn(<String, Object?>{
        'id': _uuid.v7(),
        'session_id': _uuid.v7(),
        'prayer': prayer,
        'pages': pages,
        'local_date': plan.localDate,
        'timezone_name': timezoneName,
        'client_updated_at': now.toIso8601String(),
      }, accountScope: scope);
    } else {
      await remote.updatePrayerCheckIn(existing.id, <String, Object?>{
        'pages': pages,
        'base_revision': existing.revision,
        'client_updated_at': now.toIso8601String(),
      }, accountScope: scope);
    }
    return _loadRemote(scope);
  }

  Future<void> _setRemoteGoal(
    PlanRemoteGateway remote, {
    required ReadingGoalMetric metric,
    required double target,
    required int baseRevision,
    required String timezoneName,
    required AccountScopeSnapshot scope,
  }) async {
    await remote.setGoal(<String, Object?>{
      'metric': metric.wireValue,
      'target_amount': target,
      'timezone_name': timezoneName,
      'base_revision': baseRevision,
      'client_updated_at': DateTime.now().toUtc().toIso8601String(),
    }, accountScope: scope);
    _database.ensureCurrent(scope);
  }

  Future<String> _currentLocalDate(
    AccountScopeSnapshot scope,
    String timezoneName,
  ) async {
    final cached = await _cachedRemote(scope);
    if (cached != null && cached.localDate.isNotEmpty) return cached.localDate;
    final today = jsonMap(
      await _remote!.today(timezoneName, accountScope: scope),
    );
    return today['local_date']?.toString() ?? _dateOnly(DateTime.now());
  }

  Future<DailyPlan> _loadLocal(
    AccountScopeSnapshot scope, {
    int? preferredTarget,
    ReadingGoalMetric? preferredMetric,
  }) async {
    final data = await _database.readState('daily_plan', accountScope: scope);
    var plan = data == null
        ? DailyPlan.initial(
            target: (preferredTarget ?? 6).toDouble(),
            metric: preferredMetric ?? ReadingGoalMetric.pages,
          )
        : DailyPlan.fromJson(data);
    if (preferredTarget != null &&
        (plan.target != preferredTarget ||
            (preferredMetric != null && plan.metric != preferredMetric))) {
      plan = plan.copyWith(
        target: preferredTarget.toDouble(),
        metric: preferredMetric,
      );
      await _storeLocal(plan, scope);
    }
    _database.ensureCurrent(scope);
    return plan;
  }

  Future<DailyPlan?> _cachedRemote(AccountScopeSnapshot scope) async {
    final cached = await _database.readAccountCache(
      _cacheKey,
      accountScope: scope,
    );
    if (cached == null) return null;
    try {
      return DailyPlan.fromRemote(jsonMap(cached.value));
    } on Object {
      return null;
    }
  }

  Future<void> _storeLocal(DailyPlan plan, AccountScopeSnapshot scope) =>
      _database.writeState('daily_plan', plan.toJson(), accountScope: scope);

  Future<String> _safeTimezone() async {
    try {
      final value = (await _timezoneLoader()).trim();
      return value.isEmpty ? 'UTC' : value;
    } on Object {
      return 'UTC';
    }
  }

  static Future<String> _deviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

const _prayerCodes = <String>['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

int maximumReadingTarget(ReadingGoalMetric metric) => switch (metric) {
  ReadingGoalMetric.minutes => 1440,
  ReadingGoalMetric.pages => 604,
  ReadingGoalMetric.ayahs => 6236,
};

double _amount(Object? value, {double fallback = 0}) =>
    double.tryParse(value?.toString() ?? '') ?? fallback;

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
