import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_scan_layout.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  test(
    'portrait distributes safe line gaps, never stretches or drops glyphs',
    () {
      final page = _page(122);
      final layout = MushafScanLayout.page(
        page: page,
        size: const Size(360, 700),
        portrait: true,
        verifiedCuts: mushafLineBoundaries(page.regions),
      );
      expect(layout.bands, hasLength(15));
      expect(layout.bands.first.source.top, 0);
      expect(layout.bands.last.source.bottom, 1);
      expect(layout.bands.first.destination.top, 0);
      expect(layout.bands.last.destination.bottom, closeTo(700, .001));
      for (var i = 0; i < layout.bands.length; i++) {
        final band = layout.bands[i];
        final scaleX =
            band.destination.width / (band.source.width * page.imageWidth);
        final scaleY =
            band.destination.height / (band.source.height * page.imageHeight);
        expect(scaleX, closeTo(scaleY, .000001));
        if (i > 0) {
          final previous = layout.bands[i - 1];
          expect(band.source.top, previous.source.bottom);
          expect(
            band.destination.top,
            greaterThan(previous.destination.bottom),
          );
          expect(
            layout.sourcePointAt(
              Offset(
                180,
                (previous.destination.bottom + band.destination.top) / 2,
              ),
            ),
            isNull,
          );
        }
      }
      for (final region in page.regions) {
        final source = Offset(
          region.x + region.width / 2,
          region.y + region.height / 2,
        );
        final displayed = layout.displayPoint(source);
        final restored = layout.sourcePointAt(displayed)!;
        expect(restored.dx, closeTo(source.dx, .000001));
        expect(restored.dy, closeTo(source.dy, .000001));
        expect(page.ayahAt(restored.dx, restored.dy), region.ayah);
        expect(layout.regionPath(region).contains(displayed), isTrue);
      }
    },
  );

  test('ornamental pages and landscape stay intact', () {
    expect(
      MushafScanLayout.page(
        page: _page(1),
        size: const Size(360, 700),
        portrait: true,
      ).bands,
      hasLength(1),
    );
    expect(
      MushafScanLayout.page(
        page: _page(122),
        size: const Size(800, 1226.67),
        portrait: false,
      ).bands,
      hasLength(1),
    );
  });

  test('unverified hit-map edges never split the original scan', () {
    expect(
      MushafScanLayout.page(
        page: _page(122),
        size: const Size(360, 700),
        portrait: true,
      ).bands,
      hasLength(1),
    );
  });

  test('cuts never pass through another region or an unmapped heading', () {
    const ayah = QuranAyahReference(id: '', surah: 2, ayah: 7);
    final regions = <MushafAyahRegion>[
      for (final (y, height) in <(double, double)>[
        (.1, .1),
        (.2, .1),
        (.15, .1),
        (.4, .1),
      ])
        MushafAyahRegion(
          id: '',
          ayah: ayah,
          readingOrder: 1,
          polygon: const [],
          x: .1,
          y: y,
          width: .8,
          height: height,
        ),
    ];
    expect(mushafLineBoundaries(regions), isEmpty);
  });
}

MushafPageData _page(int number) => MushafPageData(
  number: number,
  contentVersion: 'test',
  checksumSha256: '',
  imageWidth: 900,
  imageHeight: 1380,
  assets: const [],
  regions: <MushafAyahRegion>[
    for (var line = 0; line < 15; line++)
      MushafAyahRegion(
        id: '$line',
        ayah: QuranAyahReference(id: '$line', surah: 5, ayah: line + 1),
        readingOrder: line,
        polygon: const [],
        x: .05,
        y: .03 + line * .06,
        width: .9,
        height: .06,
      ),
  ],
);
