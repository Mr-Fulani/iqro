// Tajweed practice (docs/tajweed/practice.md): the tasks the API builds from
// the markup of the whole Quran, and the score, day streak and review list
// kept locally and recomputed by the backend from the same sessions.

import 'package:flutter/foundation.dart';

import 'tajweed_course_models.dart';
import 'tajweed_course_progress.dart' show tajweedProgressTime;

/// Tasks of one session.
const tajweedPracticeTasks = 8;

/// Tasks due for review a session asks for.
const tajweedPracticeReview = 4;

/// Unsent sessions kept; older ones are dropped.
const tajweedPracticePending = 50;

/// Days until a task in a box is asked again after a right answer.
const _reviewDays = <int, int>{2: 1, 3: 3};
const _lastBox = 3;

enum TajweedPracticeTaskType {
  find,
  identify,
  listen;

  static TajweedPracticeTaskType? tryParse(Object? value) =>
      values.where((type) => type.name == value).firstOrNull;
}

/// `{type}~{verse_key}~{target}`.
String tajweedPracticeKey(
  TajweedPracticeTaskType type,
  String verseKey,
  String target,
) => '${type.name}~$verseKey~$target';

/// `YYYY-MM-DD` of [moment] in the device's own time zone.
String tajweedLocalDate(DateTime moment) {
  final local = moment.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-${pad(local.month)}-'
      '${pad(local.day)}';
}

String _nextDay(String day) => DateTime.parse(
  '${day}T00:00:00Z',
).add(const Duration(days: 1)).toIso8601String().substring(0, 10);

/// One task of a session from the API.
@immutable
class TajweedPracticeTask {
  const TajweedPracticeTask({
    required this.key,
    required this.type,
    required this.target,
    required this.example,
    this.review = false,
    this.focus = 0,
    this.options = const [],
  });

  final String key;
  final TajweedPracticeTaskType type;
  final String target;
  final bool review;

  /// All words and every place of [target], as in a lesson's examples.
  final TajweedCourseExample example;

  /// The place «identify» and «listen» ask about; 0 for «find».
  final int focus;

  /// The right target and others, shuffled; empty for «find».
  final List<String> options;

  TajweedOccurrence get focusOccurrence => example.occurrences[focus];
}

/// The tasks of an API answer; tasks that do not fit are dropped.
List<TajweedPracticeTask> parseTajweedPracticeTasks(Object? value) {
  final tasks = value is Map ? value['tasks'] : null;
  if (tasks is! List) return const [];
  return [
    for (final item in tasks)
      if (item is Map) ?_task(item),
  ];
}

TajweedPracticeTask? _task(Map<Object?, Object?> item) {
  final key = item['key'];
  final type = TajweedPracticeTaskType.tryParse(item['type']);
  final target = item['target'];
  if (key is! String || type == null || target is! String) return null;
  final example = TajweedCourseExample.tryParse(item['example']);
  final focus = item['focus'] is int ? item['focus']! as int : 0;
  if (example == null || focus < 0 || focus >= example.occurrences.length) {
    return null;
  }
  final rawOptions = item['options'];
  final options = <String>[
    if (rawOptions is List)
      for (final option in rawOptions)
        if (option is String) option,
  ];
  if (type != TajweedPracticeTaskType.find && !options.contains(target)) {
    return null;
  }
  return TajweedPracticeTask(
    key: key,
    type: type,
    target: target,
    review: item['review'] == true,
    example: example,
    focus: focus,
    options: options,
  );
}

/// The first answer to a task.
@immutable
class TajweedPracticeAnswer {
  const TajweedPracticeAnswer({
    required this.key,
    required this.target,
    required this.type,
    required this.correct,
    required this.at,
  });

  static TajweedPracticeAnswer? tryParse(Object? value) {
    if (value is! Map) return null;
    final key = value['key'];
    final target = value['target'];
    final type = TajweedPracticeTaskType.tryParse(value['type']);
    final correct = value['correct'];
    final at = value['at'];
    if (key is! String ||
        target is! String ||
        type == null ||
        correct is! bool ||
        at is! String ||
        DateTime.tryParse(at) == null) {
      return null;
    }
    return TajweedPracticeAnswer(
      key: key,
      target: target,
      type: type,
      correct: correct,
      at: at,
    );
  }

