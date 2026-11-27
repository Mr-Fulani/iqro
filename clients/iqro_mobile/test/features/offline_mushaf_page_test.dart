import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  // A WebP header, as the page check reads it, and some bytes.
  final bytes = <int>[
    ...'RIFF'.codeUnits,
    24,
    0,
    0,
    0,
    ...'WEBPVP8 '.codeUnits,
    ...List<int>.filled(16, 7),
  ];
  final checksum = sha256.convert(bytes).toString();
  const relative = 'offline_packages/mushaf/mushaf-pkg/page-001-1200.webp';

  final savedPaths = <String, String Function(String support)>{
    'a relative path': (_) => relative,
    'the full path of this folder': (support) => '$support/$relative',
    // Saved before an iOS update gave the app a new folder.
    'the full path of a moved folder': (_) =>
        '/var/mobile/Containers/Data/Application/OLD/Library/'
        'Application Support/$relative',
  };

  savedPaths.forEach((name, savedPath) {
    test('a downloaded page is read offline from $name', () async {
      final support = await Directory.systemTemp.createTemp('iqro-mushaf-');
      addTearDown(() => support.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => support.path,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final file = File(p.join(support.path, relative));
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);

      final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(raw.close);
      await raw.execute(
        'CREATE TABLE offline_packages (package_id TEXT PRIMARY KEY, '
        'package_type TEXT NOT NULL, content_key TEXT NOT NULL, '
        'status TEXT NOT NULL, is_active INTEGER NOT NULL)',
      );
      await raw.execute(
        'CREATE TABLE offline_package_items (package_id TEXT NOT NULL, '
        'item_key TEXT NOT NULL, item_number INTEGER NOT NULL, '
        'file_name TEXT NOT NULL, local_path TEXT NOT NULL, '
        'checksum_sha256 TEXT NOT NULL, size_bytes INTEGER NOT NULL, '
        'status TEXT NOT NULL)',
      );
      await raw.insert('offline_packages', <String, Object?>{
        'package_id': 'mushaf-pkg',
        'package_type': 'mushaf_pages',
        'content_key': MushafIdentity.primary.contentKey,
        'status': 'ready',
        'is_active': 1,
      });
      await raw.insert('offline_package_items', <String, Object?>{
        'package_id': 'mushaf-pkg',
        'item_key': 'page:1',
        'item_number': 1,
        'file_name': 'page-001-1200.webp',
        'local_path': savedPath(support.path),
        'checksum_sha256': checksum,
        'size_bytes': bytes.length,
        'status': 'ready',
      });
      final repository = QuranRepository(
        api: _NoNetwork(),
        database: LocalDatabase.forTesting(raw),
      );
      final asset = MushafAsset(
        url: 'https://media.iqro.forum/mushaf/page-001.webp',
        width: 1200,
        sha256: checksum,
        bytes: bytes.length,
      );

      final found = await repository.cachedMushafPageAsset(
        MushafPageData(
          number: 1,
          contentVersion: 'v1',
          checksumSha256: checksum,
          imageWidth: 1200,
          imageHeight: 1840,
          assets: <MushafAsset>[asset],
          regions: const <MushafAyahRegion>[],
        ),
        asset,
      );

      expect(found.path, file.path);
    });
  });
}

class _NoNetwork implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('The page must come from the download');
}
