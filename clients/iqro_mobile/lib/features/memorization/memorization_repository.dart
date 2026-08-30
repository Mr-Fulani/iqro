import '../../core/storage/local_database.dart';

class MemorizationState {
  const MemorizationState({
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.target,
    required this.completed,
    this.assessment,
  });

  const MemorizationState.initial()
    : surah = 1,
      startAyah = 1,
      endAyah = 3,
      target = 5,
      completed = 0,
      assessment = null;

  factory MemorizationState.fromJson(Map<String, Object?> json) =>
      MemorizationState(
        surah: (json['surah'] as num?)?.toInt() ?? 1,
        startAyah: (json['start_ayah'] as num?)?.toInt() ?? 1,
        endAyah: (json['end_ayah'] as num?)?.toInt() ?? 3,
        target: (json['target'] as num?)?.toInt() ?? 5,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        assessment: json['assessment']?.toString(),
      );

  final int surah;
  final int startAyah;
  final int endAyah;
  final int target;
  final int completed;
  final String? assessment;

  MemorizationState copyWith({
    int? completed,
    String? assessment,
    bool clear = false,
  }) => MemorizationState(
    surah: surah,
    startAyah: startAyah,
    endAyah: endAyah,
    target: target,
    completed: clear ? 0 : completed ?? this.completed,
    assessment: clear ? null : assessment ?? this.assessment,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'surah': surah,
    'start_ayah': startAyah,
    'end_ayah': endAyah,
    'target': target,
    'completed': completed,
    'assessment': assessment,
  };
}

class MemorizationRepository {
  MemorizationRepository(this._database);
  final LocalDatabase _database;

  Future<MemorizationState> load() async {
    final state = await _database.readState('memorization_today');
    return state == null
        ? const MemorizationState.initial()
        : MemorizationState.fromJson(state);
  }

  Future<MemorizationState> assess(String assessment) async {
    final current = await load();
    final next = current.copyWith(
      completed: (current.completed + 1).clamp(0, current.target),
      assessment: assessment,
    );
    await _database.writeState('memorization_today', next.toJson());
    return next;
  }

  Future<MemorizationState> reset() async {
    final next = (await load()).copyWith(clear: true);
    await _database.writeState('memorization_today', next.toJson());
    return next;
  }
}
