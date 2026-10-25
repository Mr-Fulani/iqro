import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/salah/salah_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'salah_models_test.dart' show salahFixture;

void main() {
  late Database sqlDatabase;
  late LocalDatabase database;
  late _FakeSalahRemote remote;
  late SalahRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
    remote = _FakeSalahRemote();
    repository = SalahRepository(database: database, remote: remote);
  });

  tearDown(() => sqlDatabase.close());

  test('caches the document under slug, language and version', () async {
    final document = await repository.course('hanbali-umdah', 'ru');

    expect(document.course.version, '2026-10-18');
    expect(remote.documentRequests, <String>['hanbali-umdah:ru']);
    final cached = await database.readCache(
      'salah:hanbali-umdah:ru:2026-10-18',
    );
    expect(cached, isNotNull);
    expect((cached!.value! as Map)['schema_version'], 1);
  });

  test('trusts the cache only after the version check confirms it', () async {
    await repository.course('hanbali-umdah', 'ru');
    final again = await repository.course('hanbali-umdah', 'ru');

    expect(again.course.version, '2026-10-18');
    expect(remote.listRequests, 2);
    expect(remote.documentRequests, hasLength(1));

    // A new published version is fetched even though the old one is cached.
    remote.activeVersion = '2026-11-01';
    remote.document = salahFixture()
      ..['course'] = <String, Object?>{
        ...(salahFixture()['course']! as Map<String, Object?>),
        'version': '2026-11-01',
      };
    final updated = await repository.course('hanbali-umdah', 'ru');

    expect(updated.course.version, '2026-11-01');
    expect(remote.documentRequests, hasLength(2));
    expect(
      await database.readCache('salah:hanbali-umdah:ru:2026-11-01'),
      isNotNull,
    );
  });

  test('keeps the pictures of the lessons with the document', () async {
    final kept = <List<LessonMedia>>[];
    final keeping = SalahRepository(
      database: database,
      remote: remote,
      keepMedia: (media) async => kept.add(media.toList()),
    );
    await keeping.course('hanbali-umdah', 'ru');
    await pumpEventQueue();
    // The wudu lesson's video, slide and banner; the other lessons have none.
    expect(kept.single.map((block) => block.runtimeType), [
      LessonVideoMedia,
      LessonSlidesMedia,
      LessonBannerMedia,
    ]);

    // Opened again from the device: what did not arrive is fetched now.
    await keeping.course('hanbali-umdah', 'ru');
    await pumpEventQueue();
    expect(kept, hasLength(2));
    expect(remote.documentRequests, hasLength(1));
  });

  test('pictures that cannot be kept do not fail the course', () async {
    for (final keep in <Future<void> Function(Iterable<LessonMedia>)>[
      (_) => throw Exception('no disk'),
      (_) async => throw Exception('offline'),
    ]) {
      final failing = SalahRepository(
        database: database,
        remote: remote,
        keepMedia: keep,
      );
      final document = await failing.course('hanbali-umdah', 'ru');
      await pumpEventQueue();
      expect(document.lesson('wudu')!.media, hasLength(3));
    }
  });

  test('keeps languages apart', () async {
    await repository.course('hanbali-umdah', 'ru');
    await repository.course('hanbali-umdah', 'ar');

    expect(remote.documentRequests, <String>[
      'hanbali-umdah:ru',
      'hanbali-umdah:ar',
    ]);
  });

  test('offline, opens the last confirmed version', () async {
    await repository.course('hanbali-umdah', 'ru');
    remote.listError = const ApiException(message: 'offline');

    final offline = await repository.course('hanbali-umdah', 'ru');

    expect(offline.course.version, '2026-10-18');
    expect(remote.documentRequests, hasLength(1));
  });

  test('offline without a cached copy reports the failure', () async {
    remote.listError = const ApiException(message: 'offline');

    await expectLater(
      repository.course('hanbali-umdah', 'ru'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a withdrawn course is not served from the cache', () async {
    await repository.course('hanbali-umdah', 'ru');
    remote.listed = false;

    await expectLater(
      repository.course('hanbali-umdah', 'ru'),
      throwsA(isA<SalahCourseUnavailable>()),
    );
  });

  test('a client error does not fall back to the cache', () async {
    await repository.course('hanbali-umdah', 'ru');
    remote.listError = const ApiException(message: 'bad', statusCode: 400);

    await expectLater(
      repository.course('hanbali-umdah', 'ru'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a malformed cached row is replaced by a fresh download', () async {
    await database.writeCache(
      'salah:hanbali-umdah:ru:2026-10-18',
      <String, Object?>{'schema_version': 1},
    );

    final document = await repository.course('hanbali-umdah', 'ru');

    expect(document.lessons, hasLength(3));
    expect(remote.documentRequests, hasLength(1));
  });

  test('lists courses wrapped in results', () async {
    remote.wrapList = true;

    final courses = await repository.courses();

    expect(courses.single.slug, 'hanbali-umdah');
    expect(courses.single.languages, <String>['ru', 'en', 'ar', 'tr']);
  });
}

class _FakeSalahRemote implements SalahRemoteGateway {
  var activeVersion = '2026-10-18';
  var listed = true;
  var wrapList = false;
  Object? listError;
  Map<String, Object?> document = salahFixture();
  var listRequests = 0;
  final documentRequests = <String>[];

  @override
  Future<Object?> courses() async {
    listRequests += 1;
    final error = listError;
    if (error != null) throw error;
    final items = <Object?>[
      if (listed)
        <String, Object?>{
          'slug': 'hanbali-umdah',
          'version': activeVersion,
          'methodology': 'hanbali',
          'languages': <String>['ru', 'en', 'ar', 'tr'],
          'published_at': '2026-10-18T10:05:00Z',
        },
    ];
    return wrapList ? <String, Object?>{'results': items} : items;
  }

  @override
  Future<Object?> course(String slug, String language) async {
    documentRequests.add('$slug:$language');
    return document;
  }
}
