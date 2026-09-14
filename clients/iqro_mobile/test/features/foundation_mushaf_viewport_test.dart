import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final size in [const Size(400, 900), const Size(500, 600)]) {
    testWidgets('Foundation page stays centered before and after zoom: $size', (
      tester,
    ) async {
      final controller = await _pump(tester, size);
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      final page = tester.getRect(find.byType(FoundationMushafPageContent));

      expect(page.center.dx, closeTo(viewport.center.dx, .01));
      expect(page.center.dy, closeTo(viewport.center.dy, .01));
      expect(viewport.inflate(.01).contains(page.topLeft), isTrue);
      expect(viewport.inflate(.01).contains(page.bottomRight), isTrue);
      expect(page.width / page.height, closeTo(900 / 1380, .001));

      controller.setZoom(1.5);
      await tester.pump();
      final zoomed = tester.getRect(find.byType(FoundationMushafPageContent));
      expect(zoomed.center.dx, closeTo(viewport.center.dx, .01));
      expect(zoomed.center.dy, closeTo(viewport.center.dy, .01));
      expect(zoomed.width, closeTo(page.width * 1.5, .01));

      controller.setZoom(1);
      await tester.pump();
      expect(tester.getRect(find.byType(FoundationMushafPageContent)), page);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty viewport margin still toggles reader controls once', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, const Size(400, 900), onBackground: () => taps++);
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final page = tester.getRect(find.byType(FoundationMushafPageContent));
    expect(page.top - viewport.top, greaterThan(10));
    await tester.tapAt(Offset(viewport.center.dx, viewport.top + 5));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape can scroll; rotation restores a centered full page', (
    tester,
  ) async {
    await _pump(tester, const Size(800, 400));
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final initial = tester.getRect(find.byType(FoundationMushafPageContent));
    expect(initial.top, viewport.top);
    expect(initial.width, viewport.width);
    expect(initial.height, greaterThan(viewport.height));

    await tester.dragFrom(viewport.center, const Offset(0, -120));
    await tester.pump(const Duration(seconds: 1));
    final scrolled = tester.getRect(find.byType(FoundationMushafPageContent));
    expect(scrolled.top, lessThan(initial.top));

    tester.view.physicalSize = const Size(400, 900);
    await tester.pump();
    await tester.pump();
    final portraitViewport = tester.getRect(find.byType(InteractiveViewer));
    final portrait = tester.getRect(find.byType(FoundationMushafPageContent));
    expect(portrait.center.dx, closeTo(portraitViewport.center.dx, .01));
    expect(portrait.center.dy, closeTo(portraitViewport.center.dy, .01));
    expect(portrait.width, closeTo(portraitViewport.width, .01));
    expect(tester.takeException(), isNull);
  });
}

Future<NativeMushafPageController> _pump(
  WidgetTester tester,
  Size size, {
  VoidCallback? onBackground,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = NativeMushafPageController();
  final page = MushafPageData.fromFoundation({
    'mushaf_id': 19,
    'page_number': 42,
    'pages_count': 604,
    'lines_per_page': 15,
    'source_checksum_sha256': 'a' * 64,
    'verse_mapping': {'2': '255'},
    'rendering': {
      'available': true,
      'version': 2,
      'mode': 'page-font',
      'native_font_url': 'https://example.test/p42.ttf',
    },
    'words': [
      {
        'id': 1,
        'verse_key': '2:255',
        'line_number': 1,
        'position_in_verse': 1,
        'position_in_page': 1,
        'text': 'ﱁ',
      },
    ],
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedMushafRepositoryProvider.overrideWithValue(_Repository()),
        mushafPageProvider(42).overrideWith((ref) async => page),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NativeMushafPage(
            page: 42,
            controller: controller,
            selectedAyah: null,
            playingAyah: null,
            onSelectAyah: (_) {},
            onOpenAyah: (_) {},
            onBackgroundTap: onBackground ?? () {},
            onScale: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

class _Repository implements QuranRepository {
  // Viewport placement must already be correct while the font is loading.
  // Font fidelity and word hit testing are covered separately.
  final _asset = Completer<File>();

  @override
  Future<File> foundationAsset(Uri uri, String version) => _asset.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
