import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/features/courses/course_feedback.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';

import 'course_test_data.dart';

void main() {
  group('event queue', () {
    test('sends batches of at most 50 and drops a failed one', () async {
      final sent = <List<Map<String, Object?>>>[];
      var calls = 0;
      final queue = CourseEventQueue(
        platform: 'android',
        send: (platform, events) async {
          expect(platform, 'android');
          calls++;
          if (calls == 2) {
            throw const ApiException(message: 'busy', statusCode: 429);
          }
          sent.add(events);
        },
      );
      for (var index = 0; index < 120; index++) {
        queue.add('ramadan', 'namerenie', CourseEvent.lessonOpened);
      }

      await queue.flush();

      expect(calls, 3);
      expect(sent.map((batch) => batch.length), [50, 20]);
      expect(sent.first.first, {
        'course': 'ramadan',
        'lesson': 'namerenie',
        'event': 'lesson_opened',
      });
      expect(queue.pending, 0);
      // Nothing is retried.
      await queue.flush();
      expect(calls, 3);
    });

    test('sends once a minute after the first event', () async {
      final sent = <int>[];
      final queue = CourseEventQueue(
        platform: 'ios',
        period: const Duration(milliseconds: 20),
        send: (_, events) async => sent.add(events.length),
      );
      queue
        ..add('ramadan', 'namerenie', CourseEvent.videoStarted)
        ..add('ramadan', 'namerenie', CourseEvent.videoFinished);
      expect(sent, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sent, [2]);
      expect(
        CourseEventQueue(send: (_, _) async {}).period,
        const Duration(minutes: 1),
      );
    });

    test('sends when the app goes to the background', () async {
      final sent = <int>[];
      final queue = CourseEventQueue(
        platform: 'android',
        send: (_, events) async => sent.add(events.length),
      );
      queue.add('ramadan', 'namerenie', CourseEvent.lessonCompleted);
      queue.didChangeAppLifecycleState(AppLifecycleState.inactive);
      queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(sent, isEmpty);

      queue.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(sent, [1]);

      queue.add('ramadan', 'namerenie', CourseEvent.lessonHelpful);
      queue.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await pumpEventQueue();
      expect(sent, [1, 1]);
    });
  });

  group('device store', () {
    test('keeps the first vote of a lesson only', () async {
      final (sql, database) = await openCourseTestDatabase();
      addTearDown(sql.close);
      final store = CourseFeedbackStore(database);

      expect(
        await store.vote(
          course: 'ramadan',
          lesson: 'namerenie',
          vote: LessonVote.notHelpful,
        ),
        isTrue,
      );
      expect(
        await store.vote(
          course: 'ramadan',
          lesson: 'namerenie',
          vote: LessonVote.helpful,
        ),
        isFalse,
      );
      await store.vote(
        course: 'ramadan',
        lesson: 'taraviikh',
        vote: LessonVote.helpful,
      );

      expect(await database.readState('courses.vote.ramadan'), {
        'namerenie': 'not_helpful',
        'taraviikh': 'helpful',
      });
      expect(await store.votes('ramadan'), {
        'namerenie': LessonVote.notHelpful,
        'taraviikh': LessonVote.helpful,
      });
    });

    test('keeps the student\'s own rating in the contract format', () async {
      final (sql, database) = await openCourseTestDatabase();
      addTearDown(sql.close);
      final store = CourseFeedbackStore(
        database,
        clock: () => DateTime.utc(2027, 1, 20, 10),
      );

      expect(await store.rating('ramadan'), isNull);
      await store.saveRating('ramadan', stars: 4, comment: 'Спасибо');

      expect(await database.readState('courses.rating.ramadan'), {
        'stars': 4,
        'comment': 'Спасибо',
        'updated_at': '2027-01-20T10:00:00.000Z',
      });
      expect((await store.rating('ramadan'))?.stars, 4);
      expect(CourseRating.tryParse({'stars': 6, 'updated_at': 'x'}), isNull);
      expect(CourseRating.tryParse({'stars': 3}), isNull);
    });
  });

  test('a report points at the lesson, its release and the video', () {
    final document = CourseDocument.fromJson(courseDocumentJson());
    final lesson = document.lessons[1];

    expect(
      lessonReportSubject(document, lesson),
      '${document.course.title} · 2. ${lesson.title}',
    );
    expect(
      lessonReportContext(
        document,
        lesson,
        playback: const Duration(minutes: 4, seconds: 12),
      ),
      {
        'course_slug': 'ramadan',
        'lesson_slug': lesson.slug,
        'content_version': '1',
        'playback_ms': 252000,
      },
    );
    expect(
      lessonReportContext(document, lesson).containsKey('playback_ms'),
      isFalse,
    );
    expect(
      lessonReportRoute('ramadan', lesson.slug),
      '/courses/ramadan/${lesson.slug}',
    );
    expect(lessonReportCategories, [
      'religious_content',
      'accessibility_localization',
      'technical',
      'other',
    ]);
  });

  test('a shared link opens the page on the site', () {
    expect(
      courseShareUrl('ru', 'ramadan'),
      'https://iqro.forum/ru/courses/ramadan',
    );
    expect(
      courseShareUrl('en', 'ramadan', 'namerenie'),
      'https://iqro.forum/en/courses/ramadan/namerenie',
    );
  });

  test('a long subject is cut to 160 characters', () {
    final json = courseDocumentJson();
    (json['course']! as Map)['title'] = 'К' * 200;
    final document = CourseDocument.fromJson(json);
    final subject = lessonReportSubject(document, document.lessons.first);
    expect(subject.length, 160);
    expect(subject.endsWith('…'), isTrue);
  });
}
