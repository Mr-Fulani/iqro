import 'package:flutter/foundation.dart';

import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_session.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import 'tajweed_course_models.dart';
import 'tajweed_course_repository.dart';

enum TajweedLessonStatus { notStarted, inProgress, completed }

/// The `toISOString()` form the site and the backend keep: UTC with
/// milliseconds, so later records also sort later as text.
String tajweedProgressTime(DateTime moment) =>
    DateTime.fromMillisecondsSinceEpoch(
      moment.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();

/// Progress of one lesson, the same JSON as on the site and in the API.
@immutable
class TajweedLessonProgress {
  const TajweedLessonProgress({
    required this.status,
    required this.stepSlug,
    required this.contentVersion,
    required this.updatedAt,
  });

  /// The entry, or null when it does not fit (it is dropped then).
  static TajweedLessonProgress? tryParse(Object? value) {
    if (value is! Map) return null;
    final status = switch (value['status']) {
      'in_progress' => TajweedLessonStatus.inProgress,
      'completed' => TajweedLessonStatus.completed,
      _ => null,
    };
    final step = value['step_slug'];
    final version = value['content_version'];
    if (status == null || step is! String || version is! String) return null;
    final updatedAt = value['updated_at'];
    return TajweedLessonProgress(
      status: status,
      stepSlug: step,
      contentVersion: version,
      updatedAt: updatedAt is String ? updatedAt : '',
    );
  }

  /// [TajweedLessonStatus.inProgress] or [TajweedLessonStatus.completed].
  final TajweedLessonStatus status;
  final String stepSlug;
  final String contentVersion;

  /// ISO time as stored; compared as text, like the site and the backend.
  final String updatedAt;

  bool get completed => status == TajweedLessonStatus.completed;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': completed ? 'completed' : 'in_progress',
    'step_slug': stepSlug,
    'content_version': contentVersion,
    'updated_at': updatedAt,
  };

  TajweedLessonProgress copyWith({TajweedLessonStatus? status}) =>
      TajweedLessonProgress(
        status: status ?? this.status,
        stepSlug: stepSlug,
        contentVersion: contentVersion,
        updatedAt: updatedAt,
      );
}

@immutable
class TajweedCourseProgress {
  const TajweedCourseProgress([this.lessons = const {}]);

  /// `{"lessons": {...}}`; entries that do not fit are dropped.
  factory TajweedCourseProgress.fromJson(Map<String, Object?>? json) {
    final lessons = json?['lessons'];
    if (lessons is! Map) return const TajweedCourseProgress();
    return TajweedCourseProgress({
      for (final MapEntry(:key, :value) in lessons.entries)
        if (key is String && isTajweedLessonSlug(key))
          key: ?TajweedLessonProgress.tryParse(value),
    });
  }

  final Map<String, TajweedLessonProgress> lessons;

  Map<String, Object?> toJson() => <String, Object?>{
    'lessons': <String, Object?>{
      for (final MapEntry(:key, :value) in lessons.entries) key: value.toJson(),
    },
  };

  TajweedLessonStatus statusOf(String lesson) =>
      lessons[lesson]?.status ?? TajweedLessonStatus.notStarted;

  int completedCount(TajweedCourseDocument document) => document.orderedLessons
      .where((lesson) => statusOf(lesson.slug) == TajweedLessonStatus.completed)
      .length;

  /// The lesson «Continue» opens: the latest unfinished one, else the first
  /// lesson not started. Null when every lesson is completed.
  TajweedCourseLesson? resumeLesson(TajweedCourseDocument document) {
    final ordered = document.orderedLessons;
    TajweedCourseLesson? latest;
    for (final lesson in ordered) {
      final progress = lessons[lesson.slug];
      if (progress?.status != TajweedLessonStatus.inProgress) continue;
      if (latest == null ||
          progress!.updatedAt.compareTo(lessons[latest.slug]!.updatedAt) > 0) {
        latest = lesson;
      }
    }
    return latest ??
        ordered
            .where((lesson) => !lessons.containsKey(lesson.slug))
            .firstOrNull;
  }

  /// Where [lesson] opens, by preference: a step from a link, then the saved
  /// step of an unfinished lesson. Empty opens the lesson from the start; a
  /// step the lesson no longer has starts it over too.
  List<String> resumeSteps(String lesson, String? linkedStep) => [
    if (linkedStep != null && isTajweedStepSlug(linkedStep)) linkedStep,
    if (lessons[lesson] case final saved?
        when !saved.completed && isTajweedStepSlug(saved.stepSlug))
      saved.stepSlug,
  ];

