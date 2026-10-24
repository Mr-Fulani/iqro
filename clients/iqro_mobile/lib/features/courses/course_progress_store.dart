import 'package:flutter/foundation.dart';

import '../../core/storage/local_database.dart';
import '../tajweed_course/tajweed_course_progress.dart';
import 'course_models.dart';

/// `{"lessons": {"<lesson>": {...}}}`, the JSON of the site's
/// `lib/course-progress.ts`, so syncing with the account can come later as
/// is. A lesson entry is the same as in the tajweed course; topical courses
/// have no steps, so `step_slug` is `""`.
@immutable
class CourseProgress {
  const CourseProgress([this.lessons = const {}]);

  /// Entries that do not fit are dropped.
  factory CourseProgress.fromJson(Map<String, Object?>? json) {
    final lessons = json?['lessons'];
    if (lessons is! Map) return const CourseProgress();
    return CourseProgress({
      for (final MapEntry(:key, :value) in lessons.entries)
        if (key is String && isCourseSlug(key))
          key: ?TajweedLessonProgress.tryParse(value),
    });
  }

  final Map<String, TajweedLessonProgress> lessons;

  /// No lesson of the course was opened.
  bool get isEmpty => lessons.isEmpty;

  /// «Studied» was pressed.
  bool isDone(String lesson) => lessons[lesson]?.completed ?? false;

  /// Lessons gone from a new version are not counted.
  int doneCount(CourseDocument document) =>
      document.lessons.where((lesson) => isDone(lesson.slug)).length;

  /// The first lesson not studied, or null when all are.
  CourseLesson? resumeLesson(CourseDocument document) =>
      document.lessons.where((lesson) => !isDone(lesson.slug)).firstOrNull;

  /// When a lesson of the course was last opened or marked; empty without.
  String get lastUpdatedAt => lessons.values.fold(
    '',
    (latest, lesson) =>
        lesson.updatedAt.compareTo(latest) > 0 ? lesson.updatedAt : latest,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lessons': <String, Object?>{
      for (final MapEntry(:key, :value) in lessons.entries) key: value.toJson(),
    },
  };
}

/// Keeps course progress in `app_state` under `courses.progress.<course>`.
class CourseProgressStore {
  CourseProgressStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final DateTime Function() _clock;

  // Writes are read-modify-write; a queue keeps fast taps in order.
  Future<void> _queue = Future<void>.value();

  static String stateKey(String course) => 'courses.progress.$course';

  Future<CourseProgress> read(String course) async =>
      CourseProgress.fromJson(await _database.readState(stateKey(course)));

  /// The lesson was opened. A studied lesson stays studied.
  Future<CourseProgress> recordOpen({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _update(
    course,
    lesson,
    contentVersion,
    (previous) => previous?.completed ?? false,
  );

  Future<CourseProgress> markDone({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _update(course, lesson, contentVersion, (_) => true);

  /// Takes «Studied» back; the lesson stays opened.
  Future<CourseProgress> unmark({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _update(course, lesson, contentVersion, (_) => false);

  Future<CourseProgress> _update(
    String course,
    String lesson,
    String contentVersion,
    bool Function(TajweedLessonProgress? previous) completed,
  ) {
    final result = _queue.then((_) async {
      final scope = await _database.captureAccount();
      final current = CourseProgress.fromJson(
        await _database.readState(stateKey(course), accountScope: scope),
      );
      final next = CourseProgress({
        ...current.lessons,
        lesson: TajweedLessonProgress(
          status: completed(current.lessons[lesson])
              ? TajweedLessonStatus.completed
              : TajweedLessonStatus.inProgress,
          stepSlug: '',
          contentVersion: contentVersion,
          updatedAt: tajweedProgressTime(_clock()),
        ),
      });
      await _database.writeState(
        stateKey(course),
        next.toJson(),
        accountScope: scope,
      );
      return next;
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
