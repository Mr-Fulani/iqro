import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/courses/account_progress_sync.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/salah/salah_progress.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'salah_progress_test.dart' show createSalahStateTable;

void main() {
  late Database sqlDatabase;
  late LocalDatabase database;
  late SalahProgressStore salah;
  late CourseProgressStore courses;
  late DateTime now;
  late bool offline;
  late Map<String, Object?> serverLessons;
  final saved =
      <
        ({
          String kind,
          String course,
          Map<String, Object?> body,
          AccountScopeSnapshot? scope,
        })
      >[];
  final merged = <String>[];
  AuthSession? session;

  AccountProgressSync sync() => AccountProgressSync(
    save: (kind, course, body, {accountScope}) async {
      if (offline) throw const ApiException(message: 'offline');
      saved.add((kind: kind, course: course, body: body, scope: accountScope));
      return <String, Object?>{
        'kind': kind,
        'course': course,
        'lessons': <String, Object?>{
          ...body['lessons']! as Map<String, Object?>,
          ...serverLessons,
        },
      };
    },
    database: database,
    session: () => session,
    merge: (kind, course, answer, accountScope) =>
        kind == AccountProgressSync.salah
        ? salah.merge(
            course,
            SalahCourseProgress.fromJson(answer),
            accountScope: accountScope,
          )
        : courses.merge(
            course,
            CourseProgress.fromJson(answer),
            accountScope: accountScope,
          ),
    onMerged: (kind, course) => merged.add('$kind:$course'),
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createSalahStateTable(sqlDatabase);
    database = LocalDatabase.forTesting(sqlDatabase);
    now = DateTime.utc(2026, 11, 10, 12);
    salah = SalahProgressStore(database, clock: () => now);
    courses = CourseProgressStore(database, clock: () => now);
    offline = false;
    serverLessons = {};
    saved.clear();
    merged.clear();
    session = _session('test-owner');
  });

  tearDown(() => sqlDatabase.close());

  test('the prayer course is sent and a lesson passed elsewhere '
      'stays passed', () async {
    await salah.recordStep(
      course: 'hanbali-umdah',
      lesson: 'fajr',
      stepSlug: 'fajr.r1.ruku',
      contentVersion: '2026-10-18',
    );
    serverLessons = {
      // Passed on the site earlier; opened here later.
      'fajr': _entry('completed', 'fajr.salam', '2026-11-09T08:00:00.000Z'),
      'wudu': _entry('completed', 'wudu.feet', '2026-11-09T07:00:00.000Z'),
    };

    expect(await sync().sync(AccountProgressSync.salah, 'hanbali-umdah'), true);

    expect(saved.single.kind, 'salah');
    expect(saved.single.course, 'hanbali-umdah');
    expect(saved.single.body, {
      'lessons': {
        'fajr': _entry(
          'in_progress',
          'fajr.r1.ruku',
          '2026-11-10T12:00:00.000Z',
        ),
      },
    });
    expect(saved.single.scope?.userId, 'test-owner');
    final local = await salah.read('hanbali-umdah');
    expect(local.statusOf('wudu'), SalahLessonStatus.completed);
    expect(local.statusOf('fajr'), SalahLessonStatus.completed);
    // The local step is the later one and stays.
    expect(local.lessons['fajr']!.stepSlug, 'fajr.r1.ruku');
    expect(merged, ['salah:hanbali-umdah']);
  });

  test('a topical course takes the later record, so «Studied» taken back '
      'stays taken back', () async {
    await courses.markDone(
      course: 'ramadan',
      lesson: 'niyat',
      contentVersion: '3',
    );
    now = now.add(const Duration(minutes: 5));
    await courses.unmark(
      course: 'ramadan',
      lesson: 'niyat',
      contentVersion: '3',
    );
    serverLessons = {
      // The account still has the earlier «Studied» and a lesson from the site.
      'niyat': _entry('completed', '', '2026-11-10T12:00:00.000Z'),
      'tarawih': _entry('completed', '', '2026-11-09T07:00:00.000Z'),
    };

    expect(await sync().sync(AccountProgressSync.courses, 'ramadan'), true);

    expect(saved.single.kind, 'courses');
    final local = await courses.read('ramadan');
    expect(local.isDone('niyat'), false);
    expect(local.isDone('tarawih'), true);
    expect(merged, ['courses:ramadan']);
  });

  test('only a signed-in account syncs; offline the progress stays '
      'local', () async {
    await courses.recordOpen(
      course: 'ramadan',
      lesson: 'niyat',
      contentVersion: '3',
    );
    final progress = sync();
    for (final current in <AuthSession?>[
      null,
      _session('test-owner', status: 'guest'),
      _session('test-owner', status: 'pending_deletion'),
      _session('someone-else'),
    ]) {
      session = current;
      expect(
        await progress.sync(AccountProgressSync.courses, 'ramadan'),
        false,
      );
    }
    expect(saved, isEmpty);

    session = _session('test-owner');
    offline = true;
    expect(await progress.sync(AccountProgressSync.courses, 'ramadan'), false);
    expect((await courses.read('ramadan')).lessons.keys, ['niyat']);
    expect(merged, isEmpty);
  });
}

Map<String, Object?> _entry(String status, String step, String at) =>
    <String, Object?>{
      'status': status,
      'step_slug': step,
      'content_version': '2026-10-18',
      'updated_at': at,
    };

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
