import 'dart:math' as math;

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/account_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';

enum MemorizationAssessment {
  difficult('difficult'),
  repeat('repeat'),
  memorized('memorized');

  const MemorizationAssessment(this.wireValue);
  final String wireValue;

  static MemorizationAssessment? tryParse(Object? value) {
    final wireValue = value?.toString();
    return values.where((item) => item.wireValue == wireValue).firstOrNull;
  }
}

class MemorizationAyah {
  const MemorizationAyah({
    required this.id,
    required this.surah,
    required this.ayah,
    required this.textUthmani,
  });

  factory MemorizationAyah.fromJson(Map<String, Object?> json) =>
      MemorizationAyah(
        id: json['id']?.toString() ?? '',
        surah: (json['surah_number'] as num?)?.toInt() ?? 1,
        ayah: (json['ayah_number'] as num?)?.toInt() ?? 1,
        textUthmani: json['text_uthmani']?.toString() ?? '',
      );

  final String id;
  final int surah;
  final int ayah;
  final String textUthmani;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'surah_number': surah,
    'ayah_number': ayah,
    'text_uthmani': textUthmani,
  };
}

class MemorizationReciter {
  const MemorizationReciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.nameRu,
    required this.nameTr,
  });

  factory MemorizationReciter.fromJson(Map<String, Object?> json) =>
      MemorizationReciter(
        id: json['id']?.toString() ?? '',
        nameAr: json['name_ar']?.toString() ?? '',
        nameEn: json['name_en']?.toString() ?? '',
        nameRu: json['name_ru']?.toString() ?? '',
        nameTr: json['name_tr']?.toString() ?? '',
      );

  final String id;
  final String nameAr;
  final String nameEn;
  final String nameRu;
  final String nameTr;

  String nameFor(String locale) {
    if (locale == 'ar' && nameAr.isNotEmpty) return nameAr;
    if (locale == 'ru' && nameRu.isNotEmpty) return nameRu;
    if (locale == 'tr' && nameTr.isNotEmpty) return nameTr;
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name_ar': nameAr,
    'name_en': nameEn,
    'name_ru': nameRu,
    'name_tr': nameTr,
  };
}

class MemorizationPlan {
  const MemorizationPlan({
    required this.id,
    required this.editionCode,
    required this.contentVersion,
    required this.startAyah,
    required this.endAyah,
    required this.dailyRepetitions,
    required this.pauseSeconds,
    required this.timezoneName,
    required this.revision,
    this.recitationId,
    this.reciter,
  });

  factory MemorizationPlan.fromJson(Map<String, Object?> json) =>
      MemorizationPlan(
        id: json['id']?.toString() ?? '',
        editionCode: json['edition_code']?.toString() ?? 'madani-hafs',
        contentVersion: json['content_version']?.toString() ?? '',
        startAyah: MemorizationAyah.fromJson(jsonMap(json['start_ayah'])),
        endAyah: MemorizationAyah.fromJson(jsonMap(json['end_ayah'])),
        recitationId: json['recitation_id']?.toString(),
        reciter: json['reciter'] is Map
            ? MemorizationReciter.fromJson(jsonMap(json['reciter']))
            : null,
        dailyRepetitions: (json['daily_repetitions'] as num?)?.toInt() ?? 5,
        pauseSeconds: (json['pause_seconds'] as num?)?.toInt() ?? 2,
        timezoneName: json['timezone_name']?.toString() ?? 'UTC',
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String editionCode;
  final String contentVersion;
  final MemorizationAyah startAyah;
  final MemorizationAyah endAyah;
  final String? recitationId;
  final MemorizationReciter? reciter;
  final int dailyRepetitions;
  final int pauseSeconds;
  final String timezoneName;
  final int revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'edition_code': editionCode,
    'content_version': contentVersion,
    'start_ayah': startAyah.toJson(),
    'end_ayah': endAyah.toJson(),
    'recitation_id': recitationId,
    'reciter': reciter?.toJson(),
    'daily_repetitions': dailyRepetitions,
    'pause_seconds': pauseSeconds,
    'timezone_name': timezoneName,
    'revision': revision,
  };
}

class MemorizationSession {
  const MemorizationSession({
    required this.id,
    required this.planId,
    required this.completedRepetitions,
    required this.assessment,
    required this.durationSeconds,
    required this.localDate,
  });