  /// Two copies as one, as the backend merges them: a passed lesson stays
  /// passed, otherwise the later record wins. The order does not matter.
  TajweedCourseProgress merge(TajweedCourseProgress other) {
    final merged = {...lessons};
    for (final MapEntry(:key, :value) in other.lessons.entries) {
      final current = merged[key];
      if (current == null) {
        merged[key] = value;
        continue;
      }
      final later = value.updatedAt.compareTo(current.updatedAt) > 0
          ? value
          : current;
      merged[key] = current.completed || value.completed
          ? later.copyWith(status: TajweedLessonStatus.completed)
          : later;
    }
    return TajweedCourseProgress(merged);
  }
}

/// Keeps course progress in `app_state` under `tajweed.progress.<course>`.
class TajweedCourseProgressStore {
  TajweedCourseProgressStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final DateTime Function() _clock;

  // Writes are read-modify-write; a queue keeps fast page swipes and a sync
  // answer in order.
  Future<void> _queue = Future<void>.value();

  static String stateKey(String course) => 'tajweed.progress.$course';

  Future<TajweedCourseProgress> read(
    String course, {
    AccountScopeSnapshot? accountScope,
  }) async => TajweedCourseProgress.fromJson(
    await _database.readState(stateKey(course), accountScope: accountScope),
  );

  /// Saves the open step. A completed lesson stays completed.
  Future<TajweedCourseProgress> recordStep({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) => _update(course, (current) {
    final completed = current.lessons[lesson]?.completed ?? false;
    return _with(current, lesson, stepSlug, contentVersion, completed);
  });

  Future<TajweedCourseProgress> complete({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) => _update(
    course,
    (current) => _with(current, lesson, stepSlug, contentVersion, true),
  );

  /// Merges a copy from the server into the local one as it is now: steps
  /// saved while the request was on its way are kept.
  Future<TajweedCourseProgress> merge(
    String course,
    TajweedCourseProgress remote, {
    AccountScopeSnapshot? accountScope,
  }) => _update(
    course,
    (current) => current.merge(remote),
    accountScope: accountScope,
  );

  TajweedCourseProgress _with(
    TajweedCourseProgress current,
    String lesson,
    String stepSlug,
    String contentVersion,
    bool completed,
  ) => TajweedCourseProgress({
    ...current.lessons,
    lesson: TajweedLessonProgress(
      status: completed
          ? TajweedLessonStatus.completed
          : TajweedLessonStatus.inProgress,
      stepSlug: stepSlug,
      contentVersion: contentVersion,
      updatedAt: tajweedProgressTime(_clock()),
    ),
  });

  Future<TajweedCourseProgress> _update(
    String course,
    TajweedCourseProgress Function(TajweedCourseProgress current) change, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = _queue.then((_) async {
      final scope = accountScope ?? await _database.captureAccount();
      final next = change(await read(course, accountScope: scope));
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

/// Sends the local progress to the account and keeps the merged answer.
///
/// Only with a session (a guest has one too) that is not pending deletion.
/// Failures are silent: without a network the progress stays local until
/// the next time.
class TajweedProgressSync {
  TajweedProgressSync({
    required TajweedCourseRemoteGateway remote,
    required TajweedCourseProgressStore store,
    required LocalDatabase database,
    required AuthSession? Function() session,
    void Function(String course)? onMerged,
  }) : _remote = remote,
       _store = store,
       _database = database,
       _session = session,
       _onMerged = onMerged;

  final TajweedCourseRemoteGateway _remote;
  final TajweedCourseProgressStore _store;
  final LocalDatabase _database;
  final AuthSession? Function() _session;

  /// Lets the screens that show the progress read it again.
  final void Function(String course)? _onMerged;

  /// The merged progress, or null when nothing was synchronized.
  Future<TajweedCourseProgress?> sync(String course) async {
    final session = _session();
    if (session == null || session.isPendingDeletion) return null;
    try {
      final scope = await _database.captureAccount();
      if (scope.userId != session.userId) return null;
      final local = await _store.read(course, accountScope: scope);
      final answer = await _remote.saveProgress(course, <String, Object?>{
        'lessons': <String, Object?>{
          // The server refuses a record without its time.
          for (final MapEntry(:key, :value) in local.lessons.entries)
            if (value.updatedAt.isNotEmpty) key: value.toJson(),
        },
      }, accountScope: scope);
      final remote = TajweedCourseProgress.fromJson(jsonMap(answer));
      final merged = await _store.merge(course, remote, accountScope: scope);
      _onMerged?.call(course);
      return merged;
    } on Object {
      return null;
    }
  }
}
