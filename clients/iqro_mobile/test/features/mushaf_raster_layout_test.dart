import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster_layout.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

void main() {
  test('portrait preserves the complete page, spacing and hit geometry', () {
    final page = _page(122);
    final layout = MushafRasterLayout.page(
      page: page,
      size: const Size(360, 700),
      portrait: true,
    );
    expect(layout.bands, hasLength(1));
    expect(layout.bands.first.source.top, 0);
    expect(layout.bands.last.source.bottom, 1);
    expect(layout.bands.single.source, const Rect.fromLTWH(0, 0, 1, 1));
    expect(layout.bands.single.destination.center, const Offset(180, 350));
    for (var i = 0; i < layout.bands.length; i++) {
      final band = layout.bands[i];
      final scaleX =
          band.destination.width / (band.source.width * page.imageWidth);
      final scaleY =
          band.destination.height / (band.source.height * page.imageHeight);
      expect(scaleX, closeTo(scaleY, .000001));
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
  });

  test('ornamental pages and landscape stay intact', () {
    expect(
      MushafRasterLayout.page(
        page: _page(1),
        size: const Size(360, 700),
        portrait: true,
      ).bands,
      hasLength(1),
    );
    expect(
      MushafRasterLayout.page(
        page: _page(122),
        size: const Size(800, 1226.67),
        portrait: false,
      ).bands,
      hasLength(1),
    );
  });

  test('hit-map edges and page number never change scale or spacing', () {
    final layouts = [
      for (final number in [1, 2, 3, 50, 604])
        for (final x in [0.0, .024, .025, .05])
          MushafRasterLayout.page(
            page: _page(number, x: x),
            size: const Size(360, 700),
            portrait: true,
          ),
    ];
    for (final layout in layouts) {
      expect(layout.bands, layouts.first.bands);
    }
  });

  for (final edition in ['madani-hafs', 'qcf-v2-hafs', 'kfgqpc-hafs']) {
    test('$edition preserves spacing on tall phones and tablets', () {
      for (final size in const [
        Size(360, 700),
        Size(360, 900),
        Size(800, 1000),
      ]) {
        final page = _page(122, edition: edition);
        final layout = MushafRasterLayout.page(
          page: page,
          size: size,
          portrait: true,
        );
        final band = layout.bands.single;
        expect(band.source, const Rect.fromLTWH(0, 0, 1, 1));
        expect(band.destination.center, size.center(Offset.zero));
        expect(
          band.destination.width / page.imageWidth,
          closeTo(band.destination.height / page.imageHeight, .000001),
        );
        expect(band.destination.left, greaterThanOrEqualTo(0));
        expect(band.destination.top, greaterThanOrEqualTo(0));
        expect(band.destination.right, lessThanOrEqualTo(size.width));
        expect(band.destination.bottom, lessThanOrEqualTo(size.height));
      }
    });
  }

  test('extra screen height moves the page, never separates its lines', () {
    final page = _page(50);
    final short = MushafRasterLayout.page(
      page: page,
      size: const Size(360, 700),
      portrait: true,
    );
    final tall = MushafRasterLayout.page(
      page: page,
      size: const Size(360, 900),
      portrait: true,
    );
    expect(
      short.bands.single.destination.size,
      tall.bands.single.destination.size,
    );
    for (final y in [.03, .09, .3, .5, .9, .97]) {
      final before = short.displayPoint(Offset(.5, y));
      final after = tall.displayPoint(Offset(.5, y));
      expect(after.dx, before.dx);
      expect(after.dy - before.dy, closeTo(100, .000001));
    }
    expect(tall.sourcePointAt(const Offset(180, 1)), isNull);
    expect(tall.sourcePointAt(const Offset(180, 899)), isNull);
  });

  test(
    'landscape fills width and preserves the complete page for scrolling',
    () {
      final layout = MushafRasterLayout.page(
        page: _page(122),
        size: const Size(800, 400),
        portrait: false,
      );
      final band = layout.bands.single;
      expect(band.source, const Rect.fromLTWH(0, 0, 1, 1));
      expect(band.destination.left, 0);
      expect(band.destination.top, 0);
      expect(band.destination.width, 800);
      expect(band.destination.height, closeTo(800 * 1380 / 900, .000001));
    },
  );

  test('highlight polygon uses the same page transform as ink', () {
    final layout = MushafRasterLayout.page(
      page: _page(3),
      size: const Size(360, 900),
      portrait: true,
    );
    const region = MushafAyahRegion(
      id: 'polygon',
      ayah: QuranAyahReference(id: '', surah: 2, ayah: 7),
      readingOrder: 1,
      polygon: [MushafPoint(.1, .1), MushafPoint(.9, .1), MushafPoint(.1, .3)],
      x: .1,
      y: .1,
      width: .8,
      height: .2,
    );
    final path = layout.regionPath(region);
    expect(path.contains(layout.displayPoint(const Offset(.2, .15))), isTrue);
    expect(path.contains(layout.displayPoint(const Offset(.85, .28))), isFalse);
  });
}

MushafPageData _page(
  int number, {
  String edition = 'madani-hafs',
  double x = .05,
}) => MushafPageData(
  number: number,
  editionCode: edition,
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
        x: x,
        y: .03 + line * .06,
        width: 1 - x * 2,
        height: .06,
      ),
  ],
);
