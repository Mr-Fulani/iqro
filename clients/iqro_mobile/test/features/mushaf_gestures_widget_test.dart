import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_scan_layout.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

const _ayah = QuranAyahReference(id: '5:84', surah: 5, ayah: 84);
const _centralAyah = QuranAyahReference(id: '5:85', surah: 5, ayah: 85);
const _page = MushafPageData(
  number: 122,
  contentVersion: 'test',
  checksumSha256: '',
  imageWidth: 900,
  imageHeight: 1380,
  assets: <MushafAsset>[
    MushafAsset(url: 'https://example.test/page.webp', width: 2700, sha256: ''),
  ],
  regions: <MushafAyahRegion>[
    MushafAyahRegion(
      id: 'region-1',
      ayah: _ayah,
      readingOrder: 1,
      polygon: <MushafPoint>[],
      x: .2,
      y: .1,
      width: .6,
      height: .2,
    ),
    MushafAyahRegion(
      id: 'region-2',
      ayah: _centralAyah,
      readingOrder: 2,
      polygon: <MushafPoint>[],
      x: .2,
      y: .45,
      width: .6,
      height: .15,
    ),
  ],
);

void main() {
  testWidgets(
    'short tap selects an ayah, paper toggles controls, neither opens details',
    (tester) async {
      final harness = await _pumpPage(tester);

      await tester.tapAt(_pagePoint(tester, .5, .2));
      await tester.pump();
      expect(harness.taps, 0);
      expect(harness.shortSelections, <QuranAyahReference>[_ayah]);
      expect(harness.selections, isEmpty);

      await tester.tapAt(_pagePoint(tester, .5, .7));
      await tester.pump();
      expect(harness.taps, 1);
      expect(harness.shortSelections, hasLength(1));
      expect(harness.selections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('holding an ayah selects it once without a release tap', (
    tester,
  ) async {
    final harness = await _pumpPage(tester);
    final finger = await tester.startGesture(_pagePoint(tester, .5, .2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(harness.selections, isEmpty);
    expect(harness.taps, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.selections, <QuranAyahReference>[_ayah]);
    await finger.up();
    await tester.pump();
    expect(harness.taps, 0);
    expect(harness.selections, hasLength(1));
    expect(harness.shortSelections, isEmpty);
  });

  testWidgets('holding blank paper does not select a neighbouring ayah', (
    tester,
  ) async {
    final harness = await _pumpPage(tester);
    await tester.longPressAt(_pagePoint(tester, .5, .7));
    await tester.pump();
    expect(harness.selections, isEmpty);
    expect(harness.taps, 0);
  });

  testWidgets('horizontal page swipe does not trigger a tap or hold', (
    tester,
  ) async {
    final harness = await _pumpPage(tester);
    await tester.dragFrom(_pagePoint(tester, .5, .2), const Offset(280, 0));
    await tester.pump(const Duration(milliseconds: 700));
    expect(harness.pageChanges, <int>[1]);
    expect(harness.taps, 0);
    expect(harness.selections, isEmpty);
  });

  testWidgets('pinch zoom keeps hit testing in page coordinates', (
    tester,
  ) async {
    final harness = await _pumpPage(tester);
    final center = _pagePoint(tester, .5, .2);
    final first = await tester.startGesture(center - const Offset(30, 0));
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-45, 0));
    await second.moveBy(const Offset(45, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await first.up();
    await second.up();
    await tester.pump(const Duration(seconds: 2));
    expect(harness.taps, 0);
    expect(harness.selections, isEmpty);

    // Also cover an explicit zoom change through the reader's zoom control.
    harness.controller.setZoom(1.4);
    await tester.pump();
    final visibleAyahPoint = _pagePoint(tester, .5, .52);
    expect(visibleAyahPoint.dy, inInclusiveRange(0, 800));
    await tester.longPressAt(visibleAyahPoint);
    expect(harness.selections, <QuranAyahReference>[_centralAyah]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape scroll and rotation preserve long-press hit testing', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, size: const Size(800, 400));
    final point = _pagePoint(tester, .5, .2);
    await tester.dragFrom(point, const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 700));
    expect(harness.taps, 0);
    expect(harness.selections, isEmpty);
    await tester.longPressAt(_pagePoint(tester, .5, .2));
    expect(harness.selections, <QuranAyahReference>[_ayah]);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    await tester.pump();
    await tester.longPressAt(_pagePoint(tester, .5, .2));
    expect(harness.selections, <QuranAyahReference>[_ayah, _ayah]);
    expect(harness.taps, 0);
    expect(tester.takeException(), isNull);
  });
}

class _PageHarness {
  final controller = NativeMushafPageController();
  final shortSelections = <QuranAyahReference>[];
  final selections = <QuranAyahReference>[];
  final pageChanges = <int>[];
  var taps = 0;
}

Future<_PageHarness> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(400, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final harness = _PageHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedMushafRepositoryProvider.overrideWithValue(_PageRepository()),
        mushafPageProvider(122).overrideWith((ref) async => _page),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PageView(
            reverse: true,
            onPageChanged: harness.pageChanges.add,
            children: <Widget>[
              NativeMushafPage(
                page: 122,
                controller: harness.controller,
                selectedAyah: null,
                playingAyah: null,
                onSelectAyah: harness.shortSelections.add,
                onOpenAyah: harness.selections.add,
                onBackgroundTap: () => harness.taps++,
                onScale: (_) {},
              ),
              const SizedBox(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return harness;
}

Offset _pagePoint(WidgetTester tester, double x, double y) {
  final surface = find.descendant(
    of: find.byType(InteractiveViewer),
    matching: find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onLongPressStart != null,
    ),
  );
  final box = tester.renderObject<RenderBox>(surface);
  final portrait =
      tester.view.physicalSize.height >= tester.view.physicalSize.width;
  final layout = MushafScanLayout.page(
    page: _page,
    size: box.size,
    portrait: portrait,
  );
  return box.localToGlobal(layout.displayPoint(Offset(x, y)));
}

class _PageRepository implements QuranRepository {
  // Keep IO out of gesture tests; the page geometry is defined by metadata.
  final _asset = Completer<File>();

  @override
  Future<File> cachedMushafPageAsset(MushafPageData page, MushafAsset asset) =>
      _asset.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
