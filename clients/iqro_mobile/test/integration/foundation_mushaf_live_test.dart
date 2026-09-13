import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  final origin = Platform.environment['IQRO_LOCAL_API_URL'];
  final output = Platform.environment['IQRO_MUSHAF_VISUAL_OUTPUT'];
  // Created before testWidgets installs its mock HTTP client.
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all QF layouts load official assets and paint selectable words',
    () async {
      final root = Directory(output!);
      await root.create(recursive: true);
      debugPrint("Foundation live: loading catalog");
      Future<Uint8List> get(Uri uri) async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        expect(response.statusCode, 200, reason: uri.toString());
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      }

      Future<Object?> json(String path) async =>
          jsonDecode(utf8.decode(await get(Uri.parse('$origin/api/v1$path'))));
      final catalog = await json('/quran/foundation/mushafs') as List;
      expect(catalog, hasLength(13));
      debugPrint("Foundation live: catalog ready");
      for (final raw in catalog.cast<Map>()) {
        final edition = NativeMushafEdition.fromFoundation(
          Map<String, Object?>.from(raw),
        );
        expect(edition, isNotNull);
        final id = edition!.identity.foundationId!;
        for (final number in [
          1,
          42,
          edition.pagesCount,
          if (id == 6) 304,
          if (id == 7) 274,
        ]) {
          debugPrint("Foundation live: $id page $number");
          final data = MushafPageData.fromFoundation(
            Map<String, Object?>.from(
              (await json('/quran/foundation/mushafs/$id/pages/$number'))
                  as Map,
            ),
          );
          final page = data.foundation!;
          expect(page.words.every((word) => word['verse_key'] != null), isTrue);
          final resources = await loadFoundationPageResources(page, (
            uri,
            version,
          ) async {
            final file = File(
              '${root.path}/asset-${uri.path.replaceAll('/', '_')}',
            );
            final cache = Platform.environment['IQRO_MUSHAF_ASSET_CACHE'];
            if (cache != null) {
              final existing = File(
                '$cache/asset-${uri.path.replaceAll('/', '_')}',
              );
              if (await existing.exists()) return existing;
            }
            if (!await file.exists()) await file.writeAsBytes(await get(uri));
            return file;
          });
          expect(resources, isNotNull);
          const size = Size(360, 552);
          final layout = FoundationPageLayout(page, resources, size, const []);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(2);
          canvas.drawRect(
            Offset.zero & size,
            Paint()..color = const Color(0xfffffef8),
          );
          FoundationPagePainter(layout, null, null).paint(canvas, size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(720, 1104);
          picture.dispose();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          var ink = 0;
          for (var n = 0; n < bytes!.lengthInBytes; n += 4) {
            if (bytes.getUint8(n + 3) > 100 &&
                bytes.getUint8(n) < 180 &&
                bytes.getUint8(n + 1) < 180) {
              ink++;
            }
          }
          expect(
            ink,
            greaterThan(1000),
            reason: 'Blank Mushaf $id page $number',
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${root.path}/flutter-$id-$number.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
          expect(layout.words, hasLength(page.words.length));
          for (final word in layout.words) {
            expect(word.rect.width, greaterThan(0));
            expect(word.rect.left, greaterThanOrEqualTo(-.01));
            expect(word.rect.right, lessThanOrEqualTo(size.width + .01));
            expect(word.rect.top, greaterThanOrEqualTo(-.01));
            expect(word.rect.bottom, lessThanOrEqualTo(size.height + .01));
            expect(page.ayahReferences, contains(word.reference));
          }
          layout.dispose();
          resources.dispose();
        }
      }
      client.close(force: true);
    },
    skip: origin == null || output == null,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
