enum ReminderType { prayer, quranReading, quranReview }

enum ReminderSignal { sound, vibration, silent }

enum ReminderTimezoneMode { deviceLocal, fixed }

enum ReminderPermission { unknown, denied, granted }

class ReminderSchedule {
  const ReminderSchedule._({
    required this.kind,
    this.prayerEvent,
    this.prayerOffsetMinutes = 0,
    this.localTime,
  });

  const ReminderSchedule.prayer({
    required String prayerEvent,
    int prayerOffsetMinutes = 0,
  }) : this._(
         kind: 'prayer',
         prayerEvent: prayerEvent,
         prayerOffsetMinutes: prayerOffsetMinutes,
       );

  const ReminderSchedule.localTime(String localTime)
    : this._(kind: 'local_time', localTime: localTime);

  factory ReminderSchedule.fromJson(Map<String, Object?> json) {
    if (json['kind'] == 'prayer') {
      return ReminderSchedule.prayer(
        prayerEvent: json['prayer_event']?.toString() ?? 'fajr',
        prayerOffsetMinutes:
            (json['prayer_offset_minutes'] as num?)?.toInt() ?? 0,
      );
    }
    return ReminderSchedule.localTime(
      json['local_time']?.toString() ?? '08:00:00',
    );
  }

  final String kind;
  final String? prayerEvent;
  final int prayerOffsetMinutes;
  final String? localTime;

  Map<String, Object?> toJson() => kind == 'prayer'
      ? <String, Object?>{
          'kind': kind,
          'prayer_event': prayerEvent,
          'prayer_offset_minutes': prayerOffsetMinutes,
        }
      : <String, Object?>{'kind': kind, 'local_time': localTime};

  ({int hour, int minute}) get timeParts {
    final parts = (localTime ?? '08:00').split(':');
    return (
      hour: int.tryParse(parts.first) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
  }
}

class ReminderAyah {
  const ReminderAyah({
    required this.id,
    required this.surah,
    required this.ayah,
  });

  factory ReminderAyah.fromJson(Map<String, Object?> json) => ReminderAyah(
    id: json['id']?.toString() ?? '',
    surah: (json['surah_number'] as num?)?.toInt() ?? 1,
    ayah: (json['ayah_number'] as num?)?.toInt() ?? 1,
  );

  final String id;
  final int surah;
  final int ayah;
}

class ReminderReviewTarget {
  const ReminderReviewTarget({required this.start, required this.end});

  factory ReminderReviewTarget.fromJson(Map<String, Object?> json) {
    final start = json['start'] is Map
        ? Map<String, Object?>.from(json['start']! as Map)
        : const <String, Object?>{};
    final end = json['end'] is Map
        ? Map<String, Object?>.from(json['end']! as Map)
        : const <String, Object?>{};
    return ReminderReviewTarget(
      start: ReminderAyah.fromJson(start),
      end: ReminderAyah.fromJson(end),
    );
  }

  final ReminderAyah start;
  final ReminderAyah end;

