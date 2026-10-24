import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition_picker.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster.dart';
import 'package:iqro_mobile/features/quran/mushaf_thumbnail_cache.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;

import 'tajweed_test_data.dart';

const _ink = Color(0xFF392D20);
const _tajweed = 'qcf-v4-tajweed-hafs';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('mushaf-thumbnails');
  });
  tearDown(() => support.delete(recursive: true));

  Future<MushafThumbnailCache> open() =>
      MushafThumbnailCache.open(supportDirectory: () async => support);
  Directory stored() =>
      Directory(p.join(support.path, mushafThumbnailsDirectory));
  List<String> storedNames() =>
      stored().listSync().map((file) => p.basename(file.path)).toList()..sort();

  group('cache', () {
    test('a miss stays a miss until a picture is saved', () async {
      final cache = await open();
      final key = _key();
      expect(cache.isStored(key), isFalse);
      expect(cache.picture(key), isNull);
      expect(await cache.load(key), isNull);
    });

    test(
      'a saved picture is shown from memory, then from disk after a restart',
      () async {
        final cache = await open();
        final key = _key();
        await cache.save(key, await _picture(120, 207));
        final remembered = cache.picture(key)!;
        expect(remembered.width, 120);
        remembered.dispose();
        expect(storedNames(), [key.fileName]);

        final restarted = await open();
        expect(restarted.isStored(key), isTrue);
        expect(restarted.picture(key), isNull);
        final loaded = (await restarted.load(key))!;
        expect((loaded.width, loaded.height), (120, 207));
        expect(await _centre(loaded), _ink);
        loaded.dispose();
        // Decoded once, then from memory.
        expect(restarted.picture(key), isNotNull);
        // Another size or language is another picture.
        expect(restarted.isStored(_key(width: 121)), isFalse);
        expect(restarted.isStored(_key(locale: 'en')), isFalse);
      },
    );

    test(
      "a new source version replaces only that edition's pictures",
      () async {
        final cache = await open();
        final old = _key(version: 'v1');
        final oldSmall = _key(version: 'v1', width: 60);
        final other = _key(edition: 'qf-1', version: 'v1');
        for (final key in [old, oldSmall, other]) {
          await cache.save(key, await _picture(key.width, key.width * 2));
        }
        final next = _key(version: 'v2');
        await cache.save(next, await _picture(120, 240));

        expect(cache.picture(old), isNull);
        expect(cache.picture(oldSmall), isNull);
        expect(cache.picture(other), isNotNull);
        expect(storedNames(), unorderedEquals([next.fileName, other.fileName]));
        final restarted = await open();
        expect(restarted.isStored(old), isFalse);
        expect(restarted.isStored(next), isTrue);
        expect(restarted.isStored(other), isTrue);
      },
    );

    test('memory keeps the newest pictures within its budget', () async {
      final cache = MushafThumbnailCache.memory();
      // 16 MB each decoded: the oldest of three leaves the 32 MB budget.
      final keys = [
        for (final e in ['qf-1', 'qf-2', 'qf-5']) _key(edition: e),
      ];
      for (final key in keys) {
        await cache.save(key, await _picture(2048, 2048));
      }
      expect(cache.picture(keys[0]), isNull);
      expect(cache.picture(keys[1]), isNotNull);
      expect(cache.picture(keys[2]), isNotNull);
    });

    test(
      'an unreadable picture is removed so the page is drawn again',
      () async {
        final key = _key();
        await stored().create(recursive: true);
        await File(p.join(stored().path, key.fileName)).writeAsString('broken');
        await File(p.join(stored().path, 'x.png.partial')).writeAsString('cut');

        final cache = await open();
        expect(storedNames(), [key.fileName]);
        expect(cache.isStored(key), isTrue);
        expect(await cache.load(key), isNull);
        expect(cache.isStored(key), isFalse);
        expect(storedNames(), isEmpty);
      },
    );
  });

  group('miniature', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.devicePixelRatio = 2;
      addTearDown(view.resetDevicePixelRatio);
    });

    testWidgets(
      'is drawn once its page and labels are painted, then shown as a picture',
      (tester) async {
        final cache = MushafThumbnailCache.memory();
        final raster = _Raster();
        final labels = Completer<QuranCatalog>();
        final pages = _Pages(raster.file);
        await tester.pumpWidget(_app(cache, pages, catalog: labels.future));
        expect(find.byType(NativeMushafPage), findsOneWidget);

        // Neither a page still decoding nor one without its surah name is
        // kept as the picture.
        await _settle(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await raster.decode(tester);
        await _settle(tester);
        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .where((paint) => paint.painter is MushafRasterPainter),
          isNotEmpty,
        );
        expect(find.byType(RawImage), findsNothing);
        expect(cache.picture(_widgetKey()), isNull);

        labels.complete(_catalog);
        await _until(tester, find.byType(RawImage));
        expect(find.byType(NativeMushafPage), findsNothing);
        final picture = tester.widget<RawImage>(find.byType(RawImage)).image!;
        expect(picture.width, 320);
        expect(await tester.runAsync(() => _centre(picture)), _ink);
        expect(pages.requested, [604]);

        // The picker closes and opens again.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_app(cache, pages));
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(NativeMushafPage), findsNothing);
        expect(pages.requested, [604]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a picture stored by an earlier run shows without the page', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final earlier = await open();
        await earlier.save(_widgetKey(), await _picture(320, 551));
      });
      final cache = (await tester.runAsync(open))!;
      final pages = _Pages(_Raster().file);
      await tester.pumpWidget(_app(cache, pages));
      // Paper while the picture decodes, never a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NativeMushafPage), findsNothing);

      await _until(tester, find.byType(RawImage));
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(pages.requested, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new edition version draws the page again', (tester) async {
      final cache = MushafThumbnailCache.memory();
      final old = _widgetKey(version: 'source-v0');
      final image = (await tester.runAsync(() => _picture(320, 551)))!;
      await tester.runAsync(() => cache.save(old, image));
      final raster = _Raster();
      await raster.decode(tester);
      final pages = _Pages(raster.file);

      await tester.pumpWidget(_app(cache, pages));
      expect(find.byType(NativeMushafPage), findsOneWidget);
      await _until(tester, find.byType(RawImage));
      expect(pages.requested, [604]);
      expect(cache.picture(old), isNull);
      expect(cache.picture(_widgetKey()), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Quran Foundation page is kept once its font has drawn it', (
      tester,
    ) async {
      final cache = MushafThumbnailCache.memory();
      final pages = _Pages(_Raster().file, foundation: true);
      await tester.pumpWidget(_app(cache, pages, edition: _foundationEdition));
      await _until(tester, find.byType(FoundationMushafPageContent));
      await _until(tester, find.byType(RawImage));
      final picture = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(picture.width, 320);
      expect(
        cache.picture(_widgetKey(edition: 'qf-19', version: _qfVersion)),
        isNotNull,
      );
      expect(pages.requested, [604]);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(cache, pages, edition: _foundationEdition));
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(FoundationMushafPageContent), findsNothing);
      expect(pages.requested, [604]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preview always draws the page itself', (tester) async {
      final cache = MushafThumbnailCache.memory();
      final image = (await tester.runAsync(() => _picture(320, 551)))!;
      await tester.runAsync(() => cache.save(_widgetKey(), image));
      final pages = _Pages(_Raster().file);
      await tester.pumpWidget(_app(cache, pages, live: true));
      expect(find.byType(NativeMushafPage), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });
  });
}

