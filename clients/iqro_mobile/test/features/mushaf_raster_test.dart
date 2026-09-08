import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final edition in ['qcf-v4-tajweed-hafs', 'madani-hafs']) {
    testWidgets('rotation preserves the $edition scan and its decoded frame', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final low = _PendingRaster('rotation-low');
      final high = _PendingRaster('rotation-high');
      final repository = _PageRepository(low.file, high.file);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            selectedMushafRepositoryProvider.overrideWithValue(repository),
            mushafPageProvider(51).overrideWith(
              (ref) async => MushafPageData(
                number: _metadata.number,
                editionCode: edition,
                contentVersion: _metadata.contentVersion,
                checksumSha256: _metadata.checksumSha256,
                imageWidth: _metadata.imageWidth,
                imageHeight: _metadata.imageHeight,
                assets: _metadata.assets,
                regions: _metadata.regions,
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NativeMushafPage(
              page: 51,
              controller: NativeMushafPageController(),
              selectedAyah: null,
              playingAyah: null,
              onSelectAyah: (_) {},
              onOpenAyah: (_) {},
              onBackgroundTap: () {},
              onScale: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      low.frame.complete(await _frame(tester, 10));
      await tester.pump();
      final originalState = tester.state(find.byType(MushafRaster));
      expect(_paintedWidth(tester), 10);
      expect(find.text('51'), findsOneWidget);
      final paper = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(NativeMushafPage),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        paper.color,
        edition == 'madani-hafs' ? Colors.white : mushafPaperColor,
      );

      tester.view.physicalSize = const Size(1200, 600);
      await tester.pump();
      await tester.pump();
      expect(tester.state(find.byType(MushafRaster)), same(originalState));
      expect(repository.widths, contains(2160));
      expect(_paintedWidth(tester), 10);
      high.frame.complete(await _frame(tester, 20));
      await tester.pump();
      await tester.pump();
      expect(_paintedWidth(tester), 20);

      tester.view.physicalSize = const Size(400, 800);
      await tester.pump();
      await tester.pump();
      expect(tester.state(find.byType(MushafRaster)), same(originalState));
      expect(_paintedWidth(tester), isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps the current page until its sharper frame is decoded', (
    tester,
  ) async {
    final low = _PendingRaster('low');
    final high = _PendingRaster('high');
    await tester.pumpWidget(_page(low, identity: 'hafs:v1:51'));
    low.frame.complete(await _frame(tester, 10));
    await tester.pump();
    expect(find.text('raster:10'), findsOneWidget);

    await tester.pumpWidget(_page(high, identity: 'hafs:v1:51'));
    expect(find.text('raster:10'), findsOneWidget);

    high.frame.complete(await _frame(tester, 20));
    await tester.pump();
    await tester.pump();
    expect(find.text('raster:20'), findsOneWidget);
    expect(find.text('raster:10'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed resolution upgrade leaves the readable page visible', (
    tester,
  ) async {
    final low = _PendingRaster('failure-low');
    final high = _PendingRaster('failure-high');
    await tester.pumpWidget(_page(low, identity: 'hafs:v1:51'));
    low.frame.complete(await _frame(tester, 10));
    await tester.pump();
    await tester.pumpWidget(_page(high, identity: 'hafs:v1:51'));
    high.frame.completeError(StateError('decode failed'));
    await tester.pump();
    expect(find.text('raster:10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final nextIdentity in <String?>[
    null,
    'tajweed:v1:51',
    'hafs:v2:51',
    'hafs:v1:52',
  ]) {
    testWidgets('does not retain a frame across identity $nextIdentity', (
      tester,
    ) async {
      final previous = _PendingRaster('previous-$nextIdentity');
      final next = _PendingRaster('next-$nextIdentity');
      await tester.pumpWidget(_page(previous, identity: 'hafs:v1:51'));
      previous.frame.complete(await _frame(tester, 10));
      await tester.pump();
      await tester.pumpWidget(_page(next, identity: nextIdentity));
      expect(find.text('raster:10'), findsNothing);
      next.frame.completeError(StateError('unavailable'));
      await tester.pump();
      expect(find.text('unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a late superseded stream cannot replace the current page', (
    tester,
  ) async {
    final first = _PendingRaster('late-first');
    final second = _PendingRaster('late-second');
    await tester.pumpWidget(_page(first, identity: 'hafs:v1:51'));
    await tester.pumpWidget(_page(second, identity: 'hafs:v1:52'));
    second.frame.complete(await _frame(tester, 20));
    await tester.pump();
    first.frame.complete(await _frame(tester, 10));
    await tester.pump();
    expect(find.text('raster:20'), findsOneWidget);
    expect(find.text('raster:10'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _page(_PendingRaster raster, {String? identity}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MushafRaster(
    file: raster.file,
    continuityKey: identity,
    fallback: const Text('unavailable'),
    builder: (image) => Text('raster:${image.width}'),
  ),
);

Future<ImageInfo> _frame(WidgetTester tester, int width) async => ImageInfo(
  image: (await tester.runAsync(() => createTestImage(width: width)))!,
);

/// Controlled ImageStreams use the real FileImage cache key, without disk IO.
class _PendingRaster {
  _PendingRaster(String name) : file = File('/virtual-mushaf/$name.webp') {
    final provider = FileImage(file);
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(frame.future),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
  }

  final File file;
  final frame = Completer<ImageInfo>();
}

int? _paintedWidth(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<MushafScanPainter>()
    .firstOrNull
    ?.image
    .width;

const _metadata = MushafPageData(
  number: 51,
  editionCode: 'qcf-v4-tajweed-hafs',
  contentVersion: 'test-v1',
  checksumSha256: '',
  imageWidth: 900,
  imageHeight: 1380,
  assets: [
    MushafAsset(
      url: 'https://example.test/900.webp',
      width: 900,
      sha256: 'low',
    ),
    MushafAsset(
      url: 'https://example.test/2160.webp',
      width: 2160,
      sha256: 'high',
    ),
  ],
  regions: [],
);

class _PageRepository implements QuranRepository {
  _PageRepository(this.low, this.high);
  final File low;
  final File high;
  final widths = <int>[];

  @override
  Future<File> cachedMushafPageAsset(
    MushafPageData page,
    MushafAsset asset,
  ) async {
    widths.add(asset.width);
    return asset.width == 900 ? low : high;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
