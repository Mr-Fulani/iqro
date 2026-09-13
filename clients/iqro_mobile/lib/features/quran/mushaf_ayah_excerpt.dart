import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'mushaf_paper.dart';
import 'foundation_mushaf_page.dart';
import 'mushaf_raster.dart';
import 'mushaf_raster_layout.dart';
import 'quran_models.dart';
import 'quran_repository.dart';

typedef MushafExcerptPage = ({
  MushafPageData page,
  File file,
  List<MushafAyahRegion> regions,
});

Future<List<MushafExcerptPage>> loadMushafExcerpt({
  required QuranRepository repository,
  required QuranAyah ayah,
  required int tappedPage,
  required double pixelWidth,
}) async {
  final numbers = <int>{...ayah.pages, tappedPage}.toList()..sort();
  if (numbers.any((page) => page < 1 || page > 604)) {
    throw const FormatException('Invalid ayah page mapping');
  }
  final reference = QuranAyahReference(
    id: ayah.id,
    surah: ayah.surahNumber,
    ayah: ayah.number,
  );
  final result = <MushafExcerptPage>[];
  for (final number in numbers) {
    final page = await repository.mushafPage(number);
    final regions = page.regions.where((r) => r.ayah == reference).toList()
      ..sort((a, b) => a.readingOrder.compareTo(b.readingOrder));
    if (regions.isEmpty ||
        regions.any(
          (r) =>
              r.width <= 0 ||
              r.height <= 0 ||
              !r.x.isFinite ||
              !r.y.isFinite ||
              !r.width.isFinite ||
              !r.height.isFinite ||
              r.x < 0 ||
              r.y < 0 ||
              r.x + r.width > 1 ||
              r.y + r.height > 1,
        )) {
      throw const FormatException('Incomplete ayah image coverage');
    }
    if (result.isNotEmpty &&
        result.first.page.contentVersion != page.contentVersion) {
      throw const FormatException('Mixed Mushaf versions');
    }
    final asset = page.bestAssetFor(pixelWidth, 1);
    if (asset == null) throw const FormatException('Missing Mushaf artwork');
    result.add((
      page: page,
      file: await repository.cachedMushafPageAsset(page, asset),
      regions: regions,
    ));
  }
  return result;
}

class MushafAyahExcerpt extends ConsumerStatefulWidget {
  const MushafAyahExcerpt({required this.ayah, required this.page, super.key});
  final QuranAyah ayah;
  final int page;

  @override
  ConsumerState<MushafAyahExcerpt> createState() => _MushafAyahExcerptState();
}