  Map<String, Object?> toRequestJson() => <String, Object?>{
    'start_ayah_id': start.id,
    'end_ayah_id': end.id,
  };
}

class ReminderRule {
  const ReminderRule({
    required this.id,
    required this.type,
    required this.schedule,
    required this.weekdaysMask,
    required this.timezoneMode,
    required this.signal,
    required this.isEnabled,
    required this.revision,
    required this.clientUpdatedAt,
    this.timezoneName,
    this.reviewTarget,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory ReminderRule.fromJson(Map<String, Object?> json) {
    final rawSchedule = json['schedule'] is Map
        ? Map<String, Object?>.from(json['schedule']! as Map)
        : const <String, Object?>{'kind': 'local_time'};
    final rawTimezone = json['timezone'] is Map
        ? Map<String, Object?>.from(json['timezone']! as Map)
        : const <String, Object?>{'mode': 'device_local'};
    final rawTarget = json['review_target'];
    return ReminderRule(
      id: json['id']?.toString() ?? '',
      type: switch (json['reminder_type']?.toString()) {
        'prayer' => ReminderType.prayer,
        'quran_review' => ReminderType.quranReview,
        _ => ReminderType.quranReading,
      },
      schedule: ReminderSchedule.fromJson(rawSchedule),
      weekdaysMask: (json['weekdays_mask'] as num?)?.toInt() ?? 127,
      timezoneMode: rawTimezone['mode'] == 'fixed'
          ? ReminderTimezoneMode.fixed
          : ReminderTimezoneMode.deviceLocal,
      timezoneName: rawTimezone['name']?.toString(),
      signal: switch (json['signal']?.toString()) {
        'silent' => ReminderSignal.silent,
        'vibration' => ReminderSignal.vibration,
        _ => ReminderSignal.sound,
      },
      isEnabled: json['is_enabled'] != false,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      clientUpdatedAt:
          DateTime.tryParse(json['client_updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      reviewTarget: rawTarget is Map
          ? ReminderReviewTarget.fromJson(Map<String, Object?>.from(rawTarget))
          : null,
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  final String id;
  final ReminderType type;
  final ReminderSchedule schedule;
  final ReminderReviewTarget? reviewTarget;
  final int weekdaysMask;
  final ReminderTimezoneMode timezoneMode;
  final String? timezoneName;
  final ReminderSignal signal;
  final bool isEnabled;
  final int revision;
  final DateTime clientUpdatedAt;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get active => deletedAt == null;

  String get typeValue => switch (type) {
    ReminderType.prayer => 'prayer',
    ReminderType.quranReading => 'quran_reading',
    ReminderType.quranReview => 'quran_review',
  };

  Map<String, Object?> get functionalJson => <String, Object?>{
    'reminder_type': typeValue,
    'schedule': schedule.toJson(),
    if (reviewTarget != null) 'review_target': reviewTarget!.toRequestJson(),
    'weekdays_mask': weekdaysMask,
    'timezone': <String, Object?>{
      'mode': timezoneMode == ReminderTimezoneMode.fixed
          ? 'fixed'
          : 'device_local',
      if (timezoneMode == ReminderTimezoneMode.fixed) 'name': timezoneName,
    },
    'signal': signal.name,
    'is_enabled': isEnabled,
  };

  Map<String, Object?> toLocalJson() => <String, Object?>{
    'id': id,
    ...functionalJson,
    'revision': revision,
    'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
    'delivery_mode': 'local',
    'device_id': null,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': (updatedAt ?? clientUpdatedAt).toUtc().toIso8601String(),
    if (reviewTarget != null)
      'review_target': <String, Object?>{
        'start': <String, Object?>{
          'id': reviewTarget!.start.id,
          'surah_number': reviewTarget!.start.surah,
          'ayah_number': reviewTarget!.start.ayah,
        },
        'end': <String, Object?>{
          'id': reviewTarget!.end.id,
          'surah_number': reviewTarget!.end.surah,
          'ayah_number': reviewTarget!.end.ayah,
        },
      },
  };

  ReminderRule copyWith({
    ReminderSchedule? schedule,
    ReminderReviewTarget? reviewTarget,
    int? weekdaysMask,
    ReminderTimezoneMode? timezoneMode,
    String? timezoneName,
    ReminderSignal? signal,
    bool? isEnabled,
    int? revision,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
  }) => ReminderRule(
    id: id,
    type: type,
    schedule: schedule ?? this.schedule,
    reviewTarget: reviewTarget ?? this.reviewTarget,
    weekdaysMask: weekdaysMask ?? this.weekdaysMask,
    timezoneMode: timezoneMode ?? this.timezoneMode,
    timezoneName: timezoneName ?? this.timezoneName,
    signal: signal ?? this.signal,
    isEnabled: isEnabled ?? this.isEnabled,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
  );
}

class ReminderState {
  const ReminderState({
    this.rules = const <ReminderRule>[],
    this.permission = ReminderPermission.unknown,
    this.loading = true,
    this.saving = false,
    this.offline = false,
    this.exactScheduling = true,
    this.error,
  });

  final List<ReminderRule> rules;
  final ReminderPermission permission;
  final bool loading;
  final bool saving;
  final bool offline;
  final bool exactScheduling;
  final Object? error;

  ReminderState copyWith({
    List<ReminderRule>? rules,
    ReminderPermission? permission,
    bool? loading,
    bool? saving,
    bool? offline,
    bool? exactScheduling,
    Object? error,
    bool clearError = false,
  }) => ReminderState(
    rules: rules ?? this.rules,
    permission: permission ?? this.permission,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    offline: offline ?? this.offline,
    exactScheduling: exactScheduling ?? this.exactScheduling,
    error: clearError ? null : error ?? this.error,
  );
}

bool reminderRunsOnWeekday(int mask, int weekday) =>
    mask & (1 << (weekday - 1)) != 0;
