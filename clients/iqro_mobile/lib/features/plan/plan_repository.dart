import '../../core/auth/account_scope.dart';
import '../../core/storage/local_database.dart';

class DailyPlan {
  const DailyPlan({
    required this.target,
    required this.achieved,
    required this.prayerPages,
    required this.streak,
  });

  const DailyPlan.initial({this.target = 6})
    : achieved = 0,
      prayerPages = const <String, int>{
        'fajr': 0,
        'dhuhr': 0,
        'asr': 0,
        'maghrib': 0,
        'isha': 0,
      },
      streak = 0;

  factory DailyPlan.fromJson(Map<String, Object?> json) {
    final prayer = json['prayer_pages'] is Map
        ? Map<String, Object?>.from(json['prayer_pages']! as Map)
        : const <String, Object?>{};
    return DailyPlan(
      target: (json['target'] as num?)?.toInt() ?? 6,
      achieved: (json['achieved'] as num?)?.toInt() ?? 0,
      prayerPages: <String, int>{
        for (final code in const <String>[
          'fajr',
          'dhuhr',
          'asr',
          'maghrib',
          'isha',
        ])
          code: (prayer[code] as num?)?.toInt() ?? 0,
      },
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }

  final int target;
  final int achieved;
  final Map<String, int> prayerPages;
  final int streak;

  DailyPlan copyWith({
    int? target,
    int? achieved,
    Map<String, int>? prayerPages,
    int? streak,
  }) => DailyPlan(
    target: target ?? this.target,
    achieved: achieved ?? this.achieved,
    prayerPages: prayerPages ?? this.prayerPages,
    streak: streak ?? this.streak,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'achieved': achieved,
    'prayer_pages': prayerPages,
    'streak': streak,
  };
}

class PlanRepository {
  PlanRepository(this._database);

  final LocalDatabase _database;

  Future<DailyPlan> initialize({
    required int target,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final plan = DailyPlan.initial(target: target);
    await _database.writeState(
      'daily_plan',
      plan.toJson(),
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return plan;
  }

  Future<DailyPlan> load({
    int? preferredTarget,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    return _loadFor(scope, preferredTarget: preferredTarget);
  }

  Future<DailyPlan> _loadFor(
    AccountScopeSnapshot scope, {
    int? preferredTarget,
  }) async {
    final data = await _database.readState('daily_plan', accountScope: scope);
    var plan = data == null
        ? DailyPlan.initial(target: preferredTarget ?? 6)
        : DailyPlan.fromJson(data);
    if (preferredTarget != null && plan.target != preferredTarget) {
      plan = plan.copyWith(target: preferredTarget);
      await _database.writeState(
        'daily_plan',
        plan.toJson(),
        accountScope: scope,
      );
    }
    _database.ensureCurrent(scope);
    return plan;
  }

  Future<DailyPlan> addPages(
    int pages, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final current = await _loadFor(scope);
    final next = current.copyWith(achieved: current.achieved + pages);
    await _database.writeState(
      'daily_plan',
      next.toJson(),
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return next;
  }

  Future<DailyPlan> setPrayerPages(
    String prayer,
    int pages, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    final current = await _loadFor(scope);
    final values = Map<String, int>.of(current.prayerPages)..[prayer] = pages;
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    final next = current.copyWith(prayerPages: values, achieved: total);
    await _database.writeState(
      'daily_plan',
      next.toJson(),
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return next;
  }
}