  factory MemorizationSession.fromJson(Map<String, Object?> json) =>
      MemorizationSession(
        id: json['id']?.toString() ?? '',
        planId: json['plan_id']?.toString() ?? '',
        completedRepetitions:
            (json['completed_repetitions'] as num?)?.toInt() ?? 0,
        assessment:
            MemorizationAssessment.tryParse(json['assessment']) ??
            MemorizationAssessment.repeat,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        localDate: json['local_date']?.toString() ?? '',
      );

  final String id;
  final String planId;
  final int completedRepetitions;
  final MemorizationAssessment assessment;
  final int durationSeconds;
  final String localDate;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'plan_id': planId,
    'completed_repetitions': completedRepetitions,
    'assessment': assessment.wireValue,
    'duration_seconds': durationSeconds,
    'local_date': localDate,
  };
}

class MemorizationToday {
  const MemorizationToday({
    required this.localDate,
    required this.completedRepetitions,
    required this.targetRepetitions,
    required this.remainingRepetitions,
    required this.isCompleted,
    required this.sessions,
    this.lastAssessment,
  });

  factory MemorizationToday.empty() => const MemorizationToday(
    localDate: '',
    completedRepetitions: 0,
    targetRepetitions: 0,
    remainingRepetitions: 0,
    isCompleted: false,
    sessions: <MemorizationSession>[],
  );

  factory MemorizationToday.fromJson(
    Map<String, Object?> json,
  ) => MemorizationToday(
    localDate: json['local_date']?.toString() ?? '',
    completedRepetitions: (json['completed_repetitions'] as num?)?.toInt() ?? 0,
    targetRepetitions: (json['target_repetitions'] as num?)?.toInt() ?? 0,
    remainingRepetitions: (json['remaining_repetitions'] as num?)?.toInt() ?? 0,
    isCompleted: json['is_completed'] == true,
    lastAssessment: MemorizationAssessment.tryParse(json['last_assessment']),
    sessions: jsonResults(json['sessions'])
        .map((item) => MemorizationSession.fromJson(jsonMap(item)))
        .toList(growable: false),
  );

  final String localDate;
  final int completedRepetitions;
  final int targetRepetitions;
  final int remainingRepetitions;
  final bool isCompleted;
  final MemorizationAssessment? lastAssessment;
  final List<MemorizationSession> sessions;

  MemorizationToday add(MemorizationSession session) {
    final completed = completedRepetitions + session.completedRepetitions;
    return MemorizationToday(
      localDate: localDate,
      completedRepetitions: completed,
      targetRepetitions: targetRepetitions,
      remainingRepetitions: math.max(targetRepetitions - completed, 0),
      isCompleted: targetRepetitions > 0 && completed >= targetRepetitions,
      lastAssessment: session.assessment,
      sessions: <MemorizationSession>[session, ...sessions],
    );
  }

  MemorizationToday reset() => MemorizationToday(
    localDate: localDate,
    completedRepetitions: 0,
    targetRepetitions: targetRepetitions,
    remainingRepetitions: targetRepetitions,
    isCompleted: false,
    sessions: const <MemorizationSession>[],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'local_date': localDate,
    'completed_repetitions': completedRepetitions,
    'target_repetitions': targetRepetitions,
    'remaining_repetitions': remainingRepetitions,
    'is_completed': isCompleted,
    'last_assessment': lastAssessment?.wireValue,
    'sessions': sessions.map((item) => item.toJson()).toList(growable: false),
  };
}

class MemorizationRecentDay {
  const MemorizationRecentDay({
    required this.localDate,
    required this.completedRepetitions,
    required this.sessionCount,
    required this.lastAssessment,
  });

  factory MemorizationRecentDay.fromJson(Map<String, Object?> json) =>
      MemorizationRecentDay(
        localDate: json['local_date']?.toString() ?? '',
        completedRepetitions:
            (json['completed_repetitions'] as num?)?.toInt() ?? 0,
        sessionCount: (json['session_count'] as num?)?.toInt() ?? 0,
        lastAssessment:
            MemorizationAssessment.tryParse(json['last_assessment']) ??
            MemorizationAssessment.repeat,
      );

  final String localDate;
  final int completedRepetitions;
  final int sessionCount;
  final MemorizationAssessment lastAssessment;

  Map<String, Object?> toJson() => <String, Object?>{
    'local_date': localDate,
    'completed_repetitions': completedRepetitions,
    'session_count': sessionCount,
    'last_assessment': lastAssessment.wireValue,
  };
}

