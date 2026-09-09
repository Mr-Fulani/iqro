import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/platform/reader_haptics.dart';
import 'package:iqro_mobile/features/quran/mushaf_facsimile_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster.dart';
import 'package:iqro_mobile/features/quran/tajweed_book_preview_screen.dart';
import 'package:iqro_mobile/features/quran/tajweed_book_preview_source.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  test('one complete source rectangle: no changed lines, colours or crop', () {
    for (final fitWidth in [true, false]) {
      for (final viewport in const [
        Size(360, 780),
        Size(780, 360),
        Size(800, 1100),
        Size(320, 400),
      ]) {
        final layout = facsimilePageLayout(
          source: const Size(645, 1000),
          viewport: viewport,
          fitWidth: fitWidth,
        );
        final band = layout.bands.single;
        expect(band.source, const Rect.fromLTWH(0, 0, 1, 1));
        expect(
          band.destination.width / 645,
          closeTo(band.destination.height / 1000, 1e-9),
        );
        expect(band.destination.left, greaterThanOrEqualTo(0));
        expect(band.destination.top, greaterThanOrEqualTo(0));
        expect(band.destination.right, lessThanOrEqualTo(layout.size.width));
        expect(band.destination.bottom, lessThanOrEqualTo(layout.size.height));
        if (fitWidth) {
          expect(band.destination.width, closeTo(viewport.width, 1e-9));
          expect(band.destination.left, closeTo(0, 1e-9));
        } else {
          expect(layout.size, viewport);
        }
        // A future verified map can use the same transform, never old QCF XY.
        for (final point in const [
          Offset(.02, .02),
          Offset(.5, .5),
          Offset(.98, .98),
        ]) {
          final restored = layout.sourcePointAt(layout.displayPoint(point))!;
          expect(restored.dx, closeTo(point.dx, 1e-9));
          expect(restored.dy, closeTo(point.dy, 1e-9));
        }
      }
    }
  });

  test('release/production do not expose the visual experiment', () {
    expect(
      canShowTajweedBookPreview(
        const AppConfig(
          apiBaseUrl: 'https://iqro.forum',
          fallbackDownloadUrl: 'https://iqro.forum',
          environment: 'production',
        ),
      ),
      isFalse,
    );
    expect(TajweedBookSample.samples.map((s) => s.page), [51, 52, 53]);
    for (final sample in TajweedBookSample.samples) {
      expect(sample.verifies([1, 2, 3]), isFalse);
      expect(sample.uri.path, contains(TajweedBookSample.commit));
      expect(sample.uri.host, 'raw.githubusercontent.com');
    }
  });

  testWidgets(
    'landscape scroll, rotate back and change fit without a lost frame',
    (tester) async {
      _setSize(tester, const Size(360, 780));
      final file = await _raster(tester, 'rotation');
      var fitWidth = true;
      final zoomEvents = <bool>[];
      Future<void> pump() async {
        await tester.pumpWidget(
          _app(
            MushafFacsimilePage(
              file: file,
              fitWidth: fitWidth,
              onTap: () {},
              onZoomChanged: zoomEvents.add,
            ),
          ),
        );
        await tester.pump();
      }

      await pump();
      final rasterState = tester.state(find.byType(MushafRaster));
      final portrait = _painter(tester).layout;
      expect(portrait.bands.single.destination.width, 360);
      tester.view.physicalSize = const Size(780, 360);
      await pump();
      expect(tester.state(find.byType(MushafRaster)), same(rasterState));
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.panEnabled, isTrue);
      await tester.dragFrom(const Offset(390, 280), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(
        viewer.transformationController!.value.getTranslation().y,
        lessThan(0),
      );
      tester.view.physicalSize = const Size(360, 780);
      await pump();
      expect(tester.state(find.byType(MushafRaster)), same(rasterState));
      expect(viewer.transformationController!.value, Matrix4.identity());
      expect(_painter(tester).layout.bands, portrait.bands);
      fitWidth = false;
      await pump();
      expect(tester.state(find.byType(MushafRaster)), same(rasterState));
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    testWidgets(
      '$locale: three pages, tap controls, RTL swipe, one haptic per page',
      (tester) async {
        _setSize(tester, const Size(360, 780));
        final files = <int, File>{};
        for (final sample in TajweedBookSample.samples) {
          files[sample.page] = await _raster(tester, '$locale-${sample.page}');
        }
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ReaderHaptics.channel,
          (call) async {
            calls.add(call);
            return 'played';
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            ReaderHaptics.channel,
            null,
          ),
        );
        await tester.pumpWidget(
          _app(
            TajweedBookPreviewScreen(
              loadSample: (sample) async => files[sample.page]!,
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        await tester.tap(
          find.byKey(const ValueKey('facsimile-raster')).hitTestable(),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('book-preview-fit')), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('facsimile-raster')).hitTestable(),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('book-preview-page-52')));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        // Mushaf progresses RTL in every interface language.
        await tester.drag(find.byType(PageView), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(calls, hasLength(1));
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          2,
        );
        await tester.tap(find.byKey(const ValueKey('book-preview-fit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.play_arrow), findsNothing);
      },
    );
  }

  testWidgets('failed source load can retry without writing reader state', (
    tester,
  ) async {
    _setSize(tester, const Size(360, 780));
    final file = await _raster(tester, 'retry');
    var fail = true;
    await tester.pumpWidget(
      _app(
        TajweedBookPreviewScreen(
          haptics: false,
          loadSample: (_) async {
            if (fail) throw const FormatException('source unavailable');
            return file;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Повторить').hitTestable(), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Повторить').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('facsimile-raster')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(Widget child, {String locale = 'ru'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<File> _raster(WidgetTester tester, String name) async {
  final file = File('/virtual-facsimile/$name.jpg');
  final info = ImageInfo(
    image: (await tester.runAsync(
      () => createTestImage(width: 645, height: 1000),
    ))!,
  );
  final provider = FileImage(file);
  PaintingBinding.instance.imageCache.putIfAbsent(
    provider,
    () => OneFrameImageStreamCompleter(Future.value(info)),
  );
  addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
  return file;
}

MushafScanPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('facsimile-raster')))
            .painter!
        as MushafScanPainter;