  final String key;
  final String target;
  final TajweedPracticeTaskType type;
  final bool correct;

  /// ISO time of the answer.
  final String at;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'target': target,
    'type': type.name,
    'correct': correct,
    'at': at,
  };
}

/// A finished session, the body of `POST /me/tajweed/practice-sessions`.
@immutable
class TajweedPracticeSession {
  const TajweedPracticeSession({
    required this.id,
    required this.course,
    required this.localDate,
    required this.finishedAt,
    required this.answers,
  });

  /// The session, or null when it does not fit (it is dropped then).
  static TajweedPracticeSession? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final course = value['course'];
    final localDate = value['local_date'];
    final finishedAt = value['finished_at'];
    final rawAnswers = value['answers'];
    if (id is! String ||
        course is! String ||
        localDate is! String ||
        finishedAt is! String ||
        rawAnswers is! List) {
      return null;
    }
    final answers = <TajweedPracticeAnswer>[];
    for (final item in rawAnswers) {
      final answer = TajweedPracticeAnswer.tryParse(item);
      if (answer == null) return null;
      answers.add(answer);
    }
    return TajweedPracticeSession(
      id: id,
      course: course,
      localDate: localDate,
      finishedAt: finishedAt,
      answers: answers,
    );
  }

  final String id;
  final String course;

  /// `YYYY-MM-DD` on the device when the session finished.
  final String localDate;
  final String finishedAt;
  final List<TajweedPracticeAnswer> answers;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'course': course,
    'local_date': localDate,
    'finished_at': finishedAt,
    'answers': [for (final answer in answers) answer.toJson()],
  };
}

/// A task waiting in a Leitner box.
@immutable
class TajweedReviewItem {
  const TajweedReviewItem({
    required this.key,
    required this.target,
    required this.type,
    required this.box,
    required this.dueAt,
  });

  static TajweedReviewItem? tryParse(Object? value) {
    if (value is! Map) return null;
    final key = value['key'];
    final target = value['target'];
    final type = TajweedPracticeTaskType.tryParse(value['type']);
    final box = value['box'];
    final dueAt = value['due_at'];
    if (key is! String ||
        target is! String ||
        type == null ||
        box is! int ||
        dueAt is! String) {
      return null;
    }
    return TajweedReviewItem(
      key: key,
      target: target,
      type: type,
      box: box,
      dueAt: dueAt,
    );
  }

  final String key;
  final String target;
  final TajweedPracticeTaskType type;
  final int box;

  /// ISO time, compared as text like on the site and the backend.
  final String dueAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'target': target,
    'type': type.name,
    'box': box,
    'due_at': dueAt,
  };
}

/// Score, day streak and review list, the same JSON as on the site and in
/// the API (without `course`).
@immutable
class TajweedPracticeState {
  const TajweedPracticeState({
    this.sessions = 0,
    this.answers = 0,
    this.correct = 0,
    this.score = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.lastDate,
    this.review = const [],
  });

  /// The state, or null when it does not fit.
  static TajweedPracticeState? tryParse(Object? value) {
    if (value is! Map) return null;
    final streak = value['streak'];
    final review = value['review'];
    final numbers = [
      for (final name in ['sessions', 'answers', 'correct', 'score'])
        value[name],
    ];
    if (streak is! Map || review is! List || numbers.any((n) => n is! int)) {
      return null;
    }
    int count(Object? value) => value is int ? value : 0;
    return TajweedPracticeState(
      sessions: numbers[0]! as int,
      answers: numbers[1]! as int,
      correct: numbers[2]! as int,
      score: numbers[3]! as int,
      streak: count(streak['current']),
      bestStreak: count(streak['best']),
      lastDate: streak['last_date'] is String
          ? streak['last_date']! as String
          : null,
      review: [for (final item in review) ?TajweedReviewItem.tryParse(item)],
    );
  }

  final int sessions;
  final int answers;
  final int correct;
  final int score;

  /// Days in a row up to [lastDate].
  final int streak;
  final int bestStreak;
  final String? lastDate;

