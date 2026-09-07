import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/offline_package_queries.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute(
      'CREATE TABLE offline_packages (package_id TEXT PRIMARY KEY, manifest TEXT NOT NULL)',
    );
  });
  tearDown(() => database.close());

  test('status projections never request the full manifest or wildcard', () {
    expect(offlinePackageSummaryColumns, isNot(contains('manifest')));
    expect(offlinePackageSummaryColumns, isNot(contains('*')));
    expect(
      offlinePackageSummaryColumns,
      containsAll([
        'package_id',
        'status',
        'is_active',
        'completed_items',
        'total_items',
        'downloaded_bytes',
        'total_bytes',
        'last_error',
      ]),
    );
  });

  test(
    'audio summary reads multi-megabyte Unicode manifests in bounded rows',
    () async {
      final manifest = jsonEncode({
        'tracks': 'а😀' * (1024 * 1024),
        'quality': 'high',
        'reciter': {'name_ru': 'Тестовый чтец', 'name_ar': 'قارئ'},
      });
      await database.insert('offline_packages', {
        'package_id': 'audio',
        'manifest': manifest,
      });
      final summary = await readOfflineAudioSummary(database, 'audio');
      expect(summary['quality'], 'high');
      expect((summary['reciter'] as Map)['name_ar'], 'قارئ');
      expect(summary.containsKey('tracks'), isFalse);
      expect(
        (await database.query('offline_packages')).single['manifest'],
        manifest,
      );
    },
  );

  test(
    'missing and invalid old manifest do not break the storage list',
    () async {
      expect(await readOfflineAudioSummary(database, 'missing'), isEmpty);
      await database.insert('offline_packages', {
        'package_id': 'bad',
        'manifest': '{',
      });
      expect(await readOfflineAudioSummary(database, 'bad'), isEmpty);
    },
  );
}
