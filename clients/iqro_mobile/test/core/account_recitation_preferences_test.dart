import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account-bound controllers never write another user choice', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = PreferencesStore(await SharedPreferences.getInstance());
    final scope = AccountScope.forTesting('user-a');
    final plan = _UnusedPlanRepository();

    final a = AppPreferencesController(store, plan, accountScope: scope);
    addTearDown(a.dispose);
    await a.setListeningRecitation('audio-a');
    await a.setMushafRecitation('mushaf-a');
    await a.setMemorizationDefaultRecitation('memory-a');

    scope.activate('user-b');
    await a.setMushafRecitation('stale-a');
    final b = AppPreferencesController(store, plan, accountScope: scope);
    addTearDown(b.dispose);
    expect(b.state.listeningRecitationId, isNull);
    expect(b.state.mushafRecitationId, isNull);
    await b.setListeningRecitation('audio-b');

    scope.activate('user-a');
    final restoredA = AppPreferencesController(
      store,
      plan,
      accountScope: scope,
    );
    addTearDown(restoredA.dispose);
    expect(restoredA.state.listeningRecitationId, 'audio-a');
    expect(restoredA.state.mushafRecitationId, 'mushaf-a');
    expect(restoredA.state.memorizationDefaultRecitationId, 'memory-a');
    expect(store.readForAccount('user-b').listeningRecitationId, 'audio-b');
    expect(store.readForAccount('user-b').mushafRecitationId, isNull);
  });
}

class _UnusedPlanRepository implements PlanRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
