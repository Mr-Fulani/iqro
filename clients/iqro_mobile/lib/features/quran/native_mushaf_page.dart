import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'mushaf_paper.dart';
import 'mushaf_raster.dart';
import 'mushaf_scan_layout.dart';
import 'quran_models.dart';

typedef MushafPageLayout = ({
  double width,
  double height,
  double horizontalOffset,
  bool fillsLandscapeWidth,
});

// The scanned Madani pages include a narrow paper gutter around their frame.
// In landscape we let that gutter bleed outside the viewport so the readable
// page reaches both screen edges without changing the scan's aspect ratio.
const mushafLandscapeBleedFactor = 1.12;

class MushafViewportOrientation {
  bool? _landscape;

  bool update(Size viewport) {
    final next = viewport.width > viewport.height;
    final changed = _landscape != null && _landscape != next;
    _landscape = next;
    return changed;
  }
}

MushafPageLayout calculateMushafPageLayout({
  required Size viewport,
  required Size source,
  double landscapeBleedFactor = mushafLandscapeBleedFactor,
}) {
  final viewportWidth = math.max(0, viewport.width).toDouble();
  final viewportHeight = math.max(0, viewport.height).toDouble();
  final sourceWidth = math.max(1, source.width).toDouble();
  final sourceHeight = math.max(1, source.height).toDouble();
  final fillsLandscapeWidth = viewportWidth > viewportHeight;
  final scale = fillsLandscapeWidth
      ? (viewportWidth * landscapeBleedFactor) / sourceWidth
      : math.min(viewportWidth / sourceWidth, viewportHeight / sourceHeight);
  return (
    width: sourceWidth * scale,
    height: sourceHeight * scale,
    horizontalOffset: (viewportWidth - sourceWidth * scale) / 2,
    fillsLandscapeWidth: fillsLandscapeWidth,
  );
}

class NativeMushafPageController {
  ValueChanged<double>? _setZoom;

  void setZoom(double value) {
    _setZoom?.call(value.clamp(1.0, 3.0));
  }
}

class NativeMushafPage extends ConsumerStatefulWidget {
  const NativeMushafPage({
    required this.page,
    required this.controller,
    required this.selectedAyah,
    required this.playingAyah,
    required this.onSelectAyah,
    required this.onOpenAyah,
    required this.onBackgroundTap,
    required this.onScale,
    this.surahs = const <Surah>[],
    this.divisions = const <QuranDivision>[],
    super.key,
  });

  final int page;
  final NativeMushafPageController controller;
  final QuranAyahReference? selectedAyah;
  final QuranAyahReference? playingAyah;
  final ValueChanged<QuranAyahReference> onSelectAyah;
  final ValueChanged<QuranAyahReference> onOpenAyah;
  final VoidCallback onBackgroundTap;
  final ValueChanged<double> onScale;
  final List<Surah> surahs;
  final List<QuranDivision> divisions;

  @override
  ConsumerState<NativeMushafPage> createState() => _NativeMushafPageState();
}

class _NativeMushafPageState extends ConsumerState<NativeMushafPage> {
  final _transformationController = TransformationController();
  final _viewportOrientation = MushafViewportOrientation();
  var _scale = 1.0;
  var _orientationRevision = 0;
  var _viewportSize = Size.zero;
  String? _assetCacheKey;
  Future<File>? _assetFile;
  String? _resolutionRefreshKey;
  List<double> _verifiedCuts = const [];

  @override
  void initState() {
    super.initState();
    widget.controller._setZoom = _applyZoom;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewportOrientation.update(MediaQuery.sizeOf(context))) return;

