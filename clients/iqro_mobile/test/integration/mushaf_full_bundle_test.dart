import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_scan_layout.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['IQRO_MUSHAF_FULL_BUNDLE_DIR'];
  test(
    'complete native bundle: 604 pages, canonical hits, all raster decoders',
    () async {
      final manifestBytes = await File('$root/manifest.json').readAsBytes();
      final checksumFile = await File('$root/manifest.sha256').readAsString();
      expect(checksumFile, '${sha256.convert(manifestBytes)}  manifest.json\n');
      final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
      expect(manifest['publication_scope'], 'staging');
      expect(
        manifest['edition'],
        anyOf('qcf-v2-hafs', 'kfgqpc-hafs', 'qcf-v4-tajweed-hafs'),
      );
      final pages = (manifest['pages'] as List).cast<Map>();
      expect(pages.map((p) => p['page']), List.generate(604, (i) => i + 1));
      final verses = <String>{};
      for (final entry in pages) {
        final geometry = entry['geometry'] as Map;
        final bytes = await File('$root/${geometry['path']}').readAsBytes();
        expect(sha256.convert(bytes).toString(), geometry['sha256']);
        final raw = Map<String, Object?>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
        final page = MushafPageData.fromJson({
          ...raw,
          'edition_code': manifest['edition'],
        });
        for (final size in [const Size(360, 720), const Size(800, 1280)]) {
          final layout = MushafScanLayout.page(
            page: page,
            size: size,
            portrait: size.width == 360,
          );
          for (final region in page.regions) {
            final source = Offset(
              region.x + region.width / 2,
              region.y + region.height / 2,
            );
            final point = layout.sourcePointAt(layout.displayPoint(source))!;
            final hit = page.ayahAt(point.dx, point.dy)!;
            expect(
              (hit.surah, hit.ayah),
              (region.ayah.surah, region.ayah.ayah),
              reason: 'page ${page.number}',
            );
            verses.add('${hit.surah}:${hit.ayah}');
          }
        }
        for (final asset in (entry['assets'] as List).cast<Map>()) {
          final data = await File('$root/${asset['path']}').readAsBytes();
          expect(data.length, asset['bytes']);
          expect(sha256.convert(data).toString(), asset['sha256']);
          final codec = await ui.instantiateImageCodec(data);
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, asset['width']);
            expect(frame.image.height, asset['height']);
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
      }
      expect(verses.length, 6236);
    },
    skip: root == null
        ? 'Set IQRO_MUSHAF_FULL_BUNDLE_DIR for full source QA'
        : false,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
