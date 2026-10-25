import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/network/api_client.dart';
import '../../core/share/content_share.dart' show iqroPublicSite;
import '../../core/storage/local_database.dart';
import '../announcements/announcement_repository.dart'
    show announcementPlatform;
import 'course_models.dart';

/// The page of a course, or of one of its lessons, on the public site
/// (docs/courses/README.md, «Поделиться»).
String courseShareUrl(String language, String course, [String? lesson]) =>
    '$iqroPublicSite/$language/courses/$course'
    '${lesson == null ? '' : '/$lesson'}';

/// The anonymous counters of a lesson (docs/courses/README.md, «События
/// статистики»).
abstract final class CourseEvent {
  static const lessonOpened = 'lesson_opened';
  static const videoStarted = 'video_started';
  static const videoFinished = 'video_finished';
  static const lessonCompleted = 'lesson_completed';
  static const lessonHelpful = 'lesson_helpful';
  static const lessonNotHelpful = 'lesson_not_helpful';
}

/// A video counts as watched from this share of its length on.
const courseVideoWatchedShare = .9;

abstract interface class CourseFeedbackGateway {
  /// `POST /courses/events`, without an account or a cookie.
  Future<void> sendEvents(String platform, List<Map<String, Object?>> events);

  /// `PUT /courses/{slug}/rating`, as the installation's account.
  Future<Object?> rate(String course, Map<String, Object?> rating);
}

class ApiCourseFeedbackGateway implements CourseFeedbackGateway {
  ApiCourseFeedbackGateway(this._api);

  final ApiClient _api;

  @override
  Future<void> sendEvents(String platform, List<Map<String, Object?>> events) =>
      _api.post(
        '/courses/events',
        data: <String, Object?>{'platform': platform, 'events': events},
        public: true,
      );

  @override
  Future<Object?> rate(String course, Map<String, Object?> rating) =>
      _api.put('/courses/${Uri.encodeComponent(course)}/rating', data: rating);
}

typedef CourseEventSender =
    Future<void> Function(String platform, List<Map<String, Object?>> events);

/// Collects lesson events and sends them in batches once a minute, when the
/// app goes to the background and when a lesson is closed. Only daily sums
/// reach the server; a batch that fails is dropped, never retried.
class CourseEventQueue with WidgetsBindingObserver {
  CourseEventQueue({
    required CourseEventSender send,
    String? platform,
    this.period = const Duration(minutes: 1),
  }) : _send = send,
       platform = platform ?? announcementPlatform();

  static const maxBatch = 50;

  final CourseEventSender _send;
  final String platform;
  final Duration period;
  final _events = <Map<String, Object?>>[];
  Timer? _timer;

  void add(String course, String lesson, String event) {
    _events.add(<String, Object?>{
      'course': course,
      'lesson': lesson,
      'event': event,
    });
    _timer ??= Timer(period, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    while (_events.isNotEmpty) {
      final batch = _events.take(maxBatch).toList(growable: false);
      _events.removeRange(0, batch.length);
      try {
        await _send(platform, batch);
      } on Object {
        // Counters are best effort and never block the app.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }

  @visibleForTesting
  int get pending => _events.length;
}

/// «Helpful» or «Not really», once per lesson on the device.
enum LessonVote {
  helpful('helpful', CourseEvent.lessonHelpful),
  notHelpful('not_helpful', CourseEvent.lessonNotHelpful);

  const LessonVote(this.value, this.event);

  final String value;
  final String event;

  static LessonVote? parse(Object? value) =>
      values.where((vote) => vote.value == value).firstOrNull;
}

/// The student's own rating of a course; nobody else's is ever shown.
@immutable
class CourseRating {
  const CourseRating({
    required this.stars,
    required this.comment,
    required this.updatedAt,
  });

  static CourseRating? tryParse(Map<String, Object?>? json) {
    if (json case {
      'stars': final int stars,
      'updated_at': final String updatedAt,
    } when stars >= 1 && stars <= 5) {
      final comment = json['comment'];
      return CourseRating(
        stars: stars,
        comment: comment is String ? comment : '',
        updatedAt: updatedAt,
      );
    }
    return null;
  }

  final int stars;
  final String comment;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'stars': stars,
    'comment': comment,
    'updated_at': updatedAt,
  };
}

const maxCourseRatingComment = 1000;
const maxLessonReportMessage = 4000;

/// Votes under `courses.vote.<course>` and the rating under
/// `courses.rating.<course>` in `app_state`.
class CourseFeedbackStore {
  CourseFeedbackStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalDatabase _database;
  final DateTime Function() _clock;

  static String voteKey(String course) => 'courses.vote.$course';

  static String ratingKey(String course) => 'courses.rating.$course';

  Future<Map<String, LessonVote>> votes(String course) async {
    final json = await _database.readState(voteKey(course));
    return <String, LessonVote>{
      for (final MapEntry(:key, :value) in (json ?? const {}).entries)
        if (isCourseSlug(key)) key: ?LessonVote.parse(value),
    };
  }

  /// Keeps the first vote of [lesson]; returns whether this one counted.
  Future<bool> vote({
    required String course,
    required String lesson,
    required LessonVote vote,
  }) async {
    final scope = await _database.captureAccount();
    final json = await _database.readState(
      voteKey(course),
      accountScope: scope,
    );
    if (LessonVote.parse(json?[lesson]) != null) return false;
    await _database.writeState(voteKey(course), <String, Object?>{
      ...?json,
      lesson: vote.value,
    }, accountScope: scope);
    return true;
  }

  Future<CourseRating?> rating(String course) async =>
      CourseRating.tryParse(await _database.readState(ratingKey(course)));

  Future<CourseRating> saveRating(
    String course, {
    required int stars,
    required String comment,
    String? updatedAt,
  }) async {
    final rating = CourseRating(
      stars: stars,
      comment: comment,
      updatedAt: updatedAt ?? _clock().toUtc().toIso8601String(),
    );
    await _database.writeState(ratingKey(course), rating.toJson());
    return rating;
  }
}

/// «Рамадан · 2. Намерение», at most the 160 characters a subject takes.
String lessonReportSubject(CourseDocument document, CourseLesson lesson) {
  final subject =
      '${document.course.title} · ${lesson.number}. ${lesson.title}';
  return subject.length <= 160 ? subject : '${subject.substring(0, 159)}…';
}

/// Where in the course a report points.
Map<String, Object?> lessonReportContext(
  CourseDocument document,
  CourseLesson lesson, {
  Duration? playback,
}) => <String, Object?>{
  'course_slug': document.course.slug,
  'lesson_slug': lesson.slug,
  'content_version': document.course.version,
  'playback_ms': ?playback?.inMilliseconds,
};

String lessonReportRoute(String course, String lesson) =>
    '/courses/$course/$lesson';

/// The report types of a lesson, as existing feedback categories.
const lessonReportCategories = <String>[
  'religious_content',
  'accessibility_localization',
  'technical',
  'other',
];