  /// Sorted by due time, then key.
  final List<TajweedReviewItem> review;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessions': sessions,
    'answers': answers,
    'correct': correct,
    'score': score,
    'streak': <String, Object?>{
      'current': streak,
      'best': bestStreak,
      'last_date': lastDate,
    },
    'review': [for (final item in review) item.toJson()],
  };

  /// The state after one more session; the backend's `apply_session` and
  /// the site's `applyPracticeSession`, step for step.
  TajweedPracticeState apply(TajweedPracticeSession session) {
    var current = streak;
    var best = bestStreak;
    var last = lastDate;
    final day = session.localDate;
    if (last == null || day.compareTo(last) > 0) {
      current = last != null && day == _nextDay(last) ? current + 1 : 1;
      if (current > best) best = current;
      last = day;
    }
    final boxes = <String, TajweedReviewItem>{
      for (final item in review) item.key: item,
    };
    var answered = answers;
    var right = correct;
    for (final answer in session.answers) {
      answered += 1;
      final at = DateTime.parse(answer.at);
      if (!answer.correct) {
        boxes[answer.key] = TajweedReviewItem(
          key: answer.key,
          target: answer.target,
          type: answer.type,
          box: 1,
          dueAt: tajweedProgressTime(at),
        );
        continue;
      }
      right += 1;
      final item = boxes[answer.key];
      if (item == null) continue;
      if (item.box >= _lastBox) {
        boxes.remove(answer.key);
        continue;
      }
      final box = item.box + 1;
      boxes[answer.key] = TajweedReviewItem(
        key: item.key,
        target: item.target,
        type: item.type,
        box: box,
        dueAt: tajweedProgressTime(at.add(Duration(days: _reviewDays[box]!))),
      );
    }
    return TajweedPracticeState(
      sessions: sessions + 1,
      answers: answered,
      correct: right,
      score: right,
      streak: current,
      bestStreak: best,
      lastDate: last,
      review: boxes.values.toList()
        ..sort(
          (left, right) => left.dueAt == right.dueAt
              ? left.key.compareTo(right.key)
              : left.dueAt.compareTo(right.dueAt),
        ),
    );
  }

  /// The streak to show: broken when the last practice was before
  /// yesterday.
  int shownStreak(String today) {
    final last = lastDate;
    return last != null && (last == today || _nextDay(last) == today)
        ? streak
        : 0;
  }

  /// Keys of the tasks due for review at [now], oldest first.
  List<String> dueReviewKeys(
    DateTime now, {
    int? limit = tajweedPracticeReview,
  }) {
    final moment = tajweedProgressTime(now);
    final due = [
      for (final item in review)
        if (item.dueAt.compareTo(moment) <= 0) item.key,
    ];
    return limit == null || due.length <= limit ? due : due.sublist(0, limit);
  }
}

/// The local copy: the state with every session counted, and the sessions
/// the account has not taken yet.
@immutable
class TajweedPracticeLocal {
  const TajweedPracticeLocal({
    this.state = const TajweedPracticeState(),
    this.pending = const [],
  });

  /// `{"state": {...}, "pending": [...]}`; what does not fit is dropped.
  factory TajweedPracticeLocal.fromJson(Map<String, Object?>? json) {
    final pending = json?['pending'];
    return TajweedPracticeLocal(
      state:
          TajweedPracticeState.tryParse(json?['state']) ??
          const TajweedPracticeState(),
      pending: [
        if (pending is List)
          for (final item in pending) ?TajweedPracticeSession.tryParse(item),
      ],
    );
  }

  final TajweedPracticeState state;
  final List<TajweedPracticeSession> pending;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.toJson(),
    'pending': [for (final session in pending) session.toJson()],
  };

  /// A finished session counts at once and waits until the account takes
  /// it.
  TajweedPracticeLocal record(TajweedPracticeSession session) {
    final waiting = [...pending, session];
    return TajweedPracticeLocal(
      state: state.apply(session),
      pending: waiting.length > tajweedPracticePending
          ? waiting.sublist(waiting.length - tajweedPracticePending)
          : waiting,
    );
  }
}
