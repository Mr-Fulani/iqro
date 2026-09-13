import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  final origin = Platform.environment['IQRO_LOCAL_API_URL'];
  test(
    'local backend delivers a complete portable manifest and decodable pages',
    () async {
      final config = AppConfig.validate(
        apiBaseUrl: origin!,
        environment: 'local',
        fallbackDownloadUrl: 'https://iqro.forum',
        releaseMode: false,
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      Future<Uint8List> get(Uri uri) async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: uri.toString());
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      }

      Future<Object?> json(String path) async =>
          jsonDecode(utf8.decode(await get(Uri.parse('${config.apiV1}$path'))));

      try {
        final catalog = (await json('/quran/mushaf-renditions'))! as List;
        expect(
          catalog
              .cast<Map>()
              .map(
                (item) =>
                    NativeMushafEdition.parse(Map<String, Object?>.from(item)),
              )
              .whereType<NativeMushafEdition>()
              .map((edition) => edition.identity.code),
          contains('kfgqpc-hafs'),
        );
        final raw = Map<String, Object?>.from(
          (await json(
                '/quran/mushaf-renditions/kfgqpc-hafs/offline-manifest?width=720',
              ))!
              as Map,
        );
        final manifest = OfflineMushafManifest.fromJson(
          raw,
          localApiBase: Uri.parse(config.apiV1),
        );
        expect(manifest.pages, hasLength(604));
        expect(manifest.computedChecksum, manifest.packageChecksum);
        final ayahIds = <String>{};
        for (final page in manifest.pages) {
          expect(page.url.origin, config.apiBaseUrl);
          final metadata = MushafPageData.fromJson(page.metadata);
          ayahIds.addAll(metadata.regions.map((region) => region.ayah.id));
        }
        expect(ayahIds, hasLength(6236));
        for (final page in [manifest.pages.first, manifest.pages.last]) {
          final metadata = MushafPageData.fromJson(
            Map<String, Object?>.from(
              (await json(
                    '/quran/mushaf-renditions/kfgqpc-hafs/pages/${page.number}',
                  ))!
                  as Map,
            ),
          );
          expect(metadata.number, page.number);
          expect(metadata.regions, isNotEmpty);
          final bytes = await get(page.url);
          expect(bytes.length, page.bytes);
          expect(sha256.convert(bytes).toString(), page.sha256);
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, page.width);
            expect(frame.image.height, page.height);
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
      } finally {
        client.close(force: true);
      }
    },
    skip: origin == null ? 'Set IQRO_LOCAL_API_URL after make dev-data' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