/// The miniature is 160 logical pixels wide at a device pixel ratio of 2.
MushafThumbnailKey _widgetKey({
  String edition = _tajweed,
  String version = _version,
}) => MushafThumbnailKey(
  edition: edition,
  version: version,
  locale: 'ru',
  width: 320,
);

MushafThumbnailKey _key({
  String edition = 'qf-19',
  String version = 'v1',
  String locale = 'ru',
  int width = 120,
}) => MushafThumbnailKey(
  edition: edition,
  version: version,
  locale: locale,
  width: width,
);

const _version = 'source-v1';

final _edition = NativeMushafEdition(
  identity: MushafIdentity.fromPreference('native:$_tajweed'),
  names: const {'en': 'QCF V4 Tajweed'},
  stagingOnly: false,
  sourceChecksum: _version,
);

final _qfVersion = 'a' * 64;

final _foundationEdition = NativeMushafEdition(
  identity: MushafIdentity.fromPreference('native:qf-19'),
  names: const {'en': 'QCF V4 Tajweed'},
  stagingOnly: false,
  sourceChecksum: _qfVersion,
);

const _catalog = QuranCatalog(
  surahs: [
    Surah(
      id: '112',
      number: 112,
      nameAr: 'الإخلاص',
      nameEn: 'Al-Ikhlas',
      nameRu: 'Аль-Ихлас',
      ayahCount: 4,
      revelationType: 'meccan',
    ),
  ],
  fromCache: false,
);

