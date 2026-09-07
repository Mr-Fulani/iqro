import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/offline_package_items.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE offline_package_items (
        package_id TEXT NOT NULL, item_key TEXT NOT NULL,
        item_number INTEGER NOT NULL, file_name TEXT NOT NULL,
        local_path TEXT NOT NULL, url TEXT NOT NULL,
        checksum_sha256 TEXT NOT NULL, size_bytes INTEGER NOT NULL,
        metadata TEXT NOT NULL, status TEXT NOT NULL,
        downloaded_bytes INTEGER NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY (package_id, item_key)
      )
    ''');
  });
  tearDown(() => database.close());

  Future<void> prepare({
    String package = 'qcf',
    String checksum = 'original',
    int bytes = 100,
    String url = 'https://media.example.test/old',
    int count = 1,
  }) => database.transaction((transaction) async {
    final batch = transaction.batch();
    for (var number = 1; number <= count; number++) {
      enqueueOfflinePackageItem(
        batch,
        packageId: package,
        itemKey: 'page:$number',
        itemNumber: number,
        fileName: 'page-$number.webp',
        localPath: '/offline/$package/page-$number.webp',
        url: url,
        checksum: checksum,
        sizeBytes: bytes,
        metadata: '{"page":$number}',
        updatedAt: '2026-09-07T18:00:00Z',
      );
    }
    await batch.commit(noResult: true);
  });

  Future<Map<String, Object?>> row() async =>
      (await database.query('offline_package_items')).single;

  test('new package stages all 604 pages in one transaction', () async {
    await prepare(count: 604);
    final rows = await database.query('offline_package_items');
    expect(rows, hasLength(604));
    expect(rows.every((r) => r['status'] == 'pending'), isTrue);
    expect(rows.every((r) => r['downloaded_bytes'] == 0), isTrue);
  });

  test(
    'resume preserves ready file and updates URL without replacing row',
    () async {
      await prepare();
      await database.update('offline_package_items', {
        'status': 'ready',
        'downloaded_bytes': 100,
      });
      final before = (await database.rawQuery(
        'SELECT rowid FROM offline_package_items',
      )).single;
      await prepare(url: 'https://media.example.test/new');
      final value = await row();
      expect(value['status'], 'ready');
      expect(value['downloaded_bytes'], 100);
      expect(value['url'], 'https://media.example.test/new');
      expect(
        (await database.rawQuery(
          'SELECT rowid FROM offline_package_items',
        )).single,
        before,
      );
    },
  );

  test('resume preserves partial progress for identical bytes', () async {
    await prepare();
    await database.update('offline_package_items', {
      'status': 'pending',
      'downloaded_bytes': 42,
    });
    await prepare();
    expect((await row())['downloaded_bytes'], 42);
  });

  for (final changed in ['checksum', 'size']) {
    test('changed $changed marks metadata pending for verification', () async {
      await prepare();
      await database.update('offline_package_items', {
        'status': 'ready',
        'downloaded_bytes': 100,
      });
      await prepare(
        checksum: changed == 'checksum' ? 'new' : 'original',
        bytes: changed == 'size' ? 101 : 100,
      );
      expect((await row())['status'], 'pending');
      expect((await row())['downloaded_bytes'], 0);
    });
  }

  test(
    'preparing QCF does not alter existing scan or audio packages',
    () async {
      await prepare(package: 'scan');
      await prepare(package: 'audio');
      await database.update('offline_package_items', {
        'status': 'ready',
        'downloaded_bytes': 100,
      });
      await prepare(package: 'qcf');
      final old = await database.query(
        'offline_package_items',
        where: 'package_id != ?',
        whereArgs: ['qcf'],
      );
      expect(old, hasLength(2));
      expect(
        old.every(
          (r) => r['status'] == 'ready' && r['downloaded_bytes'] == 100,
        ),
        isTrue,
      );
    },
  );

  test('failed enclosing transaction rolls back queued items', () async {
    await expectLater(
      database.transaction((transaction) async {
        final batch = transaction.batch();
        enqueueOfflinePackageItem(
          batch,
          packageId: 'qcf',
          itemKey: 'page:1',
          itemNumber: 1,
          fileName: '1.webp',
          localPath: '/offline/1.webp',
          url: 'https://example.test/1',
          checksum: 'a',
          sizeBytes: 100,
          metadata: '{}',
          updatedAt: 'now',
        );
        await batch.commit(noResult: true);
        throw StateError('publication interrupted');
      }),
      throwsStateError,
    );
    expect(await database.query('offline_package_items'), isEmpty);
  });
}
