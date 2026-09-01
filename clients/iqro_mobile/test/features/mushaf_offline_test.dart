import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';

void main() {
  test('offline Mushaf manifest verifies coverage and canonical checksum', () {
    final fixture = _manifestFixture();

    final manifest = OfflineMushafManifest.fromJson(fixture);

    expect(manifest.packageId, 'quran-edition-madani-hafs-1.0.0-w1024');
    expect(manifest.pages.map((page) => page.number), <int>[1, 2]);
    expect(manifest.computedChecksum, manifest.packageChecksum);

    final tampered = Map<String, Object?>.from(
      jsonDecode(jsonEncode(fixture)) as Map,
    );
    final pages = (tampered['pages']! as List).cast<Map<String, Object?>>();
    final metadata = pages.first['metadata']! as Map<String, Object?>;
    metadata['image_width'] = 999;
    expect(
      () => OfflineMushafManifest.fromJson(tampered),
      throwsFormatException,
    );
  });

  test('offline Mushaf manifest rejects gaps and unapproved asset hosts', () {
    final gap = _manifestFixture();
    final gapPages = (gap['pages']! as List).cast<Map<String, Object?>>();
    gapPages[1]['number'] = 3;
    expect(() => OfflineMushafManifest.fromJson(gap), throwsFormatException);

    final external = _manifestFixture();
    final pages = (external['pages']! as List).cast<Map<String, Object?>>();
    final asset = pages.first['asset']! as Map<String, Object?>;
    asset['url'] = 'https://example.com/page-001.webp';
    expect(
      () => OfflineMushafManifest.fromJson(external),
      throwsFormatException,
    );
  });

  test(
    'downloaded Mushaf page must match WebP signature, size and SHA-256',
    () async {
      final bytes = _webpBytes(1);
      final directory = await Directory.systemTemp.createTemp(
        'iqro-mushaf-test-',
      );
      final file = File('${directory.path}/page-001-1024.webp');
      await file.writeAsBytes(bytes);
      final page = OfflineMushafPage(
        number: 1,
        url: Uri.parse('https://media.iqro.forum/page-001.webp'),
        fileName: 'page-001-1024.webp',
        width: 1024,
        height: 1536,
        bytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        metadata: const <String, Object?>{},
      );

      expect(await verifyMushafAssetFile(file, page), isTrue);
      await file.writeAsBytes(<int>[...bytes]..[11] = 0x00);
      expect(await verifyMushafAssetFile(file, page), isFalse);

      await directory.delete(recursive: true);
    },
  );
}

Map<String, Object?> _manifestFixture() {
  final pages = <Map<String, Object?>>[_pageFixture(1), _pageFixture(2)];
  final provisional = OfflineMushafManifest(
    packageId: 'quran-edition-madani-hafs-1.0.0-w1024',
    version: '1.0.0',
    packageChecksum: '0' * 64,
    sourceChecksum: 'a' * 64,
    width: 1024,
    totalBytes: pages.fold<int>(
      0,
      (sum, page) => sum + ((page['asset']! as Map)['bytes']! as int),
    ),
    pages: pages.map(_offlinePageFromFixture).toList(growable: false),
    raw: const <String, Object?>{},
  );
  return <String, Object?>{
    'schema_version': 1,
    'package_type': 'mushaf_pages',
    'package_id': provisional.packageId,
    'version': provisional.version,
    'package_checksum_sha256': provisional.computedChecksum,
    'source': <String, Object?>{
      'name': 'Test',
      'url': '',
      'checksum_sha256': provisional.sourceChecksum,
    },
    'rights': const <String, Object?>{'offline_download': true},
    'mushaf': const <String, Object?>{'edition_code': 'madani-hafs'},
    'width': provisional.width,
    'page_count': pages.length,
    'total_bytes': provisional.totalBytes,
    'pages': pages,
  };
}

Map<String, Object?> _pageFixture(int number) {
  final bytes = _webpBytes(number);
  final asset = <String, Object?>{
    'url':
        'https://media.staging.iqro.forum/quran/page-${number.toString().padLeft(3, '0')}.webp',
    'file_name': 'page-${number.toString().padLeft(3, '0')}-1024.webp',
    'content_type': 'image/webp',
    'width': 1024,
    'height': 1536,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
  };
  return <String, Object?>{
    'number': number,
    'metadata_url': 'https://staging.iqro.forum/api/v1/quran/pages/$number',
    'asset': asset,
    'metadata': <String, Object?>{
      'number': number,
      'content_version': '1.0.0',
      'checksum_sha256': 'a' * 64,
      'image_width': 1024,
      'image_height': 1536,
      'assets': <Object?>[asset],
      'regions': const <Object?>[],
    },
  };
}

OfflineMushafPage _offlinePageFromFixture(Map<String, Object?> page) {
  final asset = page['asset']! as Map<String, Object?>;
  return OfflineMushafPage(
    number: page['number']! as int,
    url: Uri.parse(asset['url']! as String),
    fileName: asset['file_name']! as String,
    width: asset['width']! as int,
    height: asset['height']! as int,
    bytes: asset['bytes']! as int,
    sha256: asset['sha256']! as String,
    metadata: page['metadata']! as Map<String, Object?>,
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
