import 'dart:async';

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

class ReadingPositionSummary {
  const ReadingPositionSummary({
    required this.editionCode,
    required this.page,
    required this.surah,
    required this.ayah,
  });

  factory ReadingPositionSummary.fromJson(Map<String, Object?> json) {
    final ayah = json['ayah'] is Map
        ? Map<String, Object?>.from(json['ayah']! as Map)
        : const <String, Object?>{};
    return ReadingPositionSummary(
      editionCode: json['edition_code']?.toString() ?? '',
      page: (json['page_number'] as num?)?.toInt() ?? 1,
      surah: (ayah['surah_number'] as num?)?.toInt(),
      ayah: (ayah['ayah_number'] as num?)?.toInt(),
    );
  }

  final String editionCode;
  final int page;
  final int? surah;
  final int? ayah;

  Map<String, Object?> toJson() => <String, Object?>{
    'edition_code': editionCode,
    'page_number': page,
    'surah_number': surah,
    'ayah_number': ayah,
  };
}

class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.source,
    required this.status,
    required this.timezoneName,
    required this.localDate,
    required this.activeSeconds,
    required this.creditedPages,
    required this.creditedAyahs,
    required this.manualMetric,
    required this.manualAmount,
    required this.revision,
    this.startedAt,
    this.endedAt,
    this.deletedAt,
  });

  factory ReadingSession.fromJson(Map<String, Object?> json) => ReadingSession(
    id: json['id']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    timezoneName: json['timezone_name']?.toString() ?? 'UTC',
    localDate: json['local_date']?.toString() ?? '',
    activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
    creditedPages: (json['credited_pages'] as num?)?.toInt() ?? 0,
    creditedAyahs: (json['credited_ayahs'] as num?)?.toInt() ?? 0,
    manualMetric: json['manual_metric'] == null
        ? null
        : ReadingGoalMetric.fromWire(json['manual_metric']),
    manualAmount: _amount(json['manual_amount']),
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
    endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
    deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
  );

  final String id;
  final String source;
  final String status;
  final String timezoneName;
  final String localDate;
  final int activeSeconds;
  final int creditedPages;
  final int creditedAyahs;
  final ReadingGoalMetric? manualMetric;
  final double manualAmount;
  final int revision;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? deletedAt;

  bool get isManual => source == 'manual' && status == 'completed';
  bool get isAutomatic => source == 'automatic' && status == 'completed';
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
    this.prayerCheckIns = const <PrayerReadingCheckIn>[],
    this.prayerCount = 0,
    this.automaticSessions = 0,
  });

  factory ReadingHistoryDay.fromJson(Map<String, Object?> json) {
    final goal = json['goal'] is Map
        ? Map<String, Object?>.from(json['goal']! as Map)
        : null;
    final checkIns = <PrayerReadingCheckIn>[];
    for (final raw
        in (json['prayer_check_ins'] as List?) ?? const <Object?>[]) {
      if (raw is Map) {
        checkIns.add(
          PrayerReadingCheckIn.fromJson(Map<String, Object?>.from(raw)),
        );
      }
    }
    return ReadingHistoryDay(
      localDate: _parseDateOnly(json['local_date']),
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
      prayerCheckIns: checkIns,
      prayerCount: (json['prayer_count'] as num?)?.toInt() ?? checkIns.length,
      automaticSessions: (json['automatic_sessions'] as num?)?.toInt() ?? 0,
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
  final List<PrayerReadingCheckIn> prayerCheckIns;
  final int prayerCount;
  final int automaticSessions;
}

class PrayerReadingCheckIn {
  const PrayerReadingCheckIn({
    required this.id,
    required this.prayer,
    required this.pages,
    required this.revision,
    this.localDate,
    this.timezoneName,
    this.readingSessionId,
  });

  factory PrayerReadingCheckIn.fromJson(Map<String, Object?> json) =>
      PrayerReadingCheckIn(
        id: json['id']?.toString() ?? '',
        prayer: json['prayer']?.toString() ?? '',
        pages: (json['pages'] as num?)?.toInt() ?? 0,
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        localDate: json['local_date']?.toString(),
        timezoneName: json['timezone_name']?.toString(),
        readingSessionId: json['reading_session_id']?.toString(),
      );

  final String id;
  final String prayer;
  final int pages;
  final int revision;
  final String? localDate;
  final String? timezoneName;
  final String? readingSessionId;
}

class ReadingPlanStats {
  const ReadingPlanStats({
    required this.readingDays,
    required this.completedDays,
    required this.partialDays,
  });

  final int readingDays;
  final int completedDays;
  final int partialDays;
}

class ReadingHistoryGroup {
  const ReadingHistoryGroup({
    required this.localDate,
    required this.manualSessions,
    required this.automaticSessions,
    required this.automaticSeconds,
    required this.automaticPages,
    required this.automaticAyahs,
  });

  final String localDate;
  final List<ReadingSession> manualSessions;
  final int automaticSessions;
  final int automaticSeconds;
  final int automaticPages;
  final int automaticAyahs;
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
    this.sessions = const <ReadingSession>[],
    this.continueReading,
    this.prayerPlanRevision,
    this.prayerPlanPages,
    this.prayerTimezoneName,
    this.prayerLocalDate,
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
       sessions = const <ReadingSession>[],
       continueReading = null,
       prayerPlanRevision = null,
       prayerPlanPages = null,
       prayerTimezoneName = null,
       prayerLocalDate = null,
       fromCache = false;

  factory DailyPlan.fromJson(Map<String, Object?> json) {
    final prayer = json['prayer_pages'] is Map
        ? Map<String, Object?>.from(json['prayer_pages']! as Map)
        : const <String, Object?>{};
    final continueReading = json['continue_reading'] is Map
        ? ReadingPositionSummary.fromJson(
            Map<String, Object?>.from(json['continue_reading']! as Map),
          )
        : null;
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
      prayerTimezoneName: json['prayer_timezone_name']?.toString(),
      prayerLocalDate: json['prayer_local_date']?.toString(),
      continueReading: continueReading,
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
    final sessions = <ReadingSession>[];
    for (final raw in jsonResults(snapshot['sessions'])) {
      if (raw is Map) {
        sessions.add(ReadingSession.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    final continueReading = today['continue_reading'] is Map
        ? ReadingPositionSummary.fromJson(
            Map<String, Object?>.from(today['continue_reading']! as Map),
          )
        : null;
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
      history: history.toList(growable: false),
      prayerCheckIns: checkIns,
      sessions: sessions,
      continueReading: continueReading,
      prayerPlanRevision: (rawPlan?['revision'] as num?)?.toInt(),
      prayerPlanPages: (rawPlan?['pages_per_prayer'] as num?)?.toInt(),
      prayerTimezoneName: prayer['timezone_name']?.toString(),
      prayerLocalDate: prayer['local_date']?.toString(),
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
  final String? prayerTimezoneName;
  final String? prayerLocalDate;
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
    List<ReadingSession>? sessions,
    ReadingPositionSummary? continueReading,
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
    sessions: sessions ?? this.sessions,
    continueReading: continueReading ?? this.continueReading,
    prayerPlanRevision: prayerPlanRevision ?? this.prayerPlanRevision,
    prayerPlanPages: prayerPlanPages ?? this.prayerPlanPages,
    prayerTimezoneName: prayerTimezoneName,
    prayerLocalDate: prayerLocalDate,
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
    'prayer_timezone_name': prayerTimezoneName,
    'prayer_local_date': prayerLocalDate,
    'continue_reading': continueReading?.toJson(),
    'from_cache': fromCache,
  };

  final List<ReadingSession> sessions;
  final ReadingPositionSummary? continueReading;

  List<ReadingHistoryDay> daysForRange(int rangeDays) {
    final count = rangeDays.clamp(7, 90);
    final today = _parseDateOnly(localDate);
    if (today == null) return history;
    final first = today.subtract(Duration(days: count - 1));
    return history
        .where(
          (day) =>
              day.localDate != null &&
              !day.localDate!.isBefore(first) &&
              !day.localDate!.isAfter(today),
        )
        .toList(growable: false);
  }

  ReadingHistoryDay? dayForDate(String date) {
    for (final day in history) {
      final localDate = day.localDate;
      if (localDate != null && _dateOnly(localDate) == date) return day;
    }
    return null;
  }

  ReadingPlanStats statsForRange(int rangeDays) {
    final days = daysForRange(rangeDays);
    return ReadingPlanStats(
      readingDays: days.where((day) => day.hasReading).length,
      completedDays: days.where((day) => day.state == 'completed').length,
      partialDays: days.where((day) => day.state == 'partial').length,
    );
  }

  List<ReadingHistoryGroup> historyGroupsForRange(int rangeDays) {
    final days = daysForRange(rangeDays);
    final visibleDates = <String>{};
    for (final day in days) {
      final date = _dateKey(day.localDate);
      if (date != null) visibleDates.add(date);
    }
    final prayerSessionIds = <String>{
      for (final day in days)
        for (final checkIn in day.prayerCheckIns)
          if (checkIn.readingSessionId != null) checkIn.readingSessionId!,
    };
    final groups = <String, _ReadingHistoryGroupBuilder>{};
    for (final day in days) {
      final date = _dateKey(day.localDate);
      if (date == null || day.automaticSessions == 0) continue;
      groups[date] = _ReadingHistoryGroupBuilder(
        localDate: date,
        automaticSessions: day.automaticSessions,
        automaticSeconds: day.automaticSeconds,
        automaticPages: day.automaticPages,
        automaticAyahs: day.automaticAyahs,
      );
    }
    for (final session in sessions) {
      if (!session.isManual || !visibleDates.contains(session.localDate)) {
        continue;
      }
      if (prayerSessionIds.contains(session.id)) continue;
      final group = groups.putIfAbsent(
        session.localDate,
        () => _ReadingHistoryGroupBuilder(localDate: session.localDate),
      );
      group.manualSessions.add(session);
    }
    final result = groups.values
        .map((group) => group.build())
        .toList(growable: false);
    result.sort((left, right) => right.localDate.compareTo(left.localDate));
    return result;
  }
}

class _ReadingHistoryGroupBuilder {
  _ReadingHistoryGroupBuilder({
    required this.localDate,
    this.automaticSessions = 0,
    this.automaticSeconds = 0,
    this.automaticPages = 0,
    this.automaticAyahs = 0,
  });

  final String localDate;
  final int automaticSessions;
  final int automaticSeconds;
  final int automaticPages;
  final int automaticAyahs;
  final List<ReadingSession> manualSessions = <ReadingSession>[];

  ReadingHistoryGroup build() {
    manualSessions.sort(
      (left, right) => right.localDate.compareTo(left.localDate),
    );
    return ReadingHistoryGroup(
      localDate: localDate,
      manualSessions: List<ReadingSession>.unmodifiable(manualSessions),
      automaticSessions: automaticSessions,
      automaticSeconds: automaticSeconds,
      automaticPages: automaticPages,
      automaticAyahs: automaticAyahs,
    );
  }
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

  Future<Object?> sessions({
    int limit = 100,
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> prayerDay(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  });

  Future<Object?> updateManualSession(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  });

  Future<void> deleteManualSession(
    String id,
    int revision,
    DateTime updatedAt, {
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

  Future<Object?> recordAutomatic(
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
    query: <String, Object?>{'days': 90, 'timezone_name': timezoneName},
    accountScope: accountScope,
  );

  @override
  Future<Object?> sessions({
    int limit = 100,
    AccountScopeSnapshot? accountScope,
  }) => _api.get(
    '/me/reading-sessions',
    query: <String, Object?>{'limit': limit},
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
  Future<Object?> updateManualSession(
    String id,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.patch(
    '/me/reading-sessions/$id',
    data: payload,
    accountScope: accountScope,
  );

  @override
  Future<void> deleteManualSession(
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
      '/me/reading-sessions/$id?$query',
      accountScope: accountScope,
    );
  }

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
  Future<Object?> recordAutomatic(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) => _api.post(
    '/me/reading-sessions/automatic',
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
  static const _pendingSessionsKey = 'reading:pending-automatic-sessions';
  final LocalDatabase _database;
  final PlanRemoteGateway? _remote;
  final Future<String> Function() _timezoneLoader;
  final Uuid _uuid;
  final StreamController<int> _updates = StreamController<int>.broadcast();
  var _updateVersion = 0;

  Stream<int> get updates => _updates.stream;

  ReadingSessionRecorder startReadingSession({
    required AccountScopeSnapshot accountScope,
    DateTime Function()? clock,
  }) => ReadingSessionRecorder._(
    repository: this,
    accountScope: accountScope,
    id: _uuid.v7(),
    clock: clock ?? DateTime.now,
  );

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
    await _flushAutomaticSessions(remote, scope);
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
      remote.sessions(accountScope: scope),
    ]);
    _database.ensureCurrent(scope);
    final snapshot = <String, Object?>{
      'today': today,
      'planner': jsonMap(results[0]),
      'prayer': jsonMap(results[1]),
      'sessions': results[2],
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

  Future<DailyPlan> updateManualReading(
    ReadingSession session, {
    required ReadingGoalMetric metric,
    required double amount,
    required String localDate,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (!session.isManual || session.id.isEmpty) {
      throw const FormatException('Only manual reading can be edited');
    }
    if (amount <= 0 || amount > maximumReadingTarget(metric)) {
      throw const FormatException('Reading amount is out of range');
    }
    final parsedDate = DateTime.tryParse(localDate);
    if (parsedDate == null) {
      throw const FormatException('Reading date is invalid');
    }
    final scope = accountScope ?? await _database.captureAccount();
    final remote = _remote;
    if (remote == null) {
      throw StateError('Manual reading editing requires an account');
    }
    final now = DateTime.now().toUtc();
    await remote.updateManualSession(session.id, <String, Object?>{
      'timezone_name': session.timezoneName,
      'local_date': _dateOnly(parsedDate),
      'metric': metric.wireValue,
      'amount': amount,
      'base_revision': session.revision,
      'client_updated_at': now.toIso8601String(),
    }, accountScope: scope);
    _database.ensureCurrent(scope);
    return _loadRemote(scope);
  }

  Future<DailyPlan> deleteManualReading(
    ReadingSession session, {
    AccountScopeSnapshot? accountScope,
  }) async {
    if (!session.isManual || session.id.isEmpty) {
      throw const FormatException('Only manual reading can be deleted');
    }
    final scope = accountScope ?? await _database.captureAccount();
    final remote = _remote;
    if (remote == null) {
      throw StateError('Manual reading editing requires an account');
    }
    await remote.deleteManualSession(
      session.id,
      session.revision,
      DateTime.now().toUtc(),
      accountScope: scope,
    );
    _database.ensureCurrent(scope);
    return _loadRemote(scope);
  }

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
    // Mutations need current revisions; an offline snapshot is read-only.
    final current = remote == null
        ? await _loadLocal(scope)
        : await _loadRemote(scope);
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
    final prayerTimezone = current.prayerTimezoneName ?? current.timezoneName;
    final timezoneName = prayerTimezone.isEmpty
        ? await _safeTimezone()
        : prayerTimezone;
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
        'local_date': plan.prayerLocalDate ?? plan.localDate,
        'timezone_name': plan.prayerTimezoneName ?? timezoneName,
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

  Future<void> _completeReadingSession(ReadingSessionRecorder session) async {
    final remote = _remote;
    if (remote == null) return;
    final scope = session.accountScope;
    try {
      _database.ensureCurrent(scope);
      final payload = session._payload(await _safeTimezone());
      if (payload == null) return;
      _database.ensureCurrent(scope);
      await remote.recordAutomatic(payload, accountScope: scope);
      _database.ensureCurrent(scope);
      _notifyUpdated();
    } on AccountScopeChanged {
      // Finishing an old route after an account handoff must not attribute its
      // reading to the new owner or surface an unhandled dispose-time error.
      return;
    } on Object {
      try {
        _database.ensureCurrent(scope);
        final payload = session._payload(await _safeTimezone());
        if (payload != null) {
          await _savePendingAutomaticSession(payload, scope);
        }
      } on AccountScopeChanged {
        return;
      }
    }
  }

  Future<void> _savePendingAutomaticSession(
    Map<String, Object?> payload,
    AccountScopeSnapshot scope,
  ) async {
    final state = await _database.readState(
      _pendingSessionsKey,
      accountScope: scope,
    );
    final pending = _pendingSessions(state);
    if (!pending.any((item) => item['id'] == payload['id'])) {
      pending.add(payload);
    }
    await _writePendingSessions(pending, scope);
  }

  Future<void> _flushAutomaticSessions(
    PlanRemoteGateway remote,
    AccountScopeSnapshot scope,
  ) async {
    final state = await _database.readState(
      _pendingSessionsKey,
      accountScope: scope,
    );
    final pending = _pendingSessions(state);
    if (pending.isEmpty) return;
    final remaining = <Map<String, Object?>>[];
    var failed = false;
    for (final payload in pending) {
      if (failed) {
        remaining.add(payload);
        continue;
      }
      try {
        await remote.recordAutomatic(payload, accountScope: scope);
        _database.ensureCurrent(scope);
        _notifyUpdated();
      } on AccountScopeChanged {
        rethrow;
      } on Object {
        failed = true;
        remaining.add(payload);
      }
    }
    await _writePendingSessions(remaining, scope);
  }

  List<Map<String, Object?>> _pendingSessions(Map<String, Object?>? state) {
    final pending = <Map<String, Object?>>[];
    for (final raw in (state?['items'] as List?) ?? const <Object?>[]) {
      if (raw is Map) pending.add(Map<String, Object?>.from(raw));
    }
    return pending;
  }

  Future<void> _writePendingSessions(
    List<Map<String, Object?>> pending,
    AccountScopeSnapshot scope,
  ) => _database.writeState(_pendingSessionsKey, <String, Object?>{
    'items': pending,
  }, accountScope: scope);

  void _notifyUpdated() => _updates.add(++_updateVersion);

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

class ReadingSessionRecorder {
  ReadingSessionRecorder._({
    required PlanRepository repository,
    required this.accountScope,
    required String id,
    required DateTime Function() clock,
  }) : _repository = repository,
       _id = id,
       _clock = clock {
    _startedAt = clock().toUtc();
    _activeSince = _startedAt;
  }

  final PlanRepository _repository;
  final AccountScopeSnapshot accountScope;
  final String _id;
  final DateTime Function() _clock;
  late final DateTime _startedAt;
  DateTime? _activeSince;
  Duration _activeDuration = Duration.zero;
  final Set<int> _creditedPages = <int>{};
  final Set<String> _creditedAyahs = <String>{};
  int? _lastPage;
  int? _lastSurah;
  int? _lastAyah;
  DateTime? _endedAt;
  Future<void>? _completion;

  void observe({required int page, required int surah, required int ayah}) {
    if (_completion != null || page < 1 || surah < 1 || ayah < 1) return;
    final lastPage = _lastPage;
    final lastSurah = _lastSurah;
    final lastAyah = _lastAyah;
    if (lastPage != null && lastSurah != null && lastAyah != null) {
      final pageDelta = page - lastPage;
      if (pageDelta == 1) _creditedPages.add(page);
      if (pageDelta >= 0 && pageDelta <= 1) {
        if (surah == lastSurah) {
          final ayahDelta = ayah - lastAyah;
          if (ayahDelta > 0 && ayahDelta <= 20) {
            for (var number = lastAyah + 1; number <= ayah; number++) {
              _creditedAyahs.add('$surah:$number');
            }
          }
        } else if (surah == lastSurah + 1 && ayah <= 10) {
          for (var number = 1; number <= ayah; number++) {
            _creditedAyahs.add('$surah:$number');
          }
        }
      }
    }
    _lastPage = page;
    _lastSurah = surah;
    _lastAyah = ayah;
  }

  void pause() {
    if (_completion != null) return;
    final activeSince = _activeSince;
    if (activeSince == null) return;
    final now = _clock().toUtc();
    if (now.isAfter(activeSince)) {
      _activeDuration += now.difference(activeSince);
    }
    _activeSince = null;
  }

  void resume() {
    if (_completion != null || _activeSince != null) return;
    _activeSince = _clock().toUtc();
  }

  Future<void> finish() {
    final current = _completion;
    if (current != null) return current;
    pause();
    _endedAt = _clock().toUtc();
    return _completion = _repository._completeReadingSession(this);
  }

  Map<String, Object?>? _payload(String timezoneName) {
    final endedAt = _endedAt;
    if (endedAt == null) return null;
    final elapsed = endedAt.difference(_startedAt).inSeconds.clamp(0, 86400);
    final activeSeconds = _activeDuration.inSeconds.clamp(0, elapsed);
    if (activeSeconds < 60 &&
        _creditedPages.isEmpty &&
        _creditedAyahs.isEmpty) {
      return null;
    }
    return <String, Object?>{
      'id': _id,
      'timezone_name': timezoneName,
      'started_at': _startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'active_seconds': activeSeconds,
      'credited_pages': _creditedPages.length,
      'credited_ayahs': _creditedAyahs.length,
      'client_updated_at': endedAt.toIso8601String(),
    };
  }
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

String? _dateKey(DateTime? value) => value == null ? null : _dateOnly(value);

DateTime? _parseDateOnly(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  if (raw.contains('T')) return parsed;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
