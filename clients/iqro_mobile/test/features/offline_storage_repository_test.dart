import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/offline_storage_quota.dart';
import 'package:iqro_mobile/features/settings/offline_storage_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'storage list omits large Mushaf manifests and keeps audio labels',
    () async {
      final harness = await _harness();
      for (final type in ['mushaf_pages', 'surah_audio']) {
        await _insertPackage(
          harness.database,
          packageId: type,
          packageType: type,
          contentKey: type,
          status: 'ready',
          localPath: '/not-used-for-read-only-list',
        );
      }
      await harness.database.database.update(
        'offline_packages',
        {
          'manifest': jsonEncode({'pages': 'x' * (3 * 1024 * 1024)}),
        },
        where: 'package_id = ?',
        whereArgs: ['mushaf_pages'],
      );
      final packages = await harness.repository.packages();
      expect(packages.firstWhere((p) => p.isMushaf).manifest, isEmpty);
      final audio = packages.firstWhere((p) => p.isAudio);
      expect(audio.quality, 'standard');
      expect(audio.reciterNameFor('ru'), 'Тестовый чтец');
      expect(packages.every((p) => p.status == 'ready'), isTrue);
    },
  );

  test(
    'lists actual package bytes and deletes only the confirmed package',
    () async {
      final harness = await _harness();
      final packageDirectory = Directory(
        p.join(
          harness.support.path,
          'offline_packages',
          'mushaf',
          'mushaf-test',
        ),
      );
      await packageDirectory.create(recursive: true);
      final page = File(p.join(packageDirectory.path, 'page-001.webp'));
      final partial = File(p.join(packageDirectory.path, 'page-002.webp.part'));
      await page.writeAsBytes(const <int>[1, 2, 3]);
      await partial.writeAsBytes(const <int>[4, 5]);
      await _insertPackage(
        harness.database,
        packageId: 'mushaf-test',
        packageType: 'mushaf_pages',
        contentKey: 'quran-edition:madani-hafs',
        status: 'ready',
        localPath: page.path,
      );

      final packages = await harness.repository.packages();

      expect(packages, hasLength(1));
      expect(packages.single.usedBytes, 5);
      expect(packages.single.totalBytes, 10);
      expect(packages.single.isMushaf, isTrue);

      await harness.repository.deletePackage('mushaf-test');

      expect(await packageDirectory.exists(), isFalse);
      expect(
        await harness.database.database.query('offline_packages'),
        isEmpty,
      );
      expect(
        await harness.database.database.query('offline_package_items'),
        isEmpty,
      );
    },
  );

  test('refuses active downloads and unsafe file paths', () async {
    final harness = await _harness();
    final packageDirectory = Directory(
      p.join(harness.support.path, 'offline_packages', 'audio', 'audio-test'),
    );
    await packageDirectory.create(recursive: true);
    final outside = File(p.join(harness.support.path, 'must-stay.mp3'));
    await outside.writeAsBytes(const <int>[1, 2, 3]);
    await _insertPackage(
      harness.database,
      packageId: 'audio-test',
      packageType: 'surah_audio',
      contentKey: 'recitation:00000000-0000-0000-0000-000000000001',
      status: 'downloading',
      localPath: outside.path,
    );

    await expectLater(
      harness.repository.deletePackage('audio-test'),
      throwsStateError,
    );
    await harness.database.database.update(
      'offline_packages',
      const <String, Object?>{'status': 'failed'},
      where: 'package_id = ?',
      whereArgs: const <Object?>['audio-test'],
    );
    await expectLater(
      harness.repository.deletePackage('audio-test'),
      throwsFormatException,
    );

    expect(await outside.exists(), isTrue);
    expect(await packageDirectory.exists(), isTrue);
    expect(
      await harness.database.database.query('offline_packages'),
      hasLength(1),
    );
  });

  test(
    'quota excludes a resumed package but counts other reservations',
    () async {
      final harness = await _harness();
      final packageDirectory = Directory(
        p.join(
          harness.support.path,
          'offline_packages',
          'mushaf',
          'mushaf-test',
        ),
      );
      await packageDirectory.create(recursive: true);
      final page = File(p.join(packageDirectory.path, 'page-001.webp'));
      await page.writeAsBytes(const <int>[1, 2, 3]);
      await _insertPackage(
        harness.database,
        packageId: 'mushaf-test',
        packageType: 'mushaf_pages',
        contentKey: 'quran-edition:madani-hafs',
        status: 'ready',
        localPath: page.path,
      );

      await ensureOfflineStorageCapacity(
        harness.database,
        packageId: 'mushaf-test',
        packageBytes: offlineStorageQuotaBytes,
      );
      await expectLater(
        ensureOfflineStorageCapacity(
          harness.database,
          packageId: 'another-package',
          packageBytes: offlineStorageQuotaBytes,
        ),
        throwsA(isA<OfflineStorageQuotaExceeded>()),
      );
    },
  );
}

