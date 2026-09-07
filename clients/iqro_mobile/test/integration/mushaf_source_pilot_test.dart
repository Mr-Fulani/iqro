// Opt-in source QA; the draft bundle is never included in the application APK.
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
  final root = Platform.environment['IQRO_MUSHAF_PILOT_DIR'];
  final skip = root == null
      ? 'Set IQRO_MUSHAF_PILOT_DIR to the verified offline raster pilot'
      : false;
  for (final number in <int>[1, 2, 3, 50, 255, 604]) {
    test(
      'QCF V2 pilot $number: geometry survives portrait/landscape',
      () async {
        final bundle = await _entry(root!, number);
        final geometry = Map<String, Object?>.from(bundle['geometry']! as Map);
        final bytes = await File('$root/${geometry['path']}').readAsBytes();
        expect(sha256.convert(bytes).toString(), geometry['sha256']);
        final json = Map<String, Object?>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
        expect(json['status'], 'draft');
        expect(json['edition'], 'qcf-v2-hafs-jmapps-pilot');
        final page = MushafPageData.fromJson(json);
        expect(page.number, number);
        expect(page.assets, isEmpty); // No invented public URLs or readiness.
        expect(page.regions, isNotEmpty);
        for (final size in const <Size>[
          Size(360, 720),
          Size(800, 1280),
          Size(
            360,
            720,
          ), // Same source coordinates after returning to portrait.
        ]) {
          final layout = MushafScanLayout.page(
            page: page,
            size: size,
            portrait: size.width == 360,
          );
          for (final band in layout.bands) {
            final scaleX =
                band.destination.width / (band.source.width * page.imageWidth);
            final scaleY =
                band.destination.height /
                (band.source.height * page.imageHeight);
            expect(scaleX, closeTo(scaleY, .000001));
          }
          for (final region in page.regions) {
            final source = Offset(
              region.x + region.width / 2,
              region.y + region.height / 2,
            );
            final displayed = layout.displayPoint(source);
            final restored = layout.sourcePointAt(displayed)!;
            final hit = page.ayahAt(restored.dx, restored.dy)!;
            expect(
              (hit.surah, hit.ayah),
              (region.ayah.surah, region.ayah.ayah),
            );
            expect(restored.dx, closeTo(source.dx, .000001));
            expect(restored.dy, closeTo(source.dy, .000001));
            expect(layout.regionPath(region).contains(displayed), isTrue);
          }
        }
      },
      skip: skip,
    );

    test(
      'QCF V2 pilot $number: Flutter decodes every verified resolution',
      () async {
        final bundle = await _entry(root!, number);
        final assets = (bundle['assets']! as List).cast<Map>();
        expect(assets.map((a) => a['width']), <int>[720, 1440, 2160]);
        for (final asset in assets) {
          final bytes = await File('$root/${asset['path']}').readAsBytes();
          expect(bytes.length, asset['bytes']);
          expect(sha256.convert(bytes).toString(), asset['sha256']);
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            final frame = await codec.getNextFrame();
            try {
              expect(frame.image.width, asset['width']);
              expect(frame.image.height, asset['height']);
              final pixels = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(pixels, isNotNull);
              final rgba = pixels!.buffer.asUint8List();
              var ink = 0;
              for (var index = 0; index < rgba.length; index += 4) {
                if (rgba[index] < 128 && rgba[index + 3] > 128) ink++;
              }
              expect(
                ink,
                greaterThan(frame.image.width * frame.image.height * .005),
              );
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
      },
      skip: skip,
    );
  }
}

Future<Map<String, Object?>> _entry(String root, int page) async {
  final manifest =
      jsonDecode(await File('$root/manifest.json').readAsString()) as Map;
  expect(manifest['status'], 'draft');
  expect(manifest['publication_approved'], isFalse);
  expect(manifest['source_commit'], '1d040f68d284f8e6db515157f8425abfefd78df6');
  return Map<String, Object?>.from(
    (manifest['pages'] as List).cast<Map>().singleWhere(
      (entry) => entry['page'] == page,
    ),
  );
}