class MemorizationDashboard {
  const MemorizationDashboard({
    required this.timezoneName,
    required this.plan,
    required this.today,
    required this.recentDays,
    this.fromCache = false,
  });

  factory MemorizationDashboard.fromJson(
    Map<String, Object?> json, {
    bool fromCache = false,
  }) => MemorizationDashboard(
    timezoneName: json['timezone_name']?.toString() ?? 'UTC',
    plan: json['plan'] is Map
        ? MemorizationPlan.fromJson(jsonMap(json['plan']))
        : null,
    today: MemorizationToday.fromJson(jsonMap(json['today'])),
    recentDays: jsonResults(json['recent_days'])
        .map((item) => MemorizationRecentDay.fromJson(jsonMap(item)))
        .toList(growable: false),
    fromCache: fromCache,
  );

  factory MemorizationDashboard.empty(String timezoneName) =>
      MemorizationDashboard(
        timezoneName: timezoneName,
        plan: null,
        today: MemorizationToday.empty(),
        recentDays: const <MemorizationRecentDay>[],
      );

  final String timezoneName;
  final MemorizationPlan? plan;
  final MemorizationToday today;
  final List<MemorizationRecentDay> recentDays;
  final bool fromCache;

  MemorizationDashboard withPlan(MemorizationPlan value) =>
      MemorizationDashboard(
        timezoneName: value.timezoneName,
        plan: value,
        today: MemorizationToday(
          localDate: today.localDate,
          completedRepetitions: today.completedRepetitions,
          targetRepetitions: value.dailyRepetitions,
          remainingRepetitions: math.max(
            value.dailyRepetitions - today.completedRepetitions,
            0,
          ),
          isCompleted: today.completedRepetitions >= value.dailyRepetitions,
          lastAssessment: today.lastAssessment,
          sessions: today.sessions,
        ),
        recentDays: recentDays,
      );

  MemorizationDashboard withToday(MemorizationToday value) =>
      MemorizationDashboard(
        timezoneName: timezoneName,
        plan: plan,
        today: value,
        recentDays: recentDays,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'timezone_name': timezoneName,
    'plan': plan?.toJson(),
    'today': today.toJson(),
    'recent_days': recentDays
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

class MemorizationPlanDraft {
  const MemorizationPlanDraft({
    required this.startAyahId,
    required this.endAyahId,
    required this.dailyRepetitions,
    required this.pauseSeconds,
    this.recitationId,
  });

  final String startAyahId;
  final String endAyahId;
  final String? recitationId;
  final int dailyRepetitions;
  final int pauseSeconds;
}

abstract interface class MemorizationRemoteGateway {
  Future<Object?> dashboard(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });
  Future<Object?> savePlan(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });
  Future<Object?> createSession(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });
  Future<void> resetToday(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });
}

class ApiMemorizationRemoteGateway implements MemorizationRemoteGateway {
  ApiMemorizationRemoteGateway(this._api);
  final ApiClient _api;

  @override
  Future<Object?> dashboard(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/memorization',
    query: <String, Object?>{'timezone_name': timezoneName, 'recent_days': 14},
    accountScope: accountScope,
  );

  @override
  Future<Object?> savePlan(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.put('/me/memorization', data: payload, accountScope: accountScope);

  @override
  Future<Object?> createSession(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/memorization-sessions',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<void> resetToday(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) async {
    await _api.delete(
      '/me/memorization-sessions?timezone_name='
      '${Uri.encodeQueryComponent(timezoneName)}',
      accountScope: accountScope,
    );
  }
}

class MemorizationRepository {
  MemorizationRepository({
    required LocalDatabase database,
    ApiClient? api,
    MemorizationRemoteGateway? remote,
    Future<String> Function()? timezoneLoader,
    Uuid uuid = const Uuid(),
  }) : assert(api != null || remote != null),
       _database = database,
       _remote = remote ?? ApiMemorizationRemoteGateway(api!),
       _timezoneLoader = timezoneLoader ?? _deviceTimezone,
       _uuid = uuid;

  static const _cacheKey = 'memorization:dashboard';
  final LocalDatabase _database;
  final MemorizationRemoteGateway _remote;
  final Future<String> Function() _timezoneLoader;
  final Uuid _uuid;

