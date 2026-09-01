import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import 'quran_models.dart';

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
    required this.onBackgroundTap,
    required this.onScale,
    super.key,
  });

  final int page;
  final NativeMushafPageController controller;
  final QuranAyahReference? selectedAyah;
  final QuranAyahReference? playingAyah;
  final ValueChanged<QuranAyahReference> onSelectAyah;
  final VoidCallback onBackgroundTap;
  final ValueChanged<double> onScale;

  @override
  ConsumerState<NativeMushafPage> createState() => _NativeMushafPageState();
}

class _NativeMushafPageState extends ConsumerState<NativeMushafPage> {
  final _transformationController = TransformationController();
  var _scale = 1.0;
  var _viewportSize = Size.zero;
  String? _assetCacheKey;
  Future<File>? _assetFile;

  @override
  void initState() {
    super.initState();
    widget.controller._setZoom = _applyZoom;
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
    _assetFile = ref
        .read(quranRepositoryProvider)
        .cachedMushafPageAsset(pageData, asset);
  }

  void _retryAsset(MushafPageData pageData, MushafAsset asset) {
    setState(() {
      _assetCacheKey = null;
      _assetFile = null;
      _loadAsset(pageData, asset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mushafPageProvider(widget.page));
    return data.when(
      loading: () =>
          const ColoredBox(color: Color(0xFFEDE6D3), child: IqroLoading()),
      error: (error, stack) => ColoredBox(
        color: const Color(0xFFEDE6D3),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final sourceWidth = math.max(1, pageData.imageWidth).toDouble();
        final sourceHeight = math.max(1, pageData.imageHeight).toDouble();
        final fittedScale = math.min(
          constraints.maxWidth / sourceWidth,
          constraints.maxHeight / sourceHeight,
        );
        final fittedWidth = sourceWidth * fittedScale;
        final fittedHeight = sourceHeight * fittedScale;
        final asset = pageData.bestAssetFor(
          fittedWidth,
          MediaQuery.devicePixelRatioOf(context),
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
        _loadAsset(pageData, asset);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onBackgroundTap,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1,
              maxScale: 3,
              panEnabled: _scale > 1.01,
              scaleEnabled: true,
              clipBehavior: Clip.none,
              onInteractionEnd: (_) {
                final scale = _transformationController.value
                    .getMaxScaleOnAxis();
                setState(() => _scale = scale);
                widget.onScale(scale);
              },
              child: Center(
                child: SizedBox(
                  width: fittedWidth,
                  height: fittedHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final normalizedX =
                          details.localPosition.dx / fittedWidth;
                      final normalizedY =
                          details.localPosition.dy / fittedHeight;
                      final ayah = pageData.ayahAt(normalizedX, normalizedY);
                      if (ayah == null) {
                        widget.onBackgroundTap();
                      } else {
                        widget.onSelectAyah(ayah);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        FutureBuilder<File>(
                          future: _assetFile,
                          builder: (context, snapshot) {
                            final file = snapshot.data;
                            if (file != null) {
                              return Image.file(
                                file,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                                semanticLabel:
                                    '${context.l10n.mushafMode}, '
                                    '${context.l10n.page} ${widget.page}',
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
  });

  final List<MushafAyahRegion> regions;
  final QuranAyahReference? selectedAyah;
  final QuranAyahReference? playingAyah;

  @override
  void paint(Canvas canvas, Size size) {
    final selectedFill = Paint()
      ..color = const Color(0x52DCA928)
      ..style = PaintingStyle.fill;
    final selectedStroke = Paint()
      ..color = const Color(0xA6976A05)
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
      final path = _pathFor(region, size);
      canvas.drawPath(path, playing ? playingFill : selectedFill);
      canvas.drawPath(path, playing ? playingStroke : selectedStroke);
    }
  }

  Path _pathFor(MushafAyahRegion region, Size size) {
    final path = Path();
    if (region.polygon.length >= 3) {
      final first = region.polygon.first;
      path.moveTo(first.x * size.width, first.y * size.height);
      for (final point in region.polygon.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      path.close();
      return path;
    }
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          region.x * size.width,
          region.y * size.height,
          region.width * size.width,
          region.height * size.height,
        ),
        const Radius.circular(3),
      ),
    );
    return path;
  }

  @override
  bool shouldRepaint(covariant _AyahRegionPainter oldDelegate) {
    return oldDelegate.selectedAyah != selectedAyah ||
        oldDelegate.playingAyah != playingAyah ||
        !identical(oldDelegate.regions, regions);
  }
}
