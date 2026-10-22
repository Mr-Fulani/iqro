import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_models.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_models.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_progress.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'tajweed_course_test_data.dart';

void main() {
  group('document', () {
    test('reads the course in the order of its sections', () {
      final document = TajweedCourseDocument.fromJson(
        tajweedCourseDocumentJson(),
      );
      expect(document.course.version, '2026-10-22');
      expect(document.course.title, 'Таджвид');
      expect(document.pendingReview, isTrue);
      // «iqlab» is listed in the section but not in the lessons.
      expect(document.sections.first.lessons, ['izhar', 'idgham-ghunnah']);
      expect(document.orderedLessons.map((lesson) => lesson.slug), [
        'izhar',
        'idgham-ghunnah',
        'ikhfa-shafawi',
      ]);
      expect(document.nextLesson('idgham-ghunnah')?.slug, 'ikhfa-shafawi');
      expect(document.nextLesson('ikhfa-shafawi'), isNull);
      final izhar = document.lesson('izhar')!;
      expect(izhar.minutes, 4);
      expect(izhar.letters, 'ء ه ع ح غ خ');
      expect(izhar.explanation.split('\n\n'), hasLength(3));
      final target = document.target(izhar);
      expect(target.name, 'Изхар');
      expect(target.arabicName, 'الإظهار الحلقي');
      expect(target.color, const Color(0xff7b5ea7));
      expect(target.rule, isNull);
      expect(
        document.target(document.lesson('idgham-ghunnah')!).rule,
        'idgham_ghunnah',
      );
    });

    test('rejects another schema and lessons that do not fit', () {
      Map<String, Object?> changed(void Function(Map<String, Object?>) edit) {
        final json = tajweedCourseDocumentJson();
        edit(json);
        return json;
      }

      expect(
        () => TajweedCourseDocument.fromJson(
          changed((json) => json['schema_version'] = 2),
        ),
        throwsFormatException,
      );
      expect(
        () => TajweedCourseDocument.fromJson(
          changed(
            (json) =>
                ((json['lessons']! as List).first as Map)['target'] = 'nope',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => TajweedCourseDocument.fromJson(
          changed(
            (json) =>
                ((json['lessons']! as List).first as Map)['slug'] = 'Izhar',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => TajweedCourseDocument.fromJson(
          changed(
            (json) =>
                ((json['targets']! as Map)['izhar'] as Map)['color'] = 'red',
          ),
        ),
        throwsFormatException,
      );
    });

    test('drops examples that do not fit', () {
      final page = TajweedExamplesPage.fromJson(<String, Object?>{
        'offset': 4,
        'next_offset': null,
        'examples': [
          ...tajweedCourseExamplesJson('izhar').take(2),
          <String, Object?>{'verse_key': '1:1', 'words': [], 'occurrences': []},
          'not an example',
        ],
      });
      expect(page.offset, 4);
      expect(page.nextOffset, isNull);
      expect(page.examples.map((example) => example.verseKey), [
        '89:2',
        '101:11',
      ]);
      expect(TajweedExamplesPage.fromJson(null).examples, isEmpty);
    });

    test('a lesson reads all first examples but the last, then finds it', () {
      final examples = [
        for (final item in tajweedCourseExamplesJson('izhar').take(4))
          TajweedCourseExample.tryParse(item)!,
      ];
      final split = splitFirstTajweedExamples(examples);
      expect(split.shown.map((example) => example.verseKey), [
        '89:2',
        '101:11',
        '88:4',
      ]);
      expect(split.find?.verseKey, '80:18');
      expect(
        tajweedLessonStepSlugs(split.shown.length, find: split.find != null),
        ['intro', 'how', 'example-1', 'example-2', 'example-3', 'find'],
      );

      final single = splitFirstTajweedExamples(examples.take(1).toList());
      expect(single.shown, hasLength(1));
      expect(single.find, isNull);
      expect(tajweedLessonStepSlugs(1, find: false), [
        'intro',
        'how',
        'example-1',
      ]);
      // Before the examples arrive the lesson has its first example step.
      expect(tajweedLessonStepSlugs(0, find: false), [
        'intro',
        'how',
        'example-1',
      ]);
      expect(isTajweedStepSlug('example-12'), isTrue);
      expect(isTajweedStepSlug('example-0'), isFalse);
      expect(isTajweedStepSlug('summary'), isFalse);
    });

    test('an occurrence spans its words and colours its letters', () {
      final example = TajweedCourseExample.tryParse(
        tajweedCourseExamplesJson('izhar')[3],
      )!;
      expect(example.verseKey, '80:18');
      expect(example.occurrences, hasLength(2));
      expect(example.occurrenceAt(2), 0);
      expect(example.occurrenceAt(4), 1);
      expect(example.occurrenceAt(5), -1);
      final occurrence = example.occurrences.first;
      expect(occurrence.positions, [1, 2]);
      final runs = tajweedRuns(
        example.words.first.text,
        occurrence.fragments(1),
      );
      expect(runs.map((run) => (run.text, run.code)), [
        ('مِ', null),
        ('نْ', 'target'),
      ]);
      final words = <int, ({Duration start, Duration end})>{
        1: (start: _ms(1000), end: _ms(1400)),
        2: (start: _ms(1400), end: _ms(1900)),
      };
      expect(tajweedOccurrenceTiming(words, occurrence), (
        start: _ms(1000),
        end: _ms(1900),
      ));
      expect(tajweedOccurrenceTiming({1: words[1]!}, occurrence), isNull);
    });
  });

  group('progress', () {
    TajweedLessonProgress entry(String status, String step, String at) =>
        TajweedLessonProgress.tryParse(<String, Object?>{
          'status': status,
          'step_slug': step,
          'content_version': '2026-10-22',
          'updated_at': at,
        })!;

    test('drops entries that do not fit', () {
      final progress = TajweedCourseProgress.fromJson(<String, Object?>{
        'lessons': <String, Object?>{
          'izhar': <String, Object?>{
            'status': 'completed',
            'step_slug': 'find',
            'content_version': '2026-10-22',
            'updated_at': '2026-10-22T10:00:00.000Z',
          },
          'ikhfa': <String, Object?>{'status': 'not_started'},
          'Bad Slug': <String, Object?>{
            'status': 'in_progress',
            'step_slug': 'how',
            'content_version': '2026-10-22',
          },
        },
      });
      expect(progress.lessons.keys, ['izhar']);
      expect(progress.statusOf('izhar'), TajweedLessonStatus.completed);
      expect(progress.statusOf('ikhfa'), TajweedLessonStatus.notStarted);
      expect(TajweedCourseProgress.fromJson(null).lessons, isEmpty);
    });

    test('merges like the backend: passed stays passed, later wins', () {
      final local = TajweedCourseProgress({
        'izhar': entry('completed', 'find', '2026-10-22T10:00:00.000Z'),
        'iqlab': entry('in_progress', 'how', '2026-10-22T12:00:00.000Z'),
        'ikhfa': entry('in_progress', 'example-2', '2026-10-22T09:00:00.000Z'),
      });
      final remote = TajweedCourseProgress({
        'izhar': entry('in_progress', 'intro', '2026-10-22T11:00:00.000Z'),
        'iqlab': entry('in_progress', 'find', '2026-10-22T11:00:00.000Z'),
        'ghunnah': entry('in_progress', 'how', '2026-10-21T08:00:00.000Z'),
      });
      final merged = local.merge(remote);
      expect(merged.toJson(), remote.merge(local).toJson());
      expect(merged.lessons['izhar']!.toJson(), <String, Object?>{
        'status': 'completed',
        'step_slug': 'intro',
        'content_version': '2026-10-22',
        'updated_at': '2026-10-22T11:00:00.000Z',
      });
      expect(merged.lessons['iqlab']!.stepSlug, 'how');
      expect(merged.lessons['ikhfa']!.stepSlug, 'example-2');
      expect(merged.lessons['ghunnah']!.stepSlug, 'how');
    });

    test('continues the latest unfinished lesson, else the next one', () {
      final document = TajweedCourseDocument.fromJson(
        tajweedCourseDocumentJson(),
      );
      expect(
        const TajweedCourseProgress().resumeLesson(document)?.slug,
        'izhar',
      );
      var progress = TajweedCourseProgress({
        'izhar': entry('in_progress', 'how', '2026-10-22T10:00:00.000Z'),
        'ikhfa-shafawi': entry(
          'in_progress',
          'find',
          '2026-10-22T11:00:00.000Z',
        ),
      });
      expect(progress.resumeLesson(document)?.slug, 'ikhfa-shafawi');
      progress = TajweedCourseProgress({
        'izhar': entry('completed', 'find', '2026-10-22T10:00:00.000Z'),
      });
      expect(progress.resumeLesson(document)?.slug, 'idgham-ghunnah');
      expect(progress.completedCount(document), 1);
      progress = TajweedCourseProgress({
        for (final slug in ['izhar', 'idgham-ghunnah', 'ikhfa-shafawi'])
          slug: entry('completed', 'find', '2026-10-22T10:00:00.000Z'),
      });
      expect(progress.resumeLesson(document), isNull);
    });

    test(
      'a link wins, an unfinished lesson resumes, a passed one restarts',
      () {
        final progress = TajweedCourseProgress({
          'izhar': entry(
            'in_progress',
            'example-5',
            '2026-10-22T10:00:00.000Z',
          ),
          'iqlab': entry('completed', 'find', '2026-10-22T10:00:00.000Z'),
        });
        expect(progress.resumeSteps('izhar', null), ['example-5']);
        expect(progress.resumeSteps('izhar', 'how'), ['how', 'example-5']);
        expect(progress.resumeSteps('izhar', 'nonsense'), ['example-5']);
        expect(progress.resumeSteps('iqlab', null), isEmpty);
        expect(progress.resumeSteps('ikhfa', null), isEmpty);
      },
    );
  });

  group('store, repository and sync', () {
    late Database sqlDatabase;
    late LocalDatabase database;
    late TajweedCourseProgressStore store;
    late _FakeRemote remote;
    late DateTime now;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await sqlDatabase.execute('''
        CREATE TABLE app_state (
          owner_id TEXT NOT NULL,
          state_key TEXT NOT NULL,
          payload TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (owner_id, state_key)
        )
      ''');
      await sqlDatabase.execute('''
        CREATE TABLE cache_entries (
          cache_key TEXT PRIMARY KEY,
          payload TEXT NOT NULL,
          etag TEXT,
          updated_at TEXT NOT NULL,
          expires_at TEXT
        )
      ''');
      database = LocalDatabase.forTesting(sqlDatabase);
      now = DateTime.utc(2026, 10, 22, 12, 0, 0, 123, 456);
      store = TajweedCourseProgressStore(database, clock: () => now);
      remote = _FakeRemote();
    });

    tearDown(() => sqlDatabase.close());

    test(
      'stores the step in app_state; a passed lesson stays passed',
      () async {
        await store.recordStep(
          course: 'tajweed',
          lesson: 'izhar',
          stepSlug: 'example-2',
          contentVersion: '2026-10-22',
        );
        expect(await database.readState('tajweed.progress.tajweed'), {
          'lessons': {
            'izhar': {
              'status': 'in_progress',
              'step_slug': 'example-2',
              'content_version': '2026-10-22',
              // Milliseconds, as the site's toISOString() and the backend.
              'updated_at': '2026-10-22T12:00:00.123Z',
            },
          },
        });
        await store.complete(
          course: 'tajweed',
          lesson: 'izhar',
          stepSlug: 'find',
          contentVersion: '2026-10-22',
        );
        now = now.add(const Duration(minutes: 1));
        final progress = await store.recordStep(
          course: 'tajweed',
          lesson: 'izhar',
          stepSlug: 'intro',
          contentVersion: '2026-10-22',
        );
        expect(progress.statusOf('izhar'), TajweedLessonStatus.completed);
        expect(progress.lessons['izhar']!.stepSlug, 'intro');
        expect(
          (await store.read('tajweed')).statusOf('izhar'),
          TajweedLessonStatus.completed,
        );
      },
    );

    test('caches the document by version; offline uses the last one', () async {
      final repository = TajweedCourseRepository(
        remote: remote,
        database: database,
      );
      final document = await repository.course('tajweed', 'ru');
      expect(document.lessons, hasLength(3));
      expect(remote.documentRequests, ['tajweed:ru']);
      expect(
        await database.readCache('tajweed-course:tajweed:ru:2026-10-22'),
        isNotNull,
      );

      await repository.course('tajweed', 'ru');
      expect(remote.documentRequests, hasLength(1));
      expect(remote.listRequests, 2);

      remote.offline = true;
      final offline = await repository.course('tajweed', 'ru');
      expect(offline.course.version, '2026-10-22');

      remote
        ..offline = false
        ..published = false;
      await expectLater(
        repository.course('tajweed', 'ru'),
        throwsA(isA<TajweedCourseUnavailable>()),
      );
    });

    test('pages examples with offset and limit', () async {
      final repository = TajweedCourseRepository(
        remote: remote,
        database: database,
      );
      final first = await repository.examples(
        'tajweed',
        'izhar',
        offset: 0,
        limit: 4,
      );
      expect(first.examples, hasLength(4));
      expect(first.nextOffset, 4);
      final more = await repository.examples(
        'tajweed',
        'izhar',
        offset: 4,
        limit: 3,
      );
      expect(more.examples.map((example) => example.verseKey), [
        '88:5',
        '88:10',
        '96:10',
      ]);
      expect(more.nextOffset, isNull);
      expect(remote.exampleRequests, ['izhar 0 4', 'izhar 4 3']);
    });

    test('sync sends the local progress and keeps the merged answer', () async {
      await store.recordStep(
        course: 'tajweed',
        lesson: 'izhar',
        stepSlug: 'how',
        contentVersion: '2026-10-22',
      );
      remote.stored = <String, Object?>{
        'ikhfa': <String, Object?>{
          'status': 'completed',
          'step_slug': 'find',
          'content_version': '2026-10-22',
          'updated_at': '2026-10-21T08:00:00.000Z',
        },
        'izhar': <String, Object?>{
          'status': 'in_progress',
          'step_slug': 'intro',
          'content_version': '2026-10-22',
          'updated_at': '2026-10-21T08:00:00.000Z',
        },
      };
      final merged = <String>[];
      final sync = TajweedProgressSync(
        remote: remote,
        store: store,
        database: database,
        session: () => _session('test-owner'),
        onMerged: merged.add,
      );
      final result = await sync.sync('tajweed');

      expect(remote.saved, hasLength(1));
      expect(remote.saved.single.course, 'tajweed');
      expect(remote.saved.single.body, {
        'lessons': {
          'izhar': {
            'status': 'in_progress',
            'step_slug': 'how',
            'content_version': '2026-10-22',
            'updated_at': '2026-10-22T12:00:00.123Z',
          },
        },
      });
      expect(remote.saved.single.scope?.userId, 'test-owner');
      expect(result?.statusOf('ikhfa'), TajweedLessonStatus.completed);
      final local = await store.read('tajweed');
      expect(local.statusOf('ikhfa'), TajweedLessonStatus.completed);
      // The local step is the later one and stays.
      expect(local.lessons['izhar']!.stepSlug, 'how');
      expect(merged, ['tajweed']);
    });

    test('sync waits for a session and skips a pending deletion', () async {
      await store.recordStep(
        course: 'tajweed',
        lesson: 'izhar',
        stepSlug: 'how',
        contentVersion: '2026-10-22',
      );
      AuthSession? session;
      final sync = TajweedProgressSync(
        remote: remote,
        store: store,
        database: database,
        session: () => session,
      );
      expect(await sync.sync('tajweed'), isNull);
      session = _session('test-owner', status: 'pending_deletion');
      expect(await sync.sync('tajweed'), isNull);
      session = _session('someone-else');
      expect(await sync.sync('tajweed'), isNull);
      expect(remote.saved, isEmpty);

      // A guest has a session too; offline the progress stays local.
      session = _session('test-owner', status: 'guest');
      remote.offline = true;
      expect(await sync.sync('tajweed'), isNull);
      expect((await store.read('tajweed')).lessons.keys, ['izhar']);
      remote.offline = false;
      expect(await sync.sync('tajweed'), isNotNull);
      expect(remote.saved, hasLength(1));
    });
  });
}

Duration _ms(int value) => Duration(milliseconds: value);

AuthSession _session(String userId, {String status = 'active'}) => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
  bootstrapGeneration: 1,
  userId: userId,
  userStatus: status,
  deviceId: 'device',
  email: status == 'guest' ? null : 'learner@example.com',
);

class _FakeRemote implements TajweedCourseRemoteGateway {
  var offline = false;
  var published = true;
  var listRequests = 0;
  final documentRequests = <String>[];
  final exampleRequests = <String>[];
  Map<String, Object?> stored = {};
  final saved =
      <
        ({
          String course,
          Map<String, Object?> body,
          AccountScopeSnapshot? scope,
        })
      >[];

  void _check() {
    if (offline) {
      throw const ApiException(message: 'offline');
    }
  }

  @override
  Future<Object?> courses() async {
    listRequests += 1;
    _check();
    return [
      if (published)
        <String, Object?>{
          'slug': 'tajweed',
          'version': '2026-10-22',
          'languages': ['ar', 'en', 'ru', 'tr'],
        },
    ];
  }

  @override
  Future<Object?> course(String slug, String language) async {
    documentRequests.add('$slug:$language');
    _check();
    return tajweedCourseDocumentJson();
  }

  @override
  Future<Object?> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) async {
    exampleRequests.add('$lesson $offset $limit');
    _check();
    return tajweedCourseExamplesPage(lesson, offset: offset, limit: limit);
  }

  @override
  Future<Object?> saveProgress(
    String course,
    Map<String, Object?> body, {
    AccountScopeSnapshot? accountScope,
  }) async {
    _check();
    saved.add((course: course, body: body, scope: accountScope));
    final incoming = TajweedCourseProgress.fromJson(body);
    final merged = TajweedCourseProgress.fromJson(<String, Object?>{
      'lessons': stored,
    }).merge(incoming);
    stored = merged.toJson()['lessons']! as Map<String, Object?>;
    return <String, Object?>{'course': course, 'lessons': stored};
  }

  // The practice calls are tested in tajweed_practice_test.dart.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
