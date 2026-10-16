import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'removing a never-synced highlight drops the row and its upsert',
    () async {
      final (database, repository) = await _open();
      await repository.updateAyahAnnotation(2, 255, note: '', colorKey: 'pink');

      await repository.deleteAyahAnnotation(2, 255);

      expect(await database.query('ayah_annotations'), isEmpty);
      expect(await database.query('outbox'), isEmpty);
      expect(await repository.ayahAnnotations(), isEmpty);
    },
  );

  test(
    'removing a synced highlight queues a delete with its revision',
    () async {
      final (database, repository) = await _open();
      await repository.updateAyahAnnotation(
        2,
        255,
        note: 'Аят аль-Курси',
        colorKey: 'blue',
      );
      await _markSynced(database, revision: 3);

      await repository.deleteAyahAnnotation(2, 255);

      final rows = await database.query('ayah_annotations');
      expect(rows.single['is_deleted'], 1);
      expect(await repository.ayahAnnotations(), isEmpty);
      expect(await repository.annotationDetails(2, 255), isNull);
      final operation = _payload((await database.query('outbox')).single);
      expect(operation['entity_type'], 'ayah_annotation');
      expect(operation['entity_id'], rows.single['id']);
      expect(operation['action'], 'delete');
      expect(operation['base_revision'], 3);
    },
  );

  test(
    'highlighting again after removal revives the same annotation',
    () async {
      final (database, repository) = await _open();
      await repository.updateAyahAnnotation(2, 255, note: '', colorKey: 'lime');
      await _markSynced(database, revision: 3);
      final id = (await database.query('ayah_annotations')).single['id'];
      await repository.deleteAyahAnnotation(2, 255);

      await repository.updateAyahAnnotation(
        2,
        255,
        note: '',
        colorKey: 'yellow',
      );

      final row = (await database.query('ayah_annotations')).single;
      expect(row['id'], id);
      expect(row['is_deleted'], 0);
      expect(row['color_key'], 'yellow');
      final operation = _payload((await database.query('outbox')).single);
      expect(operation['action'], 'upsert');
      expect(operation['base_revision'], 3);
    },
  );

  test('removing an ayah without a highlight changes nothing', () async {
    final (database, repository) = await _open();

    await repository.deleteAyahAnnotation(2, 255);

    expect(await database.query('ayah_annotations'), isEmpty);
    expect(await database.query('outbox'), isEmpty);
  });
}

Future<(Database, QuranRepository)> _open() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  addTearDown(database.close);
  await database.execute('''
    CREATE TABLE ayah_annotations (
      owner_id TEXT NOT NULL,
      id TEXT NOT NULL,
      edition TEXT NOT NULL,
      surah INTEGER NOT NULL,
      ayah INTEGER NOT NULL,
      page INTEGER,
      color_key TEXT NOT NULL DEFAULT 'lime',
      note TEXT NOT NULL DEFAULT '',
      server_revision INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, id)
    )
  ''');
  await database.execute('''
    CREATE TABLE outbox (
      owner_id TEXT NOT NULL,
      operation_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_error TEXT,
      PRIMARY KEY (owner_id, operation_id)
    )
  ''');
  final accountScope = AccountScope.forTesting('reader');
  const config = AppConfig(
    apiBaseUrl: 'https://iqro.forum',
    fallbackDownloadUrl: 'https://iqro.forum',
    environment: 'production',
  );
  final repository = QuranRepository(
    api: ApiClient(
      config: config,
      authRepository: AuthRepository(
        config: config,
        accountScope: accountScope,
      ),
      locale: () => 'en',
    ),
    database: LocalDatabase.forTesting(database, accountScope: accountScope),
  );
  return (database, repository);
}

/// What a successful sync leaves behind: the server's revision, no outbox.
Future<void> _markSynced(Database database, {required int revision}) async {
  await database.update('ayah_annotations', <String, Object?>{
    'server_revision': revision,
  });
  await database.delete('outbox');
}

Map<String, Object?> _payload(Map<String, Object?> row) =>
    jsonDecode(row['payload']! as String) as Map<String, Object?>;
