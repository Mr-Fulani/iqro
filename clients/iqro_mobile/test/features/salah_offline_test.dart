import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';
import 'package:iqro_mobile/features/salah/salah_offline_repository.dart';
import 'package:iqro_mobile/features/settings/offline_storage_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('manifest', () {
    test('accepts the checksum the backend computes', () {
      // A manifest as served by the local backend.
      final manifest = OfflineSalahManifest.fromJson(
        jsonDecode(_backendManifest) as Map<String, Object?>,
        slug: 'hanbali-umdah',
        language: 'ru',
        localApiBase: Uri.parse('http://localhost:8000/api/v1'),
      );

      expect(manifest.packageId, 'salah-hanbali-umdah-ru');
      expect(manifest.version, '2026-10-18-local-3');
      expect(manifest.totalBytes, 3640);
      expect(manifest.images.single.key, 'position-qiyam');
      expect(
        manifest.images.single.fileName,
        'position-qiyam-e67f71e3a988.webp',
      );
    });

    test('parses the images of the requested course and language', () {
      final manifest = OfflineSalahManifest.fromJson(
        _manifest(<_Image>[_image('qiyam', 1), _image('ruku', 2)]),
        slug: 'hanbali-umdah',
        language: 'ru',
      );

      expect(manifest.images.map((image) => image.key), <String>[
        'qiyam',
        'ruku',
      ]);
      expect(manifest.computedChecksum, manifest.packageChecksum);
      expect(
        () => OfflineSalahManifest.fromJson(
          _manifest(<_Image>[_image('qiyam', 1)]),
          slug: 'hanbali-umdah',
          language: 'en',
        ),
        throwsFormatException,
      );
    });

    test('rejects tampering, foreign hosts and a wrong total', () {
      final tampered = _manifest(<_Image>[_image('qiyam', 1)]);
      final asset =
          ((tampered['items']! as List).single as Map)['asset']
              as Map<String, Object?>;
      asset['sha256'] = 'f' * 64;
      expect(() => _parse(tampered), throwsFormatException);

      final foreign = _manifest(<_Image>[
        _image('qiyam', 1, host: 'example.com'),
      ]);
      expect(() => _parse(foreign), throwsFormatException);

      final total = _manifest(<_Image>[_image('qiyam', 1)]);
      total['total_bytes'] = 1;
      expect(() => _parse(total), throwsFormatException);

      final empty = _manifest(const <_Image>[]);
      expect(() => _parse(empty), throwsFormatException);
    });
  });

  test('a downloaded picture is shown from its file', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        salahOfflineImagesProvider.overrideWith(
          (ref, slug) async => <String, String>{'a' * 64: '/pictures/a.webp'},
        ),
        salahImageProvider.overrideWithValue((url) => NetworkImage(url)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(salahOfflineImagesProvider('hanbali-umdah').future);
    final image = container.read(salahCourseImageProvider('hanbali-umdah'));

    final local = image(
      SalahMedia(
        key: 'qiyam',
        url: 'https://media.iqro.forum/qiyam.webp',
        width: 1,
        height: 1,
        sha256: 'a' * 64,
      ),
    );
    final remote = image(
      SalahMedia(
        key: 'ruku',
        url: 'https://media.iqro.forum/ruku.webp',
        width: 1,
        height: 1,
        sha256: 'b' * 64,
      ),
    );

    expect(local, isA<FileImage>());
    expect((local as FileImage).file.path, '/pictures/a.webp');
    expect(remote, isA<NetworkImage>());
    expect((remote as NetworkImage).url, 'https://media.iqro.forum/ruku.webp');
  });

  group('repository', () {
    test('downloads, verifies and registers the course pictures', () async {
      final harness = await _harness();
      final qiyam = _image('qiyam', 1);
      final ruku = _image('ruku', 2);
      harness.gateway.publish(<_Image>[qiyam, ruku]);

      expect(
        (await harness.repository.snapshot('hanbali-umdah', 'ru')).status,
        SalahOfflineStatus.notDownloaded,
      );
      final estimate = await harness.repository.check('hanbali-umdah', 'ru');
      expect(estimate.status, SalahOfflineStatus.notDownloaded);
      expect(estimate.totalBytes, qiyam.bytes.length + ruku.bytes.length);
      expect(estimate.totalItems, 2);

      final progress = <SalahOfflineSnapshot>[];
      final installed = await harness.repository.install(
        'hanbali-umdah',
        'ru',
        onProgress: progress.add,
      );

      expect(installed.status, SalahOfflineStatus.ready);
      expect(progress.map((item) => item.status).toSet(), <SalahOfflineStatus>{
        SalahOfflineStatus.downloading,
        SalahOfflineStatus.ready,
      });
      expect(progress.last.progress, 1);
      final directory = p.join(
        harness.support.path,
        'offline_packages',
        'salah',
        'salah-hanbali-umdah-ru',
      );
      expect(
        await File(p.join(directory, qiyam.fileName)).readAsBytes(),
        qiyam.bytes,
      );
      expect(await harness.repository.localImages('hanbali-umdah', 'ru'), {
        qiyam.sha256: p.join(directory, qiyam.fileName),
        ruku.sha256: p.join(directory, ruku.fileName),
      });
      expect(
        await harness.repository.localImages('hanbali-umdah', 'en'),
        isEmpty,
      );

      final stored = await harness.repository.check('hanbali-umdah', 'ru');
      expect(stored.status, SalahOfflineStatus.ready);

      final packages = await harness.storage.packages();
      expect(packages.single.isSalah, isTrue);
      expect(packages.single.contentKey, 'salah:hanbali-umdah:ru');
      expect(packages.single.status, 'ready');
      expect(packages.single.usedBytes, installed.totalBytes);
    });

    test('rejects a picture whose SHA-256 does not match', () async {
      final harness = await _harness();
      final qiyam = _image('qiyam', 1);
      harness.gateway.publish(<_Image>[qiyam]);
      harness.gateway.files[qiyam.url] = _webpBytes(9);

      await expectLater(
        harness.repository.install('hanbali-umdah', 'ru'),
        throwsFormatException,
      );

      final snapshot = await harness.repository.snapshot('hanbali-umdah', 'ru');
      expect(snapshot.status, SalahOfflineStatus.failed);
      expect(snapshot.error, contains('integrity'));
      expect(
        await harness.repository.localImages('hanbali-umdah', 'ru'),
        isEmpty,
      );
      expect(
        await File(
          p.join(
            harness.support.path,
            'offline_packages',
            'salah',
            'salah-hanbali-umdah-ru',
            qiyam.fileName,
          ),
        ).exists(),
        isFalse,
      );
    });

    test('a new version is outdated and updates only what changed', () async {
      final harness = await _harness();
      final qiyam = _image('qiyam', 1);
      final ruku = _image('ruku', 2);
      harness.gateway.publish(<_Image>[qiyam, ruku]);
      await harness.repository.install('hanbali-umdah', 'ru');
      harness.gateway.downloads.clear();

      final sujud = _image('sujud', 3);
      harness.gateway.publish(<_Image>[qiyam, sujud], version: '2');
      final outdated = await harness.repository.check('hanbali-umdah', 'ru');
      expect(outdated.status, SalahOfflineStatus.outdated);
      expect(outdated.version, '1');
      expect(outdated.totalBytes, qiyam.bytes.length + sujud.bytes.length);

      await harness.repository.install('hanbali-umdah', 'ru');

      expect(harness.gateway.downloads, <Uri>[sujud.url]);
      final images = await harness.repository.localImages(
        'hanbali-umdah',
        'ru',
      );
      expect(
        images.keys,
        unorderedEquals(<String>[qiyam.sha256, sujud.sha256]),
      );
      expect(await File(images[qiyam.sha256]!).exists(), isTrue);
      final directory = Directory(p.dirname(images[qiyam.sha256]!));
      expect(
        await directory.list().map((entity) => p.basename(entity.path)).toSet(),
        <String>{qiyam.fileName, sujud.fileName},
      );
      final updated = await harness.repository.check('hanbali-umdah', 'ru');
      expect(updated.status, SalahOfflineStatus.ready);
      expect(updated.version, '2');
    });

    test('a checksum change with the same version is outdated', () async {
      final harness = await _harness();
      harness.gateway.publish(<_Image>[_image('qiyam', 1)]);
      await harness.repository.install('hanbali-umdah', 'ru');

      harness.gateway.publish(<_Image>[_image('qiyam', 4)]);

      expect(
        (await harness.repository.check('hanbali-umdah', 'ru')).status,
        SalahOfflineStatus.outdated,
      );
    });

    test('delete removes the files and the registration', () async {
      final harness = await _harness();
      harness.gateway.publish(<_Image>[_image('qiyam', 1)]);
      await harness.repository.install('hanbali-umdah', 'ru');
      final directory = Directory(
        p.join(
          harness.support.path,
          'offline_packages',
          'salah',
          'salah-hanbali-umdah-ru',
        ),
      );
      expect(await directory.exists(), isTrue);

      await harness.repository.delete('hanbali-umdah', 'ru');

      expect(await directory.exists(), isFalse);
      expect(
        (await harness.repository.snapshot('hanbali-umdah', 'ru')).status,
        SalahOfflineStatus.notDownloaded,
      );
      expect(
        await harness.repository.localImages('hanbali-umdah', 'ru'),
        isEmpty,
      );
      expect(await harness.storage.packages(), isEmpty);
    });

    test('a picture removed from disk falls back to the network', () async {
      final harness = await _harness();
      final qiyam = _image('qiyam', 1);
      harness.gateway.publish(<_Image>[qiyam]);
      await harness.repository.install('hanbali-umdah', 'ru');
      final images = await harness.repository.localImages(
        'hanbali-umdah',
        'ru',
      );

      await File(images[qiyam.sha256]!).delete();

      expect(
        await harness.repository.localImages('hanbali-umdah', 'ru'),
        isEmpty,
      );
    });
  });
}