class _MushafAyahExcerptState extends ConsumerState<MushafAyahExcerpt> {
  String? _key;
  Future<List<MushafExcerptPage>>? _pages;
  Future<List<MushafPageData>>? _foundationPages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant MushafAyahExcerpt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final width =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final repository = ref.read(selectedMushafRepositoryProvider);
    final identity = ref.read(selectedMushafIdentityProvider);
    final key =
        '${identity.code}:${identity.isFoundation ? repository.foundationVersion : ''}:${widget.ayah.id}:${widget.page}:$width';
    if (_key == key) return;
    _key = key;
    if (identity.isFoundation) {
      _foundationPages = () async {
        final key = '${widget.ayah.surahNumber}:${widget.ayah.number}';
        final numbers = (await repository.foundationPageIndex())[key];
        if (numbers == null || numbers.isEmpty) {
          throw const FormatException('Missing verse pages');
        }
        final pages = await Future.wait(numbers.map(repository.mushafPage));
        if (pages.any(
          (page) =>
              page.foundation == null ||
              !page.ayahReferences.any((ref) => ref.key == key),
        )) {
          throw const FormatException('Incomplete verse coverage');
        }
        return pages;
      }();
      return;
    }
    _foundationPages = null;
    _pages = loadMushafExcerpt(
      repository: repository,
      ayah: widget.ayah,
      tappedPage: widget.page,
      pixelWidth: width,
    );
  }

  Widget _fallback() => Column(
    children: <Widget>[
      MushafAyahText(text: widget.ayah.textUthmani),
      const SizedBox(height: 4),
      Text(
        context.l10n.textMode,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedMushafRepositoryProvider);
    _load();
    if (_foundationPages != null) {
      final reference = QuranAyahReference(
        id: widget.ayah.id,
        surah: widget.ayah.surahNumber,
        ayah: widget.ayah.number,
      );
      return FutureBuilder<List<MushafPageData>>(
        future: _foundationPages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return IqroAsyncError(
              title: context.l10n.noQuranData,
              message: context.l10n.networkError,
              onRetry: () => setState(() {
                _key = null;
                _load();
              }),
            );
          }
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return const SizedBox(height: 120, child: IqroLoading());
          }
          return Semantics(
            label: widget.ayah.textUthmani,
            textDirection: TextDirection.rtl,
            child: ColoredBox(
              color: mushafPaperColor,
              child: Column(
                children: [
                  for (final page in snapshot.data!)
                    FoundationMushafPageContent(
                      key: ValueKey('${page.number}:${page.contentVersion}'),
                      page: page.foundation!,
                      selected: reference,
                      playing: null,
                      excerpt: true,
                      onSelect: (_) {},
                      onOpen: (_) {},
                      onBackgroundTap: () {},
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
    return FutureBuilder<List<MushafExcerptPage>>(
      future: _pages,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _fallback();
        if (!snapshot.hasData) {
          return const SizedBox(height: 120, child: IqroLoading());
        }
        return Semantics(
          label: widget.ayah.textUthmani,
          textDirection: TextDirection.rtl,
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              decoration: BoxDecoration(
                color: mushafPaperColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFC7BBA7)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final item in snapshot.data!)
                      _MushafExcerptImage(
                        key: ValueKey('${item.file.path}:${widget.ayah.id}'),
                        item: item,
                        width: constraints.maxWidth,
                        fallback: _fallback(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MushafExcerptImage extends StatefulWidget {
  const _MushafExcerptImage({
    required this.item,
    required this.width,
    required this.fallback,
    super.key,
  });
  final MushafExcerptPage item;
  final double width;
  final Widget fallback;

  @override
  State<_MushafExcerptImage> createState() => _MushafExcerptImageState();
}

class _MushafExcerptImageState extends State<_MushafExcerptImage> {
  List<Rect> _crops = const [];

  @override
  Widget build(BuildContext context) => MushafRaster(
    file: widget.item.file,
    cropRegions: [
      for (final r in widget.item.regions)
        Rect.fromLTWH(r.x, r.y, r.width, r.height),
    ],
    onVerifiedCrops: (crops) => setState(() => _crops = crops),
    fallback: widget.fallback,
    builder: (image) {
      if (_crops.length != widget.item.regions.length) {
        return _MushafContextExcerpt(
          key: ValueKey('${widget.item.file.path}:${widget.width}'),
          image: image,
          item: widget.item,
          width: widget.width,
        );
      }
      // Keep all fragments at one scale, never enlarge a short word to full width.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final crop in _crops)
            Builder(
              builder: (context) {
                final width = widget.width * crop.width;
                final height =
                    widget.width * crop.height * image.height / image.width;
                final layout = MushafRasterLayout(
                  size: Size(width, height),
                  bands: [
                    (
                      source: crop,
                      destination: Rect.fromLTWH(0, 0, width, height),
                    ),
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: MushafRasterPainter(
                          image: image,
                          layout: layout,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

/// Overlapping line diacritics cannot safely be separated into standalone
/// strips. Show the untouched image in a scrollable viewport instead; the
/// selected ayah stays highlighted and every surrounding pixel remains intact.
class _MushafContextExcerpt extends StatefulWidget {
  const _MushafContextExcerpt({
    required this.image,
    required this.item,
    required this.width,
    super.key,
  });
  final ui.Image image;
  final MushafExcerptPage item;
  final double width;

  @override
  State<_MushafContextExcerpt> createState() => _MushafContextExcerptState();
}

class _MushafContextExcerptState extends State<_MushafContextExcerpt> {
  late final ScrollController _scroll;
  late final double _height;
  late final double _viewportHeight;

  @override
  void initState() {
    super.initState();
    _height = widget.width * widget.image.height / widget.image.width;
    final regions = widget.item.regions;
    final top = regions.map((r) => r.y).reduce(math.min);
    final bottom = regions.map((r) => r.y + r.height).reduce(math.max);
    _viewportHeight = math.min(
      _height,
      ((_height * (bottom - top + .04)).clamp(100.0, 300.0)),
    );
    _scroll = ScrollController(
      initialScrollOffset: ((_height * (top - .02)).clamp(
        0.0,
        math.max(0.0, _height - _viewportHeight),
      )),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = MushafRasterLayout(
      size: Size(widget.width, _height),
      bands: [
        (
          source: const Rect.fromLTWH(0, 0, 1, 1),
          destination: Rect.fromLTWH(0, 0, widget.width, _height),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${context.l10n.mushafMode} · ${context.l10n.page} ${widget.item.page.number}',
          style: const TextStyle(color: mushafAccentColor, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _viewportHeight,
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              primary: false,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: widget.width,
                height: _height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MushafRasterPainter(
                      image: widget.image,
                      layout: layout,
                    ),
                    foregroundPainter: _ExcerptHighlight(
                      layout,
                      widget.item.regions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExcerptHighlight extends CustomPainter {
  const _ExcerptHighlight(this.layout, this.regions);
  final MushafRasterLayout layout;
  final List<MushafAyahRegion> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x26857154);
    for (final region in regions) {
      canvas.drawPath(layout.regionPath(region), fill);
    }
  }

  @override
  bool shouldRepaint(_ExcerptHighlight oldDelegate) =>
      layout != oldDelegate.layout || regions != oldDelegate.regions;
}
