import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';

void main() {
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
}

class _FakeLocalDatabase implements LocalDatabase {
  _FakeLocalDatabase([Map<String, Map<String, Object?>>? values])
    : states = values ?? <String, Map<String, Object?>>{};

  final Map<String, Map<String, Object?>> states;

  @override
  Future<Map<String, Object?>?> readState(String key) async => states[key];

  @override
  Future<void> writeState(String key, Map<String, Object?> value) async {
    states[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
