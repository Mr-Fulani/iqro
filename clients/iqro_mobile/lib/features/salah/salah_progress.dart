import 'package:flutter/foundation.dart';

import '../../core/storage/local_database.dart';
import 'salah_models.dart';

enum SalahLessonStatus { notStarted, inProgress, completed }

/// Progress of one lesson, as stored in `app_state`.
///
/// The site keeps the same JSON in `localStorage` (spec §7.2).
@immutable
class SalahLessonProgress {
  const SalahLessonProgress({
    required this.status,
    required this.stepSlug,
    required this.contentVersion,
    this.updatedAt,
  });

  factory SalahLessonProgress.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return SalahLessonProgress(
      status: switch (json['status']) {
        'completed' => SalahLessonStatus.completed,
        'in_progress' => SalahLessonStatus.inProgress,
        _ => SalahLessonStatus.notStarted,
      },
      stepSlug: json['step_slug']?.toString() ?? '',
      contentVersion: json['content_version']?.toString() ?? '',
      updatedAt: json['updated_at'] is String
          ? DateTime.tryParse(json['updated_at']! as String)
          : null,
    );
  }

  final SalahLessonStatus status;
  final String stepSlug;
  final String contentVersion;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': switch (status) {
      SalahLessonStatus.completed => 'completed',
      SalahLessonStatus.inProgress => 'in_progress',
      SalahLessonStatus.notStarted => 'not_started',
    },
    'step_slug': stepSlug,
    'content_version': contentVersion,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
}

@immutable
class SalahCourseProgress {
  const SalahCourseProgress([this.lessons = const {}]);

  factory SalahCourseProgress.fromJson(Map<String, Object?>? json) {
    final lessons = json?['lessons'];
    if (lessons is! Map) return const SalahCourseProgress();
    return SalahCourseProgress(<String, SalahLessonProgress>{
      for (final entry in lessons.entries)
        entry.key.toString(): SalahLessonProgress.fromJson(entry.value),
    });
  }

  final Map<String, SalahLessonProgress> lessons;

  Map<String, Object?> toJson() => <String, Object?>{
    'lessons': <String, Object?>{
      for (final entry in lessons.entries) entry.key: entry.value.toJson(),
    },
  };

  SalahLessonStatus statusOf(String lesson) =>
      lessons[lesson]?.status ?? SalahLessonStatus.notStarted;

  int completedCount(SalahCourseDocument document) => document.orderedLessons
      .where((lesson) => statusOf(lesson.slug) == SalahLessonStatus.completed)
      .length;

  /// The step a lesson opens on: the saved step of an unfinished lesson, or
  /// the first step when the lesson is new, finished, or its saved step is
  /// gone from the current content version.
  int resumeStepIndex(SalahLesson lesson) {
    final progress = lessons[lesson.slug];
    if (progress == null || progress.status != SalahLessonStatus.inProgress) {
      return 0;
    }
    final index = lesson.indexOfStep(progress.stepSlug);
    return index < 0 ? 0 : index;
  }

  /// The lesson «Continue» opens: the latest unfinished one, else the first
  /// lesson not yet completed. Null when every lesson is completed.
  SalahLesson? resumeLesson(SalahCourseDocument document) {
    final ordered = document.orderedLessons;
    SalahLesson? latest;
    DateTime? latestAt;
    for (final lesson in ordered) {
      final progress = lessons[lesson.slug];
      if (progress?.status != SalahLessonStatus.inProgress) continue;
      final at = progress!.updatedAt;
      if (latest == null ||
          (at != null && (latestAt == null || at.isAfter(latestAt)))) {
        latest = lesson;
        latestAt = at;
      }
    }
    if (latest != null) return latest;
    for (final lesson in ordered) {
      if (statusOf(lesson.slug) != SalahLessonStatus.completed) return lesson;
    }
    return null;
  }
}

/// Keeps course progress in `app_state` under `salah.progress.<course>`.
class SalahProgressStore {
  SalahProgressStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final DateTime Function() _clock;

  // Writes are read-modify-write; a queue keeps fast page swipes in order.
  Future<void> _queue = Future<void>.value();

  static String stateKey(String course) => 'salah.progress.$course';

  Future<SalahCourseProgress> read(String course) async =>
      SalahCourseProgress.fromJson(await _database.readState(stateKey(course)));

  /// Saves the open step. A completed lesson stays completed.
  Future<SalahCourseProgress> recordStep({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) => _update(course, lesson, (previous) {
    final completed = previous?.status == SalahLessonStatus.completed;
    return SalahLessonProgress(
      status: completed
          ? SalahLessonStatus.completed
          : SalahLessonStatus.inProgress,
      stepSlug: stepSlug,
      contentVersion: contentVersion,
      updatedAt: _clock(),
    );
  });

  Future<SalahCourseProgress> complete({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) => _update(
    course,
    lesson,
    (_) => SalahLessonProgress(
      status: SalahLessonStatus.completed,
      stepSlug: stepSlug,
      contentVersion: contentVersion,
      updatedAt: _clock(),
    ),
  );

  Future<SalahCourseProgress> _update(
    String course,
    String lesson,
    SalahLessonProgress Function(SalahLessonProgress? previous) change,
  ) {
    final result = _queue.then((_) async {
      final current = await read(course);
      final next = SalahCourseProgress(<String, SalahLessonProgress>{
        ...current.lessons,
        lesson: change(current.lessons[lesson]),
      });
      await _database.writeState(stateKey(course), next.toJson());
      return next;
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
