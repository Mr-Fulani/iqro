import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/courses/course_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'course_test_data.dart';

void main() {
  group('models', () {
    test('read the list and the document of the shared examples', () {
      final courses = parseCourseList(courseListJson());
      final ramadan = courses.single;
      expect(ramadan.slug, 'ramadan');
      expect(ramadan.version, '1');
      expect(ramadan.lessonCount, 3);
      expect(ramadan.minutes, 30);
      expect(ramadan.cover!.cardUrl, endsWith('-640.webp'));

      final document = CourseDocument.fromJson(courseDocumentJson());
      expect(document.course.title, 'Рамадан');
      expect(document.course.languages, ['ru']);
      expect(document.lessons.map((lesson) => lesson.slug), [
        'smysl-posta',
        'namerenie',
        'taraviikh',
      ]);
      expect(document.next('namerenie')?.slug, 'taraviikh');
      expect(document.previous('smysl-posta'), isNull);
      final first = document.lessons.first;
      expect(first.notes.map((block) => block.runtimeType), [
        NoteHeading,
        NoteParagraph,
        NoteQuote,
        NoteQuote,
      ]);
      final quote = first.notes[2] as NoteQuote;
      expect(quote.direction, TextDirection.rtl);
      expect(quote.source, 'Коран, 2:183');
      expect(quote.lines.single.single.arabic, isTrue);
      final paragraph = first.notes[1] as NoteParagraph;
      expect(paragraph.lines.single.map((segment) => segment.bold), [
        false,
        false,
        false,
        true,
        false,
      ]);
      expect(document.lessons.last.sources, isEmpty);

      // Media above the notes, in the author's order.
      final banner = first.media.single as LessonBannerMedia;
      expect(banner.picture.image.url, endsWith('/2222222222bbbbbbbbbb.webp'));
      expect(banner.picture.image.smallUrl, endsWith('bbbbbbbbbb-800.webp'));
      expect(banner.picture.image.width, 1600);
      expect(banner.picture.image.height, 900);
      expect(banner.picture.caption, '');
      expect(banner.picture.alt, 'Полумесяц над минаретом на закате');
      expect(banner.picture.direction, TextDirection.ltr);
      final media = document.lesson('namerenie')!.media;
      expect(media.map((block) => block.runtimeType), [
        LessonVideoMedia,
        LessonSlidesMedia,
      ]);
      expect(
        (media.first as LessonVideoMedia).video.url,
        document.lesson('namerenie')!.video!.url,
      );
      final slides = (media.last as LessonSlidesMedia).slides;
      expect(slides.map((slide) => slide.image.height), [1200, 900]);
      expect(slides.last.caption, 'نويت صوم غد');
      expect(slides.last.direction, TextDirection.rtl);
      expect(document.lessons.last.media, isEmpty);
    });

    test('media: a document without it has its video; unknown blocks are '
        'left out', () {
      final json = courseDocumentJson();
      final lessons = (json['lessons']! as List).cast<Map>();
      for (final lesson in lessons) {
        lesson.remove('media');
      }
      var document = CourseDocument.fromJson(json);
      expect(document.lessons.first.media, isEmpty);
      final video = document.lesson('namerenie')!.media.single;
      expect((video as LessonVideoMedia).video.url, endsWith('abcd.mp4'));

      lessons.first['media'] = [
        {'type': 'quiz', 'quiz': 'ramadan-basics'},
        {'type': 'slides', 'slides': <Object?>[]},
        {
          'type': 'banner',
          'image': {
            'url': 'https://media.iqro.forum/courses/banners/b.webp',
            'small_url': 'https://media.iqro.forum/courses/banners/b-800.webp',
            'width': 1600,
            'height': 900,
          },
          'caption': 'Подпись',
          'alt': '',
          'dir': 'ltr',
          'added_later': true,
        },
      ];
      document = CourseDocument.fromJson(json);
      final banner = document.lessons.first.media.single as LessonBannerMedia;
      expect(banner.picture.caption, 'Подпись');
      expect(banner.picture.alt, '');
    });

    test('ignore unknown fields', () {
      final json = courseDocumentJson()..['added_later'] = {'any': 1};
      final lesson = (json['lessons']! as List).first as Map;
      lesson['video'] = null;
      lesson['quiz'] = 'ramadan-basics';
      ((lesson['notes']! as List).first as Map)['anchor'] = 'start';
      expect(CourseDocument.fromJson(json).lessons, hasLength(3));
      final list = courseListJson();
      ((list['courses']! as List).single as Map)['badge'] = 'new';
      expect(parseCourseList(list), hasLength(1));
    });

    test('a newer schema asks for an update', () {
      final json = courseDocumentJson()..['schema_version'] = 2;
      // Even with blocks this app does not know.
      ((json['lessons']! as List).first as Map)['notes'] = [
        {'type': 'video_chapter', 'dir': 'ltr'},
      ];
      expect(
        () => CourseDocument.fromJson(json),
        throwsA(
          isA<CourseNeedsUpdate>().having(
            (error) => error.schemaVersion,
            'schemaVersion',
            2,
          ),
        ),
      );
    });

    test('reject documents that do not fit', () {
      Map<String, Object?> changed(void Function(Map<String, Object?>) edit) {
        final json = courseDocumentJson();
        edit(json);
        return json;
      }

      Map<Object?, Object?> firstLesson(Map<String, Object?> json) =>
          (json['lessons']! as List).first as Map;
      Map<Object?, Object?> firstBlock(Map<String, Object?> json) =>
          (firstLesson(json)['notes']! as List).first as Map;
      Map<Object?, Object?> banner(Map<String, Object?> json) =>
          (firstLesson(json)['media']! as List).first as Map;

      for (final json in [
        changed((json) => json.remove('schema_version')),
        changed((json) => json['schema_version'] = 0),
        changed((json) => (json['course']! as Map).remove('version')),
        changed((json) => (json['course']! as Map)['slug'] = '../x'),
        changed((json) => firstLesson(json)['number'] = 0),
        changed((json) => firstLesson(json).remove('sources')),
        changed((json) => firstLesson(json)['slug'] = 'namerenie'),
        changed((json) => firstBlock(json)['type'] = 'table'),
        changed((json) => firstBlock(json)['dir'] = 'auto'),
        changed((json) => firstLesson(json)['media'] = {'type': 'banner'}),
        changed((json) => banner(json)['dir'] = 'auto'),
        changed((json) => banner(json).remove('alt')),
        changed((json) => (banner(json)['image']! as Map).remove('small_url')),
        changed(
          (json) => firstLesson(json)['media'] = [
            {'type': 'video', 'video': null},
          ],
        ),
        changed(
          (json) => firstLesson(json)['media'] = [
            {
              'type': 'slides',
              'slides': [
                {'image': null, 'caption': '', 'alt': '', 'dir': 'ltr'},
              ],
            },
          ],
        ),
        changed(
          (json) => firstBlock(json)['text'] = [
            {'text': 'x', 'bold': 'yes'},
          ],
        ),
        changed(
          (json) => firstBlock(json)['text'] = [
            {'text': 'x', 'lang': 'fa'},
          ],
        ),
      ]) {
        expect(() => CourseDocument.fromJson(json), throwsFormatException);
      }
      expect(
        () => parseCourseList({
          'courses': [
            {'slug': 'ramadan'},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('repository', () {
    late Database sql;
    late LocalDatabase database;
    late FakeCourseGateway remote;
    late CourseRepository repository;

    setUp(() async {
      (sql, database) = await openCourseTestDatabase();
      remote = FakeCourseGateway();
      repository = CourseRepository(remote: remote, database: database);
    });

    tearDown(() => sql.close());

    Future<CourseDocument> open(String language) async {
      final catalog = await repository.catalog(language);
      return repository.document(catalog.course('ramadan')!, language);
    }

    test('keeps the document under its version and reuses it', () async {
      final document = await open('ru');
      expect(document.course.version, '1');
      final stored = await database.readCache(
        CourseRepository.documentCacheKey('ramadan', 'ru', '1'),
      );
      expect(stored?.value, courseDocumentJson());
      expect(
        CourseRepository.documentCacheKey('ramadan', 'ru', '1'),
        'courses.document.ramadan.ru.1',
      );

      await open('ru');
      expect(remote.listRequests, ['ru', 'ru']);
      expect(remote.documentRequests, ['ramadan.ru']);
    });

    test('keeps the pictures of the lessons with the document', () async {
      final kept = <List<LessonMedia>>[];
      repository = CourseRepository(
        remote: remote,
        database: database,
        keepMedia: (media) async => kept.add(media.toList()),
      );
      await open('ru');
      await pumpEventQueue();
      expect(kept.single.map((block) => block.runtimeType), [
        LessonBannerMedia,
        LessonVideoMedia,
        LessonSlidesMedia,
      ]);

      // Opened again from the device: what did not arrive is fetched now.
      await open('ru');
      await pumpEventQueue();
      expect(kept, hasLength(2));
      expect(remote.documentRequests, ['ramadan.ru']);
    });

    test('pictures that cannot be kept do not fail the course', () async {
      for (final keep in <Future<void> Function(Iterable<LessonMedia>)>[
        (_) => throw Exception('no disk'),
        (_) async => throw Exception('offline'),
      ]) {
        repository = CourseRepository(
          remote: remote,
          database: database,
          keepMedia: keep,
        );
        final document = await open('ru');
        await pumpEventQueue();
        expect(document.lessons, hasLength(3));
      }
    });

    test('a new version in the list means a new document', () async {
      await open('ru');
      remote
        ..list = courseListVersion('2')
        ..documents = {'2': courseDocumentVersion('2')};
      final document = await open('ru');
      expect(document.course.version, '2');
      expect(remote.documentRequests, ['ramadan.ru', 'ramadan.ru']);
      expect(
        await database.readCache(
          CourseRepository.documentCacheKey('ramadan', 'ru', '2'),
        ),
        isNotNull,
      );
    });

    test('offline lists only the courses kept on the device', () async {
      await repository.catalog('ru');
      remote.list = offlineError;
      var catalog = await repository.catalog('ru');
      expect(catalog.offline, isTrue);
      // The list is known, but the course was never opened.
      expect(catalog.courses, isEmpty);

      remote.list = courseListJson();
      await open('ru');
      remote
        ..list = offlineError
        ..documentError = offlineError;
      catalog = await repository.catalog('ru');
      expect(catalog.offline, isTrue);
      expect(catalog.courses.single.slug, 'ramadan');
      final document = await repository.document(catalog.courses.single, 'ru');
      expect(document.lessons, hasLength(3));
    });

    test('offline keeps the stored version after a newer list', () async {
      await open('ru');
      remote.list = courseListVersion('2');
      await repository.catalog('ru');
      remote
        ..list = offlineError
        ..documentError = offlineError;
      final catalog = await repository.catalog('ru');
      expect(catalog.courses.single.version, '1');
      final document = await repository.document(catalog.courses.single, 'ru');
      expect(document.course.version, '1');
    });

    test('a course gone from the list is hidden, offline too', () async {
      await open('ru');
      remote.list = {'language': 'ru', 'courses': <Object?>[]};
      expect((await repository.catalog('ru')).courses, isEmpty);
      remote.list = offlineError;
      expect((await repository.catalog('ru')).courses, isEmpty);
    });

    test('after a rollback the older stored version is current', () async {
      await open('ru');
      remote
        ..list = courseListVersion('2')
        ..documents = {'2': courseDocumentVersion('2')};
      await open('ru');
      remote.list = courseListJson();
      expect((await open('ru')).course.version, '1');
      remote.list = offlineError;
      expect((await repository.catalog('ru')).courses.single.version, '1');
    });

    test('a server without the section shows no courses', () async {
      remote.list = notFoundError;
      final catalog = await repository.catalog('ru');
      expect(catalog.offline, isFalse);
      expect(catalog.courses, isEmpty);
    });

    test('a missing document is an unavailable course', () async {
      final course = (await repository.catalog('ru')).courses.single;
      remote.documents = {};
      await expectLater(
        repository.document(course, 'ru'),
        throwsA(isA<CourseUnavailable>()),
      );
    });

    test('a newer schema is not stored', () async {
      final course = (await repository.catalog('ru')).courses.single;
      remote.documents = {'1': courseDocumentJson()..['schema_version'] = 2};
      await expectLater(
        repository.document(course, 'ru'),
        throwsA(isA<CourseNeedsUpdate>()),
      );
      expect(
        await database.readCache(
          CourseRepository.documentCacheKey('ramadan', 'ru', '1'),
        ),
        isNull,
      );
    });

    test('server and format errors are not taken for offline', () async {
      remote.list = const ApiException(message: 'Bad', statusCode: 400);
      await expectLater(repository.catalog('ru'), throwsA(isA<ApiException>()));
      remote.list = {'courses': 'none'};
      await expectLater(repository.catalog('ru'), throwsFormatException);
    });
  });

  group('progress', () {
    late Database sql;
    late LocalDatabase database;
    late CourseProgressStore store;
    var now = DateTime.utc(2026, 10, 24, 9, 30, 0, 123, 456);

    setUp(() async {
      (sql, database) = await openCourseTestDatabase();
      store = CourseProgressStore(database, clock: () => now);
    });

    tearDown(() => sql.close());

    test('stores the site format under courses.progress.<slug>', () async {
      await store.recordOpen(
        course: 'ramadan',
        lesson: 'namerenie',
        contentVersion: '1',
      );
      expect(await database.readState('courses.progress.ramadan'), {
        'lessons': {
          'namerenie': {
            'status': 'in_progress',
            'step_slug': '',
            'content_version': '1',
            'updated_at': '2026-10-24T09:30:00.123Z',
          },
        },
      });
      now = now.add(const Duration(minutes: 1));
      var progress = await store.markDone(
        course: 'ramadan',
        lesson: 'namerenie',
        contentVersion: '1',
      );
      expect(progress.lessons['namerenie']!.toJson(), {
        'status': 'completed',
        'step_slug': '',
        'content_version': '1',
        'updated_at': '2026-10-24T09:31:00.123Z',
      });
      // Opening it again keeps it studied.
      now = now.add(const Duration(minutes: 1));
      progress = await store.recordOpen(
        course: 'ramadan',
        lesson: 'namerenie',
        contentVersion: '2',
      );
      expect(progress.isDone('namerenie'), isTrue);
      expect(progress.lastUpdatedAt, '2026-10-24T09:32:00.123Z');
      progress = await store.unmark(
        course: 'ramadan',
        lesson: 'namerenie',
        contentVersion: '2',
      );
      expect(progress.isDone('namerenie'), isFalse);
      expect((await store.read('ramadan')).lessons['namerenie']!.toJson(), {
        'status': 'in_progress',
        'step_slug': '',
        'content_version': '2',
        'updated_at': '2026-10-24T09:32:00.123Z',
      });
    });

    test('counts the lessons of the current version and resumes', () {
      final document = CourseDocument.fromJson(courseDocumentJson());
      Map<String, Object?> entry(String status) => {
        'status': status,
        'step_slug': '',
        'content_version': '1',
        'updated_at': '2026-10-24T09:00:00.000Z',
      };
      final progress = CourseProgress.fromJson({
        'lessons': {
          'smysl-posta': entry('completed'),
          // A lesson gone from a new version does not count.
          'gone': entry('completed'),
          'namerenie': entry('in_progress'),
          // Entries that do not fit are dropped, as on the site.
          'taraviikh': {
            'status': 'done',
            'step_slug': '',
            'content_version': '1',
          },
          'other': {
            'status': 'completed',
            'step_slug': null,
            'content_version': '1',
          },
          '../x': entry('completed'),
        },
      });
      expect(progress.lessons.keys, ['smysl-posta', 'gone', 'namerenie']);
      expect(progress.doneCount(document), 1);
      expect(progress.resumeLesson(document)?.slug, 'namerenie');
      final all = CourseProgress.fromJson({
        'lessons': {
          for (final lesson in document.lessons)
            lesson.slug: entry('completed'),
        },
      });
      expect(all.resumeLesson(document), isNull);
      expect(CourseProgress.fromJson({'lessons': []}).isEmpty, isTrue);
    });
  });
}