    // A landscape page can carry a large vertical translation (or user zoom).
    // Reusing that matrix after rotation can move the portrait page completely
    // outside its viewport, so every orientation change starts from its own
    // canonical fit.
    _transformationController.value = Matrix4.identity();
    _scale = 1;
    final revision = ++_orientationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _orientationRevision) return;
      widget.onScale(1);
    });
  }

  @override
  void didUpdateWidget(covariant NativeMushafPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._setZoom = null;
      widget.controller._setZoom = _applyZoom;
    }
  }

  @override
  void dispose() {
    widget.controller._setZoom = null;
    _transformationController.dispose();
    super.dispose();
  }

  void _applyZoom(double value) {
    final scale = value.clamp(1.0, 3.0);
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        _viewportSize.width * (1 - scale) / 2,
        _viewportSize.height * (1 - scale) / 2,
        0,
      );
    _transformationController.value = matrix;
    if (mounted) setState(() => _scale = scale);
  }

  void _loadAsset(MushafPageData pageData, MushafAsset asset) {
    final cacheKey =
        '${pageData.contentVersion}:${asset.width}:${asset.sha256}';
    if (_assetCacheKey == cacheKey) return;
    _assetCacheKey = cacheKey;
    _verifiedCuts = const [];
    _assetFile = ref
        .read(selectedMushafRepositoryProvider)
        .cachedMushafPageAsset(pageData, asset);
  }

  void _retryAsset(MushafPageData pageData, MushafAsset asset) {
    setState(() {
      _assetCacheKey = null;
      _assetFile = null;
      _loadAsset(pageData, asset);
    });
  }

  void _refreshResolutionIfNeeded(
    MushafPageData pageData, {
    required double logicalWidth,
    required double devicePixelRatio,
  }) {
    if (!pageData.needsHigherResolution(logicalWidth, devicePixelRatio)) return;
    final minimumWidth = (logicalWidth * devicePixelRatio).ceil();
    final key =
        '${pageData.contentVersion}:${pageData.number}:'
        '${pageData.maximumAssetWidth}:$minimumWidth';
    if (_resolutionRefreshKey == key) return;
    _resolutionRefreshKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resolutionRefreshKey != key) return;
      unawaited(() async {
        final changed = await ref
            .read(selectedMushafRepositoryProvider)
            .refreshMushafPageResolution(pageData, minimumWidth: minimumWidth);
        if (changed && mounted && _resolutionRefreshKey == key) {
          ref.invalidate(mushafPageProvider(widget.page));
        }
      }());
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mushafPageProvider(widget.page));
    return data.when(
      loading: () =>
          const ColoredBox(color: mushafPaperColor, child: IqroLoading()),
      error: (error, stack) => ColoredBox(
        color: mushafPaperColor,
        child: IqroAsyncError(
          title: context.l10n.noQuranData,
          message: context.l10n.networkError,
          onRetry: () => ref.invalidate(mushafPageProvider(widget.page)),
        ),
      ),
      data: _buildPage,
    );
  }

  Widget _buildPage(MushafPageData pageData) {
    final viewport = MediaQuery.sizeOf(context);
    final portrait = viewport.height >= viewport.width;
    final surahNumber = pageData.firstAyahReference?.surah;
    final surah = widget.surahs
        .where((s) => s.number == surahNumber)
        .firstOrNull;
    final juz = widget.divisions
        .where((d) => widget.page >= d.startPage && widget.page <= d.endPage)
        .firstOrNull;
    final locale = Localizations.localeOf(context).languageCode;
    return ColoredBox(
      color: mushafPaperColor,
      child: Column(
        children: <Widget>[
          if (portrait)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      surah?.nameFor(locale) ??
                          '${context.l10n.surah} ${surahNumber ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: mushafInkColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${context.l10n.juz} ${juz?.number ?? '—'}',
                    style: const TextStyle(
                      color: mushafInkColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildScan(pageData)),
          if (portrait)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 14),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EBE1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFC7BBA7),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.bookmark_border_rounded,
                        color: mushafAccentColor,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.page}',
                        style: const TextStyle(
                          color: mushafInkColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScan(MushafPageData pageData) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = calculateMushafPageLayout(
          landscapeBleedFactor: pageData.editionCode == 'madani-hafs'
              ? mushafLandscapeBleedFactor
              : 1,
          viewport: Size(constraints.maxWidth, constraints.maxHeight),
          source: Size(
            pageData.imageWidth.toDouble(),
            pageData.imageHeight.toDouble(),
          ),
        );
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final asset = pageData.bestAssetFor(
          layout.fillsLandscapeWidth ? layout.width : _viewportSize.width,
          devicePixelRatio,
        );
        if (asset == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                context.l10n.noQuranData,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        _refreshResolutionIfNeeded(
          pageData,
          logicalWidth: layout.width,
          devicePixelRatio: devicePixelRatio,
        );
        _loadAsset(pageData, asset);
        final scanLayout = MushafScanLayout.page(
          page: pageData,
          size: layout.fillsLandscapeWidth
              ? Size(layout.width, layout.height)
              : _viewportSize,
          portrait: !layout.fillsLandscapeWidth,
          verifiedCuts: _verifiedCuts,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onBackgroundTap,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              alignment: layout.fillsLandscapeWidth
                  ? Alignment.topCenter
                  : Alignment.center,
              minScale: 1,
              maxScale: 3,
              panEnabled: _scale > 1.01 || layout.fillsLandscapeWidth,
              panAxis: layout.fillsLandscapeWidth && _scale <= 1.01
                  ? PanAxis.vertical
                  : PanAxis.free,
              scaleEnabled: true,
              clipBehavior: Clip.none,
              onInteractionEnd: (_) {
                final scale = _transformationController.value
                    .getMaxScaleOnAxis();
                setState(() => _scale = scale);
                widget.onScale(scale);
              },
              child: Transform.translate(
                offset: Offset(
                  layout.fillsLandscapeWidth ? layout.horizontalOffset : 0,
                  0,
                ),
                child: SizedBox(
                  width: scanLayout.size.width,
                  height: scanLayout.size.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final point = scanLayout.sourcePointAt(
                        details.localPosition,
                      );
                      final ayah = point == null
                          ? null
                          : pageData.ayahAt(point.dx, point.dy);
                      if (ayah == null) {
                        widget.onBackgroundTap();
                      } else {
                        widget.onSelectAyah(ayah);
                      }
                    },
                    onLongPressStart: (details) {
                      final point = scanLayout.sourcePointAt(
                        details.localPosition,
                      );
                      final ayah = point == null
                          ? null
                          : pageData.ayahAt(point.dx, point.dy);
                      if (ayah != null) widget.onOpenAyah(ayah);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        FutureBuilder<File>(
                          future: _assetFile,
                          builder: (context, snapshot) {
                            final file = snapshot.data;
                            if (file != null) {
                              return RepaintBoundary(
                                child: Semantics(
                                  label:
                                      '${context.l10n.mushafMode}, ${context.l10n.page} ${widget.page}',
                                  image: true,
                                  child: MushafRaster(
                                    file: file,
                                    cutCandidates: widget.page > 2
                                        ? mushafLineBoundaries(pageData.regions)
                                        : const [],
                                    onVerifiedCuts: (cuts) {
                                      if (mounted &&
                                          !listEquals(_verifiedCuts, cuts)) {
                                        setState(() => _verifiedCuts = cuts);
                                      }
                                    },
                                    builder: (image) => CustomPaint(
                                      painter: MushafScanPainter(
                                        image: image,
                                        layout: scanLayout,
                                      ),
                                    ),
                                    fallback: IqroAsyncError(
                                      title: context.l10n.noQuranData,
                                      onRetry: () =>
                                          _retryAsset(pageData, asset),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return IqroAsyncError(
                                title: context.l10n.noQuranData,
                                message: context.l10n.networkError,
                                onRetry: () => _retryAsset(pageData, asset),
                              );
                            }
                            return const IqroLoading();
                          },
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _AyahRegionPainter(
                              regions: pageData.regions,
                              selectedAyah: widget.selectedAyah,
                              playingAyah: widget.playingAyah,
                              layout: scanLayout,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AyahRegionPainter extends CustomPainter {
  const _AyahRegionPainter({
    required this.regions,
    required this.selectedAyah,
    required this.playingAyah,
    required this.layout,
  });

  final List<MushafAyahRegion> regions;
  final QuranAyahReference? selectedAyah;
  final QuranAyahReference? playingAyah;
  final MushafScanLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final selectedFill = Paint()
      ..color = const Color(0x33857154)
      ..style = PaintingStyle.fill;
    final selectedStroke = Paint()
      ..color = const Color(0x99857154)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final playingFill = Paint()
      ..color = const Color(0x520B8068)
      ..style = PaintingStyle.fill;
    final playingStroke = Paint()
      ..color = const Color(0xC20B6B57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final region in regions) {
      final selected = region.ayah == selectedAyah;
      final playing = region.ayah == playingAyah;
      if (!selected && !playing) continue;
      final path = layout.regionPath(region);
      canvas.drawPath(path, playing ? playingFill : selectedFill);
      canvas.drawPath(path, playing ? playingStroke : selectedStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _AyahRegionPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.selectedAyah != selectedAyah ||
        oldDelegate.playingAyah != playingAyah ||
        !identical(oldDelegate.regions, regions);
  }
}
