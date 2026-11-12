import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/names/names_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'names_test_data.dart';

void main() {
  late Database sqlDatabase;
  late LocalDatabase database;
  late _FakeRemote remote;
  late NamesRepository repository;

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
    remote = _FakeRemote();
    repository = NamesRepository(remote: remote, database: database);
  });

  tearDown(() => sqlDatabase.close());

  test('keeps the answer for offline, per language', () async {
    final document = await repository.collection('asma-al-husna', 'ru');

    expect(document.names, hasLength(4));
    expect(remote.requests, <String>['asma-al-husna:ru']);
    expect(await database.readCache('names:asma-al-husna:ru'), isNotNull);
    expect(await database.readCache('names:asma-al-husna:en'), isNull);
  });

  test('asks the server first: a new version replaces the copy', () async {
    await repository.collection('asma-al-husna', 'ru');
    remote.document = namesFixture()
      ..['collection'] = <String, Object?>{
        ...(namesFixture()['collection']! as Map<String, Object?>),
        'version': 'example-2',
      };

    final again = await repository.collection('asma-al-husna', 'ru');

    expect(again.version, 'example-2');
    expect(remote.requests, hasLength(2));
  });

  test('without a network the last answer is shown', () async {
    await repository.collection('asma-al-husna', 'ru');
    remote.error = const ApiException(message: 'offline');

    final cached = await repository.collection('asma-al-husna', 'ru');

    expect(cached.version, 'example-1');
    // Another language was never loaded: there is nothing to show.
    expect(
      repository.collection('asma-al-husna', 'tr'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a list that is not published is not shown from the copy', () async {
    await repository.collection('asma-al-husna', 'ru');
    remote.error = const ApiException(message: 'Not found', statusCode: 404);

    expect(
      repository.collection('asma-al-husna', 'ru'),
      throwsA(isA<NamesUnavailable>()),
    );
  });

  test('a refused request does not fall back to the copy', () async {
    await repository.collection('asma-al-husna', 'ru');
    remote.error = const ApiException(message: 'Bad request', statusCode: 400);

    expect(
      repository.collection('asma-al-husna', 'ru'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a document of another list is rejected', () async {
    expect(repository.collection('other', 'ru'), throwsFormatException);
  });
}

class _FakeRemote implements NamesRemoteGateway {
  Map<String, Object?> document = namesFixture();
  Object? error;
  final requests = <String>[];

  @override
  Future<Object?> collection(String slug, String language) async {
    requests.add('$slug:$language');
    final failure = error;
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return document;
  }
}
