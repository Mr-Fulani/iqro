import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';
import 'package:iqro_mobile/features/salah/salah_progress.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'salah_models_test.dart' show salahFixture;

void main() {
  late Database sqlDatabase;
  late LocalDatabase database;
  late SalahProgressStore store;
  late SalahCourseDocument document;
  late DateTime now;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createSalahStateTable(sqlDatabase);
    database = LocalDatabase.forTesting(sqlDatabase);
    now = DateTime.utc(2026, 10, 18, 12);
    store = SalahProgressStore(database, clock: () => now);
    document = SalahCourseDocument.fromJson(salahFixture());
  });

  tearDown(() => sqlDatabase.close());

  test('stores lesson status, step and content version in app_state', () async {
    await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r1.ruku',
      contentVersion: '2026-10-18',
    );

    final raw = await database.readState('salah.progress.hanbali-umdah');
    expect(raw, <String, Object?>{
      'lessons': <String, Object?>{
        'fajr': <String, Object?>{
          'status': 'in_progress',
          'step_slug': 'fajr.r1.ruku',
          'content_version': '2026-10-18',
          'updated_at': '2026-10-18T12:00:00.000Z',
        },
      },
    });
    final progress = await store.read('hanbali-umdah');
    expect(progress.statusOf('fajr'), SalahLessonStatus.inProgress);
    expect(progress.statusOf('wudu'), SalahLessonStatus.notStarted);
  });

  test('a completed lesson never returns to in progress', () async {
    await store.complete(
      course: 'hanbali-umdah',
      lesson: 'wudu',
      stepSlug: 'wudu.face',
      contentVersion: '2026-10-18',
    );
    final progress = await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'wudu',
      stepSlug: 'wudu.intention',
      contentVersion: '2026-10-18',
    );

    expect(progress.statusOf('wudu'), SalahLessonStatus.completed);
    expect(progress.lessons['wudu']!.stepSlug, 'wudu.intention');
    expect(progress.completedCount(document), 1);
  });

  test('resumes on the saved step, or from the start', () async {
    final fajr = document.lesson('fajr')!;
    var progress = await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r2.tashahhud',
      contentVersion: '2026-10-18',
    );
    expect(progress.resumeStepIndex(fajr), 3);

    // The step is gone from a newer content version.
    progress = await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r1.removed',
      contentVersion: '2026-09-01',
    );
    expect(progress.resumeStepIndex(fajr), 0);

    progress = await store.complete(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r2.taslim',
      contentVersion: '2026-10-18',
    );
    expect(progress.resumeStepIndex(fajr), 0);
  });

  test('«Continue» opens the latest unfinished lesson', () async {
    expect(
      const SalahCourseProgress().resumeLesson(document)?.slug,
      'what-is-salah',
    );

    await store.complete(
      course: 'hanbali-umdah',
      lesson: 'what-is-salah',
      stepSlug: 'what-is-salah.intro',
      contentVersion: '2026-10-18',
    );
    var progress = await store.read('hanbali-umdah');
    expect(progress.resumeLesson(document)?.slug, 'wudu');

    await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r1.fatiha',
      contentVersion: '2026-10-18',
    );
    now = now.add(const Duration(minutes: 5));
    progress = await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'wudu',
      stepSlug: 'wudu.face',
      contentVersion: '2026-10-18',
    );
    expect(progress.resumeLesson(document)?.slug, 'wudu');
    now = now.add(const Duration(minutes: 5));
    progress = await store.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r1.ruku',
      contentVersion: '2026-10-18',
    );
    expect(progress.resumeLesson(document)?.slug, 'fajr');

    for (final lesson in <String>['wudu', 'fajr']) {
      progress = await store.complete(
        course: 'hanbali-umdah',
        lesson: lesson,
        stepSlug: 'x',
        contentVersion: '2026-10-18',
      );
    }
    expect(progress.resumeLesson(document), isNull);
    expect(progress.completedCount(document), 3);
  });

  test('fast step changes are saved in order', () async {
    await Future.wait(<Future<Object?>>[
      for (final step in <String>['a', 'b', 'c'])
        store.recordStep(
          course: 'hanbali-umdah',
          lesson: step == 'c' ? 'wudu' : 'fajr',
          stepSlug: step,
          contentVersion: 'v',
        ),
    ]);

    final progress = await store.read('hanbali-umdah');
    expect(progress.lessons['fajr']!.stepSlug, 'b');
    expect(progress.lessons['wudu']!.stepSlug, 'c');
  });
}

Future<void> createSalahStateTable(Database database) => database.execute('''
  CREATE TABLE app_state (
    owner_id TEXT NOT NULL,
    state_key TEXT NOT NULL,
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (owner_id, state_key)
  )
''');
