import 'dart:math' as math;

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
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

enum MemorizationItemStatus {
  active('active'),
  queued('queued'),
  memorized('memorized');

  const MemorizationItemStatus(this.wireValue);
  final String wireValue;

  static MemorizationItemStatus tryParse(Object? value) =>
      values.where((item) => item.wireValue == value?.toString()).firstOrNull ??
      queued;
}

/// One range of the memorization list; the active one is the plan's range.
class MemorizationItem {
  const MemorizationItem({
    required this.id,
    required this.status,
    required this.position,
    required this.startAyah,
    required this.endAyah,
  });

  factory MemorizationItem.fromJson(Map<String, Object?> json) =>
      MemorizationItem(
        id: json['id']?.toString() ?? '',
        status: MemorizationItemStatus.tryParse(json['status']),
        position: (json['position'] as num?)?.toInt() ?? 0,
        startAyah: MemorizationAyah.fromJson(jsonMap(json['start_ayah'])),
        endAyah: MemorizationAyah.fromJson(jsonMap(json['end_ayah'])),
      );

  final String id;
  final MemorizationItemStatus status;
  final int position;
  final MemorizationAyah startAyah;
  final MemorizationAyah endAyah;

  int get surah => startAyah.surah;
  int get ayahCount => endAyah.ayah - startAyah.ayah + 1;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.wireValue,
    'position': position,
    'start_ayah': startAyah.toJson(),
    'end_ayah': endAyah.toJson(),
  };
}

/// A Mushaf selection; it may run into the next surah.
class MemorizationSelection {
  const MemorizationSelection({
    required this.startSurah,
    required this.startAyah,
    required this.endSurah,
    required this.endAyah,
  });

  final int startSurah;
  final int startAyah;
  final int endSurah;
  final int endAyah;

  Map<String, Object?> toJson() => <String, Object?>{
    'start_surah': startSurah,
    'start_ayah': startAyah,
    'end_surah': endSurah,
    'end_ayah': endAyah,
  };
}

enum MemorizationAddMode {
  queue('queue'),
  now('now'),
  extend('extend');

  const MemorizationAddMode(this.wireValue);
  final String wireValue;
}

enum MemorizationPreviewState { empty, duplicate, extendable, choose }

/// Which choice the Mushaf menu offers for a selection, decided by the server.
class MemorizationSelectionPreview {
  const MemorizationSelectionPreview({
    required this.state,
    required this.revision,
    this.item,
    this.extendSurah,
    this.extendStartAyah,
    this.extendEndAyah,
  });

  factory MemorizationSelectionPreview.fromJson(Map<String, Object?> json) {
    final extend = json['extend_to'] is Map ? jsonMap(json['extend_to']) : null;
    return MemorizationSelectionPreview(
      state:
          MemorizationPreviewState.values
              .where((item) => item.name == json['state']?.toString())
              .firstOrNull ??
          MemorizationPreviewState.choose,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      item: json['item'] is Map
          ? MemorizationItem.fromJson(jsonMap(json['item']))
          : null,
      extendSurah: (extend?['surah_number'] as num?)?.toInt(),
      extendStartAyah: (extend?['start_ayah_number'] as num?)?.toInt(),
      extendEndAyah: (extend?['end_ayah_number'] as num?)?.toInt(),
    );
  }

  final MemorizationPreviewState state;
  final int revision;
  final MemorizationItem? item;
  final int? extendSurah;
  final int? extendStartAyah;
  final int? extendEndAyah;
}