const _juz = [
  QuranDivision(
    number: 30,
    startAyah: QuranAyahReference(id: '78:1', surah: 78, ayah: 1),
    endAyah: QuranAyahReference(id: '114:6', surah: 114, ayah: 6),
    startPage: 582,
    endPage: 604,
  ),
];

/// Ink on the whole picture, so its centre tells page content from paper.
Future<ui.Image> _picture(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = _ink,
  );
  return recorder.endRecording().toImage(width, height);
}

Future<Color> _centre(ui.Image image) async {
  final bytes = (await image.toByteData())!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

Widget _app(
  MushafThumbnailCache cache,
  _Pages pages, {
  NativeMushafEdition? edition,
  Future<QuranCatalog>? catalog,
  bool live = false,
}) => ProviderScope(
  overrides: [
    mushafThumbnailCacheProvider.overrideWithValue(cache),
    mushafRepositoryProvider.overrideWith((ref, identity) => pages),
    quranCatalogProvider.overrideWith(
      (ref) async => catalog == null ? _catalog : await catalog,
    ),
    quranJuzProvider.overrideWith((ref) async => _juz),
  ],
  child: MaterialApp(
    theme: IqroTheme.light(),
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Center(
      child: SizedBox(
        width: 160,
        child: MushafEditionThumbnail(edition: edition ?? _edition, live: live),
      ),
    ),
  ),
);

/// Lets page loading, picture capture and decoding run on the real clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A page picture that decodes when the test says so, through the real
/// FileImage cache key and without disk IO.
class _Raster {
  _Raster() : file = File('/virtual-mushaf/thumbnail-604.webp') {
    final provider = FileImage(file);
    PaintingBinding.instance.imageCache.evict(provider);
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(_frame.future),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
  }

  final File file;
  final _frame = Completer<ImageInfo>();

  Future<void> decode(WidgetTester tester) async {
    final image = await tester.runAsync(() => _picture(900, 1380));
    _frame.complete(ImageInfo(image: image!));
  }
}

class _Pages implements QuranRepository {
  _Pages(this.asset, {this.foundation = false});

  final File asset;
  final bool foundation;
  final requested = <int>[];

  @override
  QuranRepository forMushaf(MushafIdentity identity) => this;

  @override
  QuranRepository withFoundationVersion(String version) => this;

  @override
  Future<MushafPageData> mushafPage(int page, {bool forceRefresh = false}) {
    requested.add(page);
    if (foundation) {
      return Future.value(
        MushafPageData.fromFoundation({
          'mushaf_id': 19,
          'page_number': page,
          'pages_count': 604,
          'lines_per_page': 15,
          'source_checksum_sha256': _qfVersion,
          'verse_mapping': {'112': '4'},
          'rendering': {
            'available': true,
            'version': 2,
            'mode': 'page-font',
            'native_font_url':
                'https://verses.quran.foundation/fonts/quran/p.ttf',
          },
          'words': page604Words,
        }),
      );
    }
    return Future.value(
      MushafPageData(
        number: page,
        editionCode: _tajweed,
        contentVersion: 'test',
        checksumSha256: '',
        imageWidth: 900,
        imageHeight: 1380,
        assets: const [
          MushafAsset(
            url: 'https://example.test/604.webp',
            width: 900,
            sha256: '',
          ),
        ],
        regions: const [],
      ),
    );
  }

  @override
  Future<File> cachedMushafPageAsset(MushafPageData page, MushafAsset asset) =>
      Future.value(this.asset);

  @override
  Future<File> foundationAsset(Uri uri, String version) async =>
      File('assets/fonts/AmiriQuran-Regular.ttf');

  @override
  Future<bool> refreshMushafPageResolution(
    MushafPageData page, {
    required int minimumWidth,
  }) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
