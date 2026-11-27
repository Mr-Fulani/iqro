import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/offline_package_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _android = '/data/user/0/forum.iqro.app/files';
const _iosBefore =
    '/var/mobile/Containers/Data/Application/AAAA/Library/Application Support';
const _iosAfter =
    '/var/mobile/Containers/Data/Application/BBBB/Library/Application Support';

void main() {
  setUpAll(sqfliteFfiInit);

  group('a saved offline path', () {
    test('is relative to the support folder', () {
      expect(
        offlinePackageItemPath('audio', 'pkg', 'surah-001.mp3'),
        'offline_packages/audio/pkg/surah-001.mp3',
      );
      expect(
        resolveOfflinePackageItemPath(
          _iosAfter,
          'offline_packages/audio/pkg/surah-001.mp3',
        ),
        '$_iosAfter/offline_packages/audio/pkg/surah-001.mp3',
      );
    });

    test('of an earlier version inside the folder stays as it is', () {
      const stored = '$_android/offline_packages/mushaf/pkg/page-001-1.webp';
      expect(resolveOfflinePackageItemPath(_android, stored), stored);
    });

    test('of an earlier version follows a moved app folder', () {
      // An iOS update gives the app a new container; the files move with it.
      expect(
        resolveOfflinePackageItemPath(
          _iosAfter,
          '$_iosBefore/offline_packages/salah/pkg/image.webp',
        ),
        '$_iosAfter/offline_packages/salah/pkg/image.webp',
      );
    });

    test('outside the package folders is refused', () {
      for (final stored in <String>[
        '',
        '../outside.mp3',
        'offline_packages/../outside.mp3',
        'offline_packages/audio/pkg',
        'offline_packages/audio/pkg/folder/file.mp3',
        '/etc/passwd',
        '$_android/must-stay.mp3',
        '/elsewhere/offline_packages/audio/pkg/../../../x/y.mp3',
      ]) {
        expect(
          resolveOfflinePackageItemPath(_android, stored),
          isNull,
          reason: stored,
        );
      }
    });
  });

  test('the migration makes only exact package paths relative', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE offline_packages '
      '(package_id TEXT PRIMARY KEY, package_type TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE offline_package_items (package_id TEXT NOT NULL, '
      'item_key TEXT NOT NULL, file_name TEXT NOT NULL, '
      'local_path TEXT NOT NULL, PRIMARY KEY (package_id, item_key))',
    );
    for (final (id, type) in <(String, String)>[
      ('a1', 'surah_audio'),
      ('m1', 'mushaf_pages'),
      ('s1', 'salah_course'),
      ('x1', 'future_type'),
    ]) {
      await database.insert('offline_packages', <String, Object?>{
        'package_id': id,
        'package_type': type,
      });
    }
    final rows = <(String, String, String, String)>[
      // Saved whole on Android.
      (
        'a1',
        'surah:1',
        'surah-001.mp3',
        '$_android/offline_packages/audio/a1/surah-001.mp3',
      ),
      // Saved whole in an iOS folder that has moved since.
      (
        'm1',
        'page:1',
        'page-001-1.webp',
        '$_iosBefore/offline_packages/mushaf/m1/page-001-1.webp',
      ),
      // Already relative.
      ('s1', 'image:a', 'a.webp', 'offline_packages/salah/s1/a.webp'),
      // Not the row's own package, folder or file: left as it is.
      (
        'a1',
        'surah:2',
        'surah-002.mp3',
        '$_android/offline_packages/audio/b2/surah-002.mp3',
      ),
      (
        'm1',
        'page:2',
        'page-002-1.webp',
        '$_android/mushaf_pages/page-002-1.webp',
      ),
      (
        'm1',
        'page:3',
        'page-003-1.webp',
        '$_android/offline_packages/audio/m1/page-003-1.webp',
      ),
      (
        'x1',
        'item:1',
        'file.bin',
        '$_android/offline_packages/future/x1/file.bin',
      ),
    ];
    for (final (packageId, itemKey, fileName, localPath) in rows) {
      await database.insert('offline_package_items', <String, Object?>{
        'package_id': packageId,
        'item_key': itemKey,
        'file_name': fileName,
        'local_path': localPath,
      });
    }

    Future<Map<String, String>> paths() async => <String, String>{
      for (final row in await database.query('offline_package_items'))
        '${row['package_id']}/${row['item_key']}': row['local_path']! as String,
    };

    await relativizeOfflinePackageItemPaths(database);
    final migrated = await paths();
    expect(migrated, <String, String>{
      'a1/surah:1': 'offline_packages/audio/a1/surah-001.mp3',
      'm1/page:1': 'offline_packages/mushaf/m1/page-001-1.webp',
      's1/image:a': 'offline_packages/salah/s1/a.webp',
      'a1/surah:2': rows[3].$4,
      'm1/page:2': rows[4].$4,
      'm1/page:3': rows[5].$4,
      'x1/item:1': rows[6].$4,
    });

    // Running it again changes nothing.
    await relativizeOfflinePackageItemPaths(database);
    expect(await paths(), migrated);
  });
}