Future<_Harness> _harness() async {
  final support = await Directory.systemTemp.createTemp('iqro-storage-test-');
  final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await raw.execute('PRAGMA foreign_keys = ON');
  await raw.execute('''
    CREATE TABLE offline_packages (
      package_id TEXT PRIMARY KEY,
      package_type TEXT NOT NULL,
      content_key TEXT NOT NULL,
      version TEXT NOT NULL,
      width INTEGER,
      checksum_sha256 TEXT NOT NULL,
      manifest TEXT NOT NULL,
      status TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 0,
      total_items INTEGER NOT NULL,
      completed_items INTEGER NOT NULL DEFAULT 0,
      total_bytes INTEGER NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
  await raw.execute('''
    CREATE TABLE offline_package_items (
      package_id TEXT NOT NULL,
      item_key TEXT NOT NULL,
      item_number INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      local_path TEXT NOT NULL,
      url TEXT NOT NULL,
      checksum_sha256 TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      metadata TEXT NOT NULL,
      status TEXT NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (package_id, item_key),
      FOREIGN KEY (package_id) REFERENCES offline_packages(package_id)
        ON DELETE CASCADE
    )
  ''');
  final database = LocalDatabase.forTesting(raw);
  final repository = OfflineStorageRepository(
    database: database,
    supportDirectory: () async => support,
  );
  addTearDown(() async {
    await raw.close();
    if (await support.exists()) await support.delete(recursive: true);
  });
  return _Harness(database, repository, support);
}

Future<void> _insertPackage(
  LocalDatabase database, {
  required String packageId,
  required String packageType,
  required String contentKey,
  required String status,
  required String localPath,
}) async {
  final now = DateTime.utc(2026, 9, 4).toIso8601String();
  await database.database.insert('offline_packages', <String, Object?>{
    'package_id': packageId,
    'package_type': packageType,
    'content_key': contentKey,
    'version': '1',
    'checksum_sha256': 'a' * 64,
    'manifest': jsonEncode(<String, Object?>{
      'quality': 'standard',
      'reciter': <String, Object?>{
        'name_en': 'Test reciter',
        'name_ru': 'Тестовый чтец',
      },
    }),
    'status': status,
    'is_active': status == 'ready' ? 1 : 0,
    'total_items': 2,
    'completed_items': 1,
    'total_bytes': 10,
    'downloaded_bytes': 3,
    'updated_at': now,
  });
  await database.database.insert('offline_package_items', <String, Object?>{
    'package_id': packageId,
    'item_key': 'item:1',
    'item_number': 1,
    'file_name': p.basename(localPath),
    'local_path': localPath,
    'url': 'https://media.iqro.forum/test',
    'checksum_sha256': 'b' * 64,
    'size_bytes': 3,
    'metadata': '{}',
    'status': 'ready',
    'downloaded_bytes': 3,
    'updated_at': now,
  });
}

class _Harness {
  const _Harness(this.database, this.repository, this.support);

  final LocalDatabase database;
  final OfflineStorageRepository repository;
  final Directory support;
}
