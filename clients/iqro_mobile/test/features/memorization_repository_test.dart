import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/memorization/memorization_repository.dart';

void main() {
  test(
    'dashboard uses the server plan and falls back to private cache',
    () async {
      final database = _MemoryDatabase();
      final remote = _MemoryRemote();
      final repository = MemorizationRepository(
        database: database,
        remote: remote,
        timezoneLoader: () async => 'Europe/Istanbul',
      );

      final online = await repository.load();
      remote.failDashboard = true;
      final offline = await repository.load();

      expect(remote.timezoneName, 'Europe/Istanbul');
      expect(online.plan?.startAyah.ayah, 2);
      expect(online.plan?.dailyRepetitions, 5);
      expect(offline.fromCache, isTrue);
      expect(offline.plan?.endAyah.ayah, 4);
    },
  );

  test('plan edit sends canonical ayah ids and optimistic revision', () async {
    final remote = _MemoryRemote();
    final repository = MemorizationRepository(
      database: _MemoryDatabase(),
      remote: remote,
      timezoneLoader: () async => 'Europe/Istanbul',
    );
    await repository.load();

    final dashboard = await repository.savePlan(
      const MemorizationPlanDraft(
        startAyahId: 'ayah-2',
        endAyahId: 'ayah-5',
        recitationId: 'recitation-1',
        dailyRepetitions: 8,
        pauseSeconds: 3,
      ),
      baseRevision: 7,
    );

    expect(remote.savedPlan?['start_ayah_id'], 'ayah-2');
    expect(remote.savedPlan?['end_ayah_id'], 'ayah-5');
    expect(remote.savedPlan?['daily_repetitions'], 8);
    expect(remote.savedPlan?['pause_seconds'], 3);
    expect(remote.savedPlan?['base_revision'], 7);
    expect(remote.savedPlan?['timezone_name'], 'Europe/Istanbul');
    expect(remote.savedPlan?['client_updated_at'], isNotEmpty);
    expect(dashboard.plan?.dailyRepetitions, 8);
  });

  test('assessment records a real synced repetition', () async {
    final remote = _MemoryRemote();
    final repository = MemorizationRepository(
      database: _MemoryDatabase(),
      remote: remote,
      timezoneLoader: () async => 'Europe/Istanbul',
    );
    await repository.load();

    final dashboard = await repository.assess(
      MemorizationAssessment.memorized,
      duration: const Duration(seconds: 12),
    );

    expect(remote.savedSession?['plan_id'], 'plan-1');
    expect(remote.savedSession?['assessment'], 'memorized');
    expect(remote.savedSession?['completed_repetitions'], 1);
    expect(remote.savedSession?['duration_seconds'], 12);
    expect(dashboard.today.completedRepetitions, 1);
  });
}

class _MemoryDatabase implements LocalDatabase {
  CachedValue? cached;

  @override
  Future<CachedValue?> readCache(String key) async => cached;

  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration? maxAge,
  }) async {
    final now = DateTime.now().toUtc();
    cached = CachedValue(
      value: value,
      updatedAt: now,
      etag: etag,
      expiresAt: maxAge == null ? null : now.add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRemote implements MemorizationRemoteGateway {
  var dashboardPayload = _dashboard();
  bool failDashboard = false;
  String? timezoneName;
  Map<String, Object?>? savedPlan;
  Map<String, Object?>? savedSession;

  @override
  Future<Object?> dashboard(String timezoneName) async {
    this.timezoneName = timezoneName;
    if (failDashboard) throw StateError('offline');
    return dashboardPayload;
  }

  @override
  Future<Object?> savePlan(Map<String, Object?> payload) async {
    savedPlan = payload;
    final plan = Map<String, Object?>.from(dashboardPayload['plan']! as Map)
      ..['end_ayah'] = <String, Object?>{
        'id': payload['end_ayah_id'],
        'surah_number': 2,
        'ayah_number': 5,
        'text_uthmani': 'text',
      }
      ..['recitation_id'] = payload['recitation_id']
      ..['daily_repetitions'] = payload['daily_repetitions']
      ..['pause_seconds'] = payload['pause_seconds']
      ..['revision'] = 8;
    dashboardPayload = <String, Object?>{...dashboardPayload, 'plan': plan};
    return plan;
  }

  @override
  Future<Object?> createSession(Map<String, Object?> payload) async {
    savedSession = payload;
    final session = <String, Object?>{
      ...payload,
      'id': payload['id'],
      'plan_id': payload['plan_id'],
    };
    final today = Map<String, Object?>.from(dashboardPayload['today']! as Map)
      ..['completed_repetitions'] = 1
      ..['remaining_repetitions'] = 4
      ..['last_assessment'] = payload['assessment']
      ..['sessions'] = <Object?>[session];
    dashboardPayload = <String, Object?>{...dashboardPayload, 'today': today};
    return session;
  }

  @override
  Future<void> resetToday(String timezoneName) async {}
}

Map<String, Object?> _dashboard() => <String, Object?>{
  'timezone_name': 'Europe/Istanbul',
  'plan': <String, Object?>{
    'id': 'plan-1',
    'edition_code': 'madani-hafs',
    'content_version': '2026.1',
    'start_ayah': <String, Object?>{
      'id': 'ayah-2',
      'surah_number': 2,
      'ayah_number': 2,
      'text_uthmani': 'text',
    },
    'end_ayah': <String, Object?>{
      'id': 'ayah-4',
      'surah_number': 2,
      'ayah_number': 4,
      'text_uthmani': 'text',
    },
    'recitation_id': null,
    'reciter': null,
    'daily_repetitions': 5,
    'pause_seconds': 2,
    'timezone_name': 'Europe/Istanbul',
    'revision': 7,
  },
  'today': <String, Object?>{
    'local_date': '2026-09-02',
    'completed_repetitions': 0,
    'target_repetitions': 5,
    'remaining_repetitions': 5,
    'is_completed': false,
    'last_assessment': null,
    'sessions': const <Object?>[],
  },
  'recent_days': const <Object?>[],
};
