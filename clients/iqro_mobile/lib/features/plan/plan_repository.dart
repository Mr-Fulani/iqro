import '../../core/storage/local_database.dart';

class DailyPlan {
  const DailyPlan({
    required this.target,
    required this.achieved,
    required this.prayerPages,
    required this.streak,
  });

  const DailyPlan.initial()
    : target = 6,
      achieved = 2,
      prayerPages = const <String, int>{
        'fajr': 2,
        'dhuhr': 0,
        'asr': 0,
        'maghrib': 0,
        'isha': 0,
      },
      streak = 4;

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

  Future<DailyPlan> load() async {
    final data = await _database.readState('daily_plan');
    return data == null ? const DailyPlan.initial() : DailyPlan.fromJson(data);
  }

  Future<DailyPlan> addPages(int pages) async {
    final current = await load();
    final next = current.copyWith(achieved: current.achieved + pages);
    await _database.writeState('daily_plan', next.toJson());
    return next;
  }

  Future<DailyPlan> setPrayerPages(String prayer, int pages) async {
    final current = await load();
    final values = Map<String, int>.of(current.prayerPages)..[prayer] = pages;
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    final next = current.copyWith(prayerPages: values, achieved: total);
    await _database.writeState('daily_plan', next.toJson());
    return next;
  }
}