OfflineSalahManifest _parse(Map<String, Object?> json) =>
    OfflineSalahManifest.fromJson(json, slug: 'hanbali-umdah', language: 'ru');

class _Image {
  _Image(this.key, this.bytes, {required this.host});

  final String key;
  final List<int> bytes;
  final String host;

  String get sha256 => crypto.sha256.convert(bytes).toString();
  String get fileName => '$key-${sha256.substring(0, 12)}.webp';
  Uri get url => Uri.parse('https://$host/salah/hanbali-umdah/$fileName');
}

_Image _image(String key, int marker, {String host = 'media.iqro.forum'}) =>
    _Image(key, _webpBytes(marker), host: host);

Map<String, Object?> _manifest(List<_Image> images, {String version = '1'}) {
  final sourceChecksum = 'a' * 64;
  final provisional = OfflineSalahManifest(
    slug: 'hanbali-umdah',
    language: 'ru',
    version: version,
    packageChecksum: '',
    sourceChecksum: sourceChecksum,
    totalBytes: 0,
    images: <OfflineSalahImage>[
      for (final image in images)
        OfflineSalahImage(
          key: image.key,
          url: image.url,
          fileName: image.fileName,
          bytes: image.bytes.length,
          sha256: image.sha256,
        ),
    ],
    raw: const <String, Object?>{},
  );
  return <String, Object?>{
    'schema_version': 1,
    'package_type': 'salah_course',
    'package_id': 'hanbali-umdah:ru',
    'version': version,
    'source_checksum_sha256': sourceChecksum,
    'package_checksum_sha256': provisional.computedChecksum,
    'published_at': '2026-10-18T00:00:00+00:00',
    'total_bytes': images.fold<int>(
      0,
      (sum, image) => sum + image.bytes.length,
    ),
    'items': <Object?>[
      for (final image in images)
        <String, Object?>{
          'key': image.key,
          'asset': <String, Object?>{
            'url': image.url.toString(),
            'file_name': image.fileName,
            'content_type': 'image/webp',
            'bytes': image.bytes.length,
            'sha256': image.sha256,
          },
        },
    ],
  };
}

