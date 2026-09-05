import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_ayah_excerpt.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

void main() {
  test(
    'excerpt covers every page in reading order and uses high resolution',
    () async {
      final repository = _Repository();
      final result = await loadMushafExcerpt(
        repository: repository,
        ayah: _ayah,
        tappedPage: 4,
        pixelWidth: 1080,
      );
      expect(result.map((r) => r.page.number), <int>[3, 4]);
      expect(repository.widths, <int>[2700, 2700]);
      expect(result.first.regions.map((r) => r.readingOrder), <int>[1, 2]);
      expect(
        result.every((r) => r.regions.every((r) => r.ayah.ayah == 7)),
        isTrue,
      );
    },
  );

  test(
    'missing continuation fails rather than silently truncating the ayah',
    () async {
      await expectLater(
        loadMushafExcerpt(
          repository: _Repository(missingContinuation: true),
          ayah: _ayah,
          tappedPage: 3,
          pixelWidth: 1080,
        ),
        throwsFormatException,
      );
    },
  );

  test('mixed content versions cannot form one excerpt', () async {
    await expectLater(
      loadMushafExcerpt(
        repository: _Repository(mixedVersion: true),
        ayah: _ayah,
        tappedPage: 3,
        pixelWidth: 1080,
      ),
      throwsFormatException,
    );
  });
}

const _ayah = QuranAyah(
  id: '2:7',
  surahNumber: 2,
  number: 7,
  textUthmani: 'نص',
  pages: <int>[4, 3],
);

class _Repository implements QuranRepository {
  _Repository({this.missingContinuation = false, this.mixedVersion = false});
  final bool missingContinuation;
  final bool mixedVersion;
  final widths = <int>[];

  @override
  Future<MushafPageData> mushafPage(
    int number, {
    bool forceRefresh = false,
  }) async => MushafPageData(
    number: number,
    contentVersion: mixedVersion && number == 4 ? 'v2' : 'v1',
    checksumSha256: '',
    imageWidth: 900,
    imageHeight: 1380,
    assets: const <MushafAsset>[
      MushafAsset(url: 'https://example.test/900.webp', width: 900, sha256: ''),
      MushafAsset(
        url: 'https://example.test/2700.webp',
        width: 2700,
        sha256: '',
      ),
    ],
    regions: <MushafAyahRegion>[
      for (final order in <int>[2, 1, 3])
        if (!(missingContinuation && number == 4))
          MushafAyahRegion(
            id: '$order',
            ayah: QuranAyahReference(
              id: '',
              surah: 2,
              ayah: order == 3 ? 8 : 7,
            ),
            readingOrder: order,
            polygon: const [],
            x: .1,
            y: .1 * order,
            width: .8,
            height: .1,
          ),
    ],
  );

  @override
  Future<File> cachedMushafPageAsset(
    MushafPageData page,
    MushafAsset asset,
  ) async {
    widths.add(asset.width);
    return File('test-page-${page.number}.webp');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