class MemorizationDashboard {
  const MemorizationDashboard({
    required this.timezoneName,
    required this.plan,
    required this.today,
    required this.recentDays,
    this.revision = 0,
    this.items = const <MemorizationItem>[],
    this.memorizedAyahCount = 0,
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
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    items: _items(json['items']),
    memorizedAyahCount: (json['memorized_ayah_count'] as num?)?.toInt() ?? 0,
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
  final int revision;
  final List<MemorizationItem> items;
  final int memorizedAyahCount;
  final bool fromCache;

  MemorizationItem? get activeItem => items
      .where((item) => item.status == MemorizationItemStatus.active)
      .firstOrNull;

  List<MemorizationItem> get queuedItems => items
      .where((item) => item.status == MemorizationItemStatus.queued)
      .toList(growable: false);

  /// A list mutation response carries the new plan and the whole list.
  MemorizationDashboard withList(Map<String, Object?> json) {
    final next = MemorizationDashboard(
      timezoneName: timezoneName,
      plan: plan,
      today: today,
      recentDays: recentDays,
      revision: (json['revision'] as num?)?.toInt() ?? revision,
      items: _items(json['items']),
      memorizedAyahCount:
          (json['memorized_ayah_count'] as num?)?.toInt() ?? memorizedAyahCount,
    );
    return json['plan'] is Map
        ? next.withPlan(MemorizationPlan.fromJson(jsonMap(json['plan'])))
        : next;
  }

  static List<MemorizationItem> _items(Object? value) => jsonResults(value)
      .map((item) => MemorizationItem.fromJson(jsonMap(item)))
      .toList(growable: false);

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
        revision: value.revision,
        items: items,
        memorizedAyahCount: memorizedAyahCount,
      );

  MemorizationDashboard withToday(MemorizationToday value) =>
      MemorizationDashboard(
        timezoneName: timezoneName,
        plan: plan,
        today: value,
        recentDays: recentDays,
        revision: revision,
        items: items,
        memorizedAyahCount: memorizedAyahCount,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'timezone_name': timezoneName,
    'plan': plan?.toJson(),
    'today': today.toJson(),
    'recent_days': recentDays
        .map((item) => item.toJson())
        .toList(growable: false),
    'revision': revision,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'memorized_ayah_count': memorizedAyahCount,
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
  Future<Object?> previewSelection(
    Map<String, Object?> query, {
    AccountScopeSnapshot? accountScope,
  });
  Future<Object?> addSelection(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });
  Future<Object?> updateItem(
    String itemId,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });
  Future<Object?> removeItem(
    String itemId,
    int baseRevision, {
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

  @override
  Future<Object?> previewSelection(
    Map<String, Object?> query, {
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/memorization-items/preview',
    query: query,
    accountScope: accountScope,
  );

  @override
  Future<Object?> addSelection(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/memorization-items',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<Object?> updateItem(
    String itemId,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.patch(
    '/me/memorization-items/${Uri.encodeComponent(itemId)}',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<Object?> removeItem(
    String itemId,
    int baseRevision, {
    AccountScopeSnapshot? accountScope,
  }) => _api.delete(
    '/me/memorization-items/${Uri.encodeComponent(itemId)}'
    '?base_revision=$baseRevision',
    accountScope: accountScope,
  );
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

  /// The dashboard saved by the last [load] while it is still today's, shown
  /// at once while the next one waits for the server. A copy from an earlier
  /// day is never shown: its repetitions are not today's.
  Future<MemorizationDashboard?> cachedToday({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final cached = await _cached(scope);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return cached?.today.localDate == today ? cached : null;
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

  Future<MemorizationSelectionPreview> preview(
    MemorizationSelection selection, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final payload = await _remote.previewSelection(
      selection.toJson(),
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return MemorizationSelectionPreview.fromJson(jsonMap(payload));
  }

  /// Adds a Mushaf selection; the result says what the server did with it.
  Future<({String result, MemorizationDashboard dashboard})> addSelection(
    MemorizationSelection selection, {
    required MemorizationAddMode mode,
    required int baseRevision,
    String? recitationId,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final timezoneName = await _safeTimezone();
    _database.ensureCurrent(scope);
    final payload = jsonMap(
      await _remote.addSelection(<String, Object?>{
        ...selection.toJson(),
        'mode': mode.wireValue,
        'source': 'mushaf',
        'recitation_id': recitationId,
        'timezone_name': timezoneName,
        'base_revision': baseRevision,
        'client_updated_at': DateTime.now().toUtc().toIso8601String(),
      }, accountScope: scope),
    );
    return (
      result: payload['result']?.toString() ?? '',
      dashboard: await _applyList(payload, scope, timezoneName),
    );
  }

  Future<MemorizationDashboard> updateItem(
    String itemId,
    MemorizationItemStatus status, {
    required int baseRevision,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final payload = jsonMap(
      await _remote.updateItem(itemId, <String, Object?>{
        'status': status.wireValue,
        'base_revision': baseRevision,
        'client_updated_at': DateTime.now().toUtc().toIso8601String(),
      }, accountScope: scope),
    );
    return _applyList(payload, scope, await _safeTimezone());
  }

  Future<MemorizationDashboard> removeItem(
    String itemId, {
    required int baseRevision,
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _database.captureAccount();
    _database.ensureCurrent(scope);
    final payload = jsonMap(
      await _remote.removeItem(itemId, baseRevision, accountScope: scope),
    );
    return _applyList(payload, scope, await _safeTimezone());
  }

  Future<MemorizationDashboard> _applyList(
    Map<String, Object?> payload,
    AccountScopeSnapshot scope,
    String timezoneName,
  ) async {
    _database.ensureCurrent(scope);
    final current =
        await _cached(scope) ?? MemorizationDashboard.empty(timezoneName);
    final optimistic = current.withList(payload);
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
