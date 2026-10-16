import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/cache_maintenance.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Ahead of the wall clock so freshly created directories count as old.
final _now = DateTime.now().toUtc().add(const Duration(days: 30));
final _oldVersion = 'a' * 64;
final _newVersion = 'b' * 64;

void main() {
  sqfliteFfiInit();

  test(
    'removes entries only long after expiry and keeps offline metadata',
    () async {
      final h = await _Harness.create();
      await h.package(
        packageId: 'mushaf-1',
        type: 'mushaf_pages',
        contentKey: 'mushaf-rendition:kfgqpc-hafs',
        localPaths: const [],
      );
      await h.entry(
        'calendar:old',
        expires: _now.subtract(const Duration(days: 61)),
      );
      await h.entry(
        'calendar:recent',
        expires: _now.subtract(const Duration(days: 59)),
      );
      await h.entry(
        'mushaf-rendition:kfgqpc-hafs:page:1',
        expires: _now.subtract(const Duration(days: 400)),
      );
      await h.entry(
        'mushaf-rendition:qcf-v2-hafs:page:1',
        expires: _now.subtract(const Duration(days: 400)),
      );
      await h.entry(
        'mushaf-renditions:https://api.example/',
        expires: _now.subtract(const Duration(days: 400)),
      );

      final report = await h.maintenance().run();

      expect(report!.deletedEntries, 2);
      expect(await h.keys(), {
        'calendar:recent',
        'mushaf-rendition:kfgqpc-hafs:page:1',
        'mushaf-renditions:https://api.example/',
      });
    },
  );

  test('never deletes offline package files, even unreferenced ones', () async {
    final h = await _Harness.create();
    final packageFile = h.file(
      'offline_packages/mushaf/pkg/page-001-1200.webp',
      bytes: 500,
      used: _now.subtract(const Duration(days: 300)),
    );
    // A package item that, for whatever reason, lives inside a cache root.
    final strayItem = h.file(
      'mushaf_pages/kfgqpc-hafs/1/page-002-w1200-0000000000000000.webp',
      bytes: 500,
      used: _now.subtract(const Duration(days: 300)),
    );
    final orphan = h.file(
      'mushaf_pages/kfgqpc-hafs/1/page-003-w1200-0000000000000000.webp',
      bytes: 10,
      used: _now.subtract(const Duration(days: 300)),
    );
    await h.package(
      packageId: 'pkg',
      type: 'mushaf_pages',
      contentKey: 'mushaf-rendition:kfgqpc-hafs',
      localPaths: [packageFile.path, strayItem.path],
    );

    await h.maintenance(limitBytes: 0).run();

    expect(packageFile.existsSync(), isTrue);
    expect(strayItem.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('evicts the least recently used files above the limit', () async {
    final h = await _Harness.create();
    final files = <File>[];
    for (var day = 1; day <= 5; day += 1) {
      final file = h.file(
        'foundation_assets/${'$day' * 64}.ttf',
        bytes: 100,
        used: _now.subtract(Duration(days: 10 - day)),
      );
      await h.entry(
        'foundation-asset:$day',
        expires: _now.add(const Duration(days: 30)),
        payload: {'path': file.path, 'sha256': '$day' * 64, 'bytes': 100},
      );
      files.add(file);
    }
    // Written moments ago: a download in flight is never evicted.
    final inFlight = h.file(
      'foundation_assets/${'f' * 64}.ttf.123.partial',
      bytes: 100,
      used: _now.subtract(const Duration(minutes: 5)),
    );

    final report = await h.maintenance(limitBytes: 300).run();

    expect(files.map((file) => file.existsSync()), [
      false,
      false,
      false,
      true,
      true,
    ]);
    expect(inFlight.existsSync(), isTrue);
    expect(report!.deletedFiles, 3);
    expect(report.freedBytes, 300);
    expect(report.remainingBytes, 300);
  });

  test('a new raster page version clears the previous one', () async {
    final h = await _Harness.create();
    final page = _rasterPage('2026.10', checksum: 'c' * 64);
    final current = h.file(
      p.join(
        mushafPagesDirectory,
        mushafPageCachePath(
          'qcf-v2-hafs',
          MushafPageData.fromJson(page),
          MushafPageData.fromJson(page).assets.single,
        ),
      ),
      bytes: 100,
      used: _now.subtract(const Duration(days: 3)),
    );
    final previous = h.file(
      'mushaf_pages/qcf-v2-hafs/2026.01/page-001-w1200-dddddddddddddddd.webp',
      bytes: 100,
      used: _now.subtract(const Duration(days: 2)),
    );
    await h.entry(
      'mushaf-rendition:qcf-v2-hafs:page:1',
      expires: _now.add(const Duration(days: 30)),
      payload: page,
    );

    await h.maintenance().run();

    expect(current.existsSync(), isTrue);
    expect(previous.existsSync(), isFalse);
    expect(previous.parent.existsSync(), isFalse);
  });

  test(
    'a new Foundation version clears pages and assets of the old one',
    () async {
      final h = await _Harness.create();
      await h.entry(
        'mushaf-renditions:https://api.example/',
        expires: _now.add(const Duration(hours: 1)),
        payload: [
          {'source_id': 5, 'source_checksum_sha256': _newVersion},
        ],
      );
      for (final version in [_oldVersion, _newVersion]) {
        await h.entry(
          'mushaf-rendition:qf-5:page:1:$version:qul-layout-v1:surah-header-v2',
          expires: _now.add(const Duration(days: 30)),
        );
        await h.entry(
          'mushaf-rendition:qf-5:page-index:$version',
          expires: _now.add(const Duration(hours: 1)),
        );
      }
      final oldFont = h.file(
        'foundation_assets/${'1' * 64}.ttf',
        bytes: 100,
        used: _now.subtract(const Duration(days: 2)),
      );
      final newFont = h.file(
        'foundation_assets/${'2' * 64}.ttf',
        bytes: 100,
        used: _now.subtract(const Duration(days: 2)),
      );
      final untaggedFont = h.file(
        'foundation_assets/${'3' * 64}.ttf',
        bytes: 100,
        used: _now.subtract(const Duration(days: 2)),
      );
      for (final (key, file, version) in [
        ('foundation-asset:old', oldFont, _oldVersion),
        ('foundation-asset:new', newFont, _newVersion),
        ('foundation-asset:untagged', untaggedFont, null),
      ]) {
        await h.entry(
          key,
          expires: _now.add(const Duration(days: 30)),
          payload: {
            'path': file.path,
            'sha256': 'x' * 64,
            'bytes': 100,
            'content_version': ?version,
          },
        );
      }

      await h.maintenance().run();

      expect(await h.keys(), {
        'mushaf-renditions:https://api.example/',
        'mushaf-rendition:qf-5:page:1:$_newVersion:qul-layout-v1:surah-header-v2',
        'mushaf-rendition:qf-5:page-index:$_newVersion',
        'foundation-asset:new',
        'foundation-asset:untagged',
      });
      expect(oldFont.existsSync(), isFalse);
      expect(newFont.existsSync(), isTrue);
      expect(untaggedFont.existsSync(), isTrue);
    },
  );

  test('keeps every Foundation version when no catalog is cached', () async {
    final h = await _Harness.create();
    await h.entry(
      'mushaf-rendition:qf-5:page-index:$_oldVersion',
      expires: _now.add(const Duration(hours: 1)),
    );

    await h.maintenance().run();

    expect(await h.keys(), {'mushaf-rendition:qf-5:page-index:$_oldVersion'});
  });

  test('runs at most once per interval unless forced', () async {
    final h = await _Harness.create();
    expect(await h.maintenance().run(), isNotNull);
    expect(await h.maintenance().run(), isNull);
    expect(await h.maintenance().run(force: true), isNotNull);
    expect(
      await h.maintenance(now: _now.add(const Duration(days: 1))).run(),
      isNotNull,
    );
  });

  test(
    'touching a cached file refreshes a stale stamp at most daily',
    () async {
      final h = await _Harness.create();
      final file = h.file(
        'foundation_assets/font.ttf',
        bytes: 1,
        used: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(await touchCachedFile(file), isTrue);
      expect(await touchCachedFile(file), isFalse);
      expect(
        DateTime.now().difference(file.lastModifiedSync()),
        lessThan(const Duration(minutes: 1)),
      );
    },
  );
}

Map<String, Object?> _rasterPage(String version, {required String checksum}) =>
    <String, Object?>{
      'edition_code': 'qcf-v2-hafs',
      'number': 1,
      'content_version': version,
      'checksum_sha256': checksum,
      'assets': [
        {
          'url': 'https://media.iqro.forum/mushaf/page-001.webp',
          'width': 1200,
          'height': 1840,
          'bytes': 100,
          'sha256': checksum,
        },
      ],
    };

class _Harness {
  _Harness(this.raw, this.database, this.support);

  final Database raw;
  final LocalDatabase database;
  final Directory support;

  static Future<_Harness> create() async {
    final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await raw.execute('''
      CREATE TABLE cache_entries (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        etag TEXT,
        updated_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
    await raw.execute('''
      CREATE TABLE device_state (
        state_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await raw.execute('''
      CREATE TABLE offline_packages (
        package_id TEXT PRIMARY KEY,
        package_type TEXT NOT NULL,
        content_key TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await raw.execute('''
      CREATE TABLE offline_package_items (
        package_id TEXT NOT NULL,
        item_key TEXT NOT NULL,
        local_path TEXT NOT NULL,
        PRIMARY KEY (package_id, item_key)
      )
    ''');
    final support = await Directory.systemTemp.createTemp('iqro-cache-');
    addTearDown(() async {
      await raw.close();
      if (await support.exists()) await support.delete(recursive: true);
    });
    return _Harness(raw, LocalDatabase.forTesting(raw), support);
  }

  CacheMaintenance maintenance({int limitBytes = 1 << 30, DateTime? now}) =>
      CacheMaintenance(
        database: database,
        supportDirectory: () async => support,
        clock: () => now ?? _now,
        fileCacheLimitBytes: limitBytes,
      );

  Future<void> entry(
    String key, {
    required DateTime expires,
    Object? payload = const <String, Object?>{},
  }) => raw.insert('cache_entries', <String, Object?>{
    'cache_key': key,
    'payload': jsonEncode(payload),
    'updated_at': _now.toIso8601String(),
    'expires_at': expires.toIso8601String(),
  });

  Future<void> package({
    required String packageId,
    required String type,
    required String contentKey,
    required List<String> localPaths,
  }) async {
    await raw.insert('offline_packages', <String, Object?>{
      'package_id': packageId,
      'package_type': type,
      'content_key': contentKey,
      'status': 'ready',
    });
    for (final (index, path) in localPaths.indexed) {
      await raw.insert('offline_package_items', <String, Object?>{
        'package_id': packageId,
        'item_key': 'page:$index',
        'local_path': path,
      });
    }
  }

  File file(String relative, {required int bytes, required DateTime used}) {
    final file = File(p.join(support.path, relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(bytes, 1));
    file.setLastModifiedSync(used);
    return file;
  }

  Future<Set<String>> keys() async => {
    for (final row in await raw.query('cache_entries', columns: ['cache_key']))
      row['cache_key']! as String,
  };
}