  Future<MemorizationDashboard> load({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    return _loadFor(scope);
  }

  Future<MemorizationDashboard> _loadFor(AccountScopeSnapshot scope) async {
    final timezoneName = await _safeTimezone();
    _database.ensureCurrent(scope);
    try {
      final payload = await _remote.dashboard(
        timezoneName,
        accountScope: scope,
      );
      _database.ensureCurrent(scope);
      final dashboard = MemorizationDashboard.fromJson(jsonMap(payload));
      await _store(dashboard, scope);
      return dashboard;
    } on Object {
      _database.ensureCurrent(scope);
      final cached = await _cached(scope);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<MemorizationDashboard> savePlan(
    MemorizationPlanDraft draft, {
    int baseRevision = 0,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    if (draft.startAyahId.isEmpty || draft.endAyahId.isEmpty) {
      throw const FormatException('Memorization ayah range is incomplete');
    }
    if (draft.dailyRepetitions < 1 || draft.dailyRepetitions > 100) {
      throw const FormatException('Daily repetitions are out of range');
    }
    if (draft.pauseSeconds < 0 || draft.pauseSeconds > 30) {
      throw const FormatException('Pause is out of range');
    }
    final timezoneName = await _safeTimezone();
    _database.ensureCurrent(scope);
    final payload = await _remote.savePlan(<String, Object?>{
      'start_ayah_id': draft.startAyahId,
      'end_ayah_id': draft.endAyahId,
      'recitation_id': draft.recitationId,
      'daily_repetitions': draft.dailyRepetitions,
      'pause_seconds': draft.pauseSeconds,
      'timezone_name': timezoneName,
      'base_revision': baseRevision,
      'client_updated_at': DateTime.now().toUtc().toIso8601String(),
    }, accountScope: scope);
    _database.ensureCurrent(scope);
    final plan = MemorizationPlan.fromJson(jsonMap(payload));
    final current =
        await _cached(scope) ?? MemorizationDashboard.empty(timezoneName);
    final optimistic = current.withPlan(plan);
    await _store(optimistic, scope);
    return _refreshOr(optimistic, scope);
  }

  Future<MemorizationDashboard> assess(
    MemorizationAssessment assessment, {
    int repetitions = 1,
    Duration duration = Duration.zero,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final current = await _cached(scope) ?? await _loadFor(scope);
    final plan = current.plan;
    if (plan == null) throw const FormatException('Memorization plan missing');
    final now = DateTime.now().toUtc();
    final payload = await _remote.createSession(<String, Object?>{
      'id': _uuid.v7(),
      'plan_id': plan.id,
      'completed_repetitions': repetitions.clamp(1, 1000),
      'assessment': assessment.wireValue,
      'duration_seconds': duration.inSeconds.clamp(0, 86400),
      'timezone_name': current.timezoneName,
      'local_date': current.today.localDate,
      'client_updated_at': now.toIso8601String(),
    }, accountScope: scope);
    _database.ensureCurrent(scope);
    final session = MemorizationSession.fromJson(jsonMap(payload));
    final optimistic = current.withToday(current.today.add(session));
    await _store(optimistic, scope);
    return _refreshOr(optimistic, scope);
  }

  Future<MemorizationDashboard> reset({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final current = await _cached(scope) ?? await _loadFor(scope);
    await _remote.resetToday(current.timezoneName, accountScope: scope);
    _database.ensureCurrent(scope);
    final optimistic = current.withToday(current.today.reset());
    await _store(optimistic, scope);
    return _refreshOr(optimistic, scope);
  }

  Future<MemorizationDashboard> _refreshOr(
    MemorizationDashboard fallback,
    AccountScopeSnapshot scope,
  ) async {
    try {
      return await _loadFor(scope);
    } on AccountScopeChanged {
      rethrow;
    } on Object {
      _database.ensureCurrent(scope);
      return fallback;
    }
  }

  Future<MemorizationDashboard?> _cached(AccountScopeSnapshot scope) async {
    final cached = await _database.readAccountCache(
      _cacheKey,
      accountScope: scope,
    );
    if (cached == null) return null;
    try {
      return MemorizationDashboard.fromJson(
        jsonMap(cached.value),
        fromCache: true,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _store(
    MemorizationDashboard dashboard,
    AccountScopeSnapshot scope,
  ) => _database.writeAccountCache(
    _cacheKey,
    dashboard.toJson(),
    maxAge: const Duration(days: 30),
    accountScope: scope,
  );

  Future<String> _safeTimezone() async {
    try {
      final timezoneName = (await _timezoneLoader()).trim();
      return timezoneName.isEmpty ? 'UTC' : timezoneName;
    } on Object {
      return 'UTC';
    }
  }

  static Future<String> _deviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}
