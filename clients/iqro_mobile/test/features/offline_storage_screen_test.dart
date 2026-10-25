// The offline storage screen. With SCREENSHOT_DIR it also saves a picture of
// the screen for the pull request:
//
//   flutter test test/features/offline_storage_screen_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Real fonts come from the Flutter SDK (Roboto, Material icons) and macOS
// (Georgia for `serif`).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/design_system/iqro_icon.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition_picker.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';
import 'package:iqro_mobile/features/quran/mushaf_thumbnail_cache.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/settings/offline_storage_repository.dart';
import 'package:iqro_mobile/features/settings/offline_storage_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _size = Size(1080, 2340); // Redmi Note 7
const _pixelRatio = 2.75;
final _boundary = GlobalKey();

NativeMushafEdition _edition(String code, String en, String ru) =>
    NativeMushafEdition(
      identity: MushafIdentity.fromPreference('native:$code'),
      names: {'en': en, 'ru': ru},
      stagingOnly: false,
      sourceChecksum: 'source-v1',
    );

final _tajweed = _edition(
  'qcf-v4-tajweed-hafs',
  'QCF V4 Tajweed',
  'QCF V4 Таджвид',
);
final _madinah = _edition('qf-1', 'Madinah Mushaf', 'Мединский Мусхаф');

OfflinePackageSummary _package(
  String id,
  String type,
  String contentKey, {
  int bytes = 1024,
  bool active = true,
  Map<String, Object?> manifest = const <String, Object?>{},
}) => OfflinePackageSummary(
  packageId: id,
  packageType: type,
  contentKey: contentKey,
  status: 'ready',
  active: active,
  completedItems: 604,
  totalItems: 604,
  downloadedBytes: bytes,
  totalBytes: bytes,
  usedBytes: bytes,
  manifest: manifest,
);

/// A page-shaped picture: paper with lines of ink, as the picker stores it.
Future<ui.Image> _page(int width) {
  final height = (width / mushafEditionPageSize.aspectRatio).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = mushafPaperColor,
    );
  final ink = Paint()
    ..color = const Color(0xFF392D20)
    ..strokeWidth = height / 60;
  for (var line = 1; line <= 15; line++) {
    final y = height * line / 16;
    canvas.drawLine(Offset(width * .12, y), Offset(width * .88, y), ink);
  }
  return recorder.endRecording().toImage(width, height);
}

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Roboto', <String>[
    for (final weight in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$weight.ttf',
  ]);
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('serif', <String>[
    '/System/Library/Fonts/Supplemental/Georgia.ttf',
    '/System/Library/Fonts/Supplemental/Georgia Bold.ttf',
  ]);
}

Future<_Pages> _pump(
  WidgetTester tester,
  List<OfflinePackageSummary> packages, {
  required List<NativeMushafEdition> stored,
}) async {
  final cache = MushafThumbnailCache.memory();
  final width = (44 * tester.view.devicePixelRatio).round();
  await tester.runAsync(() async {
    for (final edition in stored) {
      final key = MushafThumbnailKey(
        edition: edition.identity.code,
        version: edition.sourceChecksum,
        locale: 'ru',
        width: width,
      );
      await cache.save(key, await _page(width));
    }
  });
  final pages = _Pages();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: [
          offlinePackagesProvider.overrideWith((ref) async => packages),
          availableMushafRenditionsProvider.overrideWithValue([
            _tajweed,
            _madinah,
          ]),
          mushafThumbnailCacheProvider.overrideWithValue(cache),
          mushafRepositoryProvider.overrideWith((ref, identity) => pages),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: IqroTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OfflineStorageScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  return pages;
}

void main() {
  setUpAll(() async {
    if (_directory.isNotEmpty) await _loadFonts();
  });

  testWidgets(
    'a downloaded Mushaf shows its edition name and stored miniature',
    (tester) async {
      final pages = await _pump(
        tester,
        [
          _package('tajweed', 'mushaf_pages', _tajweed.identity.contentKey),
          // An edition the catalog no longer lists.
          _package('old', 'mushaf_pages', 'mushaf-rendition:retired'),
        ],
        stored: [_tajweed],
      );

      expect(find.text('QCF V4 Таджвид'), findsOneWidget);
      // Without a catalog entry the package keeps its generic name and seal.
      expect(find.text('Мусхаф без интернета'), findsOneWidget);
      expect(find.byType(MushafEditionThumbnail), findsOneWidget);
      // The picker's stored picture: no page is loaded to draw it.
      expect(
        find.descendant(
          of: find.byType(MushafEditionThumbnail),
          matching: find.byType(RawImage),
        ),
        findsOneWidget,
      );
      expect(pages.requested, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a Mushaf the catalog no longer lists keeps the name and page it was '
    'downloaded with',
    (tester) async {
      final pages = await _pump(tester, [
        _package(
          'legacy',
          'mushaf_pages',
          'mushaf-rendition:qcf-v2-hafs',
          active: false,
          manifest: const {
            'name': 'QCF V2',
            'preview_path': '/offline_packages/mushaf/legacy/page-604.webp',
          },
        ),
      ], stored: const []);

      expect(find.text('QCF V2'), findsOneWidget);
      expect(
        find.text('Полные страницы Мусхафа · Прежняя версия'),
        findsOneWidget,
      );
      final page = tester.widget<Image>(find.byType(Image));
      expect(
        ((page.image as ResizeImage).imageProvider as FileImage).file.path,
        '/offline_packages/mushaf/legacy/page-604.webp',
      );
      expect(pages.requested, isEmpty);
    },
  );

  testWidgets('the prayer course shows a figure in sujud', (tester) async {
    await _pump(tester, [
      _package('salah', 'salah_course', 'salah-course:v1'),
    ], stored: const []);

    expect(find.text('Обучение намазу'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IqroIcon && widget.icon == iqroSalahIcon,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.self_improvement), findsNothing);
  });

  testWidgets('screenshot', (tester) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.padding = const FakeViewPadding(top: 66);
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      [
        _package('salah', 'salah_course', 'salah-course:v1', bytes: 384000),
        _package(
          'tajweed',
          'mushaf_pages',
          _tajweed.identity.contentKey,
          bytes: 200278016,
        ),
        _package(
          'madinah',
          'mushaf_pages',
          _madinah.identity.contentKey,
          bytes: 256901120,
        ),
      ],
      stored: [_tajweed, _madinah],
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('$_directory/app-offline-storage-ru.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    expect(tester.takeException(), isNull);
  }, skip: _directory.isEmpty);
}

class _Pages implements QuranRepository {
  final requested = <int>[];

  @override
  QuranRepository forMushaf(MushafIdentity identity) => this;

  @override
  QuranRepository withFoundationVersion(String version) => this;

  @override
  Future<MushafPageData> mushafPage(int page, {bool forceRefresh = false}) {
    requested.add(page);
    return Completer<MushafPageData>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