class _FakeGateway implements SalahOfflineGateway {
  Map<String, Object?>? manifestJson;
  final files = <Uri, List<int>>{};
  final downloads = <Uri>[];

  void publish(List<_Image> images, {String version = '1'}) {
    manifestJson = _manifest(images, version: version);
    for (final image in images) {
      files[image.url] = image.bytes;
    }
  }

  @override
  Uri? get localApiBase => null;

  @override
  Future<Object?> manifest(String slug, String language) async {
    if (slug != 'hanbali-umdah' || language != 'ru') {
      throw const SocketException('not published');
    }
    return jsonDecode(jsonEncode(manifestJson));
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    required int expectedBytes,
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(url);
    final bytes = files[url]!;
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
    onProgress?.call(bytes.length, expectedBytes);
  }
}

class _Harness {
  _Harness(this.repository, this.storage, this.gateway, this.support);

  final SalahOfflineRepository repository;
  final OfflineStorageRepository storage;
  final _FakeGateway gateway;
  final Directory support;
}

Future<_Harness> _harness() async {
  final support = await Directory.systemTemp.createTemp('iqro-salah-test-');
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
  final gateway = _FakeGateway();
  addTearDown(() async {
    await raw.close();
    if (await support.exists()) await support.delete(recursive: true);
  });
  return _Harness(
    SalahOfflineRepository(
      gateway: gateway,
      database: database,
      supportDirectory: () async => support,
    ),
    OfflineStorageRepository(
      database: database,
      supportDirectory: () async => support,
    ),
    gateway,
    support,
  );
}

List<int> _webpBytes(int marker) => <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0,
  0,
  0,
  0,
  0x57,
  0x45,
  0x42,
  0x50,
  marker,
  1,
  2,
  3,
];

const _backendManifest = '''
{"schema_version":1,"package_type":"salah_course","package_id":"hanbali-umdah:ru","version":"2026-10-18-local-3","source_checksum_sha256":"c4f473e75bfc564aa79e0d14015c2e8af87e8a406780c65a6a36d2966fcd401b","items":[{"key":"position-qiyam","asset":{"url":"http://localhost:8000/media/salah/hanbali-umdah/2026-10-18-local-3/position-qiyam-e67f71e3a988.webp","file_name":"position-qiyam-e67f71e3a988.webp","content_type":"image/webp","bytes":3640,"sha256":"e67f71e3a988efa13c0767d84609f37eb49686227219d955acab72fc67b6f5e5"}}],"package_checksum_sha256":"d55da5516f2fd31b59a57cf499efbe16a4e6db6f9a2d73bfb933c8211acfb96b","published_at":"2026-10-18T14:06:36.903134+00:00","total_bytes":3640}
''';
