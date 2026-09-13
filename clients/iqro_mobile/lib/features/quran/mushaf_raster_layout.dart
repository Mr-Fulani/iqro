import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'quran_models.dart';

typedef MushafRasterBand = ({Rect source, Rect destination});

/// Fits a complete page with one uniform transform, including its whitespace.
/// Screen height and hit-map granularity must never change the typesetting.
class MushafRasterLayout {
  const MushafRasterLayout({required this.size, required this.bands});

  factory MushafRasterLayout.page({
    required MushafPageData page,
    required Size size,
    required bool portrait,
  }) {
    final sourceWidth = page.imageWidth.toDouble();
    final scale = portrait
        ? math.min(size.width / sourceWidth, size.height / page.imageHeight)
        : size.width / sourceWidth;
    final imageHeight = page.imageHeight * scale;
    final imageWidth = sourceWidth * scale;
    final spare = math.max(0.0, size.height - imageHeight);
    return MushafRasterLayout(
      size: size,
      bands: <MushafRasterBand>[
        (
          source: const Rect.fromLTWH(0, 0, 1, 1),
          destination: Rect.fromLTWH(
            (size.width - imageWidth) / 2,
            spare / 2,
            imageWidth,
            imageHeight,
          ),
        ),
      ],
    );
  }

  final Size size;
  final List<MushafRasterBand> bands;

  Offset? sourcePointAt(Offset point) {
    for (final band in bands) {
      final target = band.destination;
      if (!target.contains(point)) continue;
      return Offset(
        band.source.left +
            (point.dx - target.left) / target.width * band.source.width,
        band.source.top +
            (point.dy - target.top) / target.height * band.source.height,
      );
    }
    return null;
  }

  Offset displayPoint(Offset point) {
    final y = point.dy;
    final band = bands.firstWhere(
      (b) => y >= b.source.top && y <= b.source.bottom,
      orElse: () => bands.last,
    );
    return Offset(
      band.destination.left +
          (point.dx - band.source.left) /
              band.source.width *
              band.destination.width,
      band.destination.top +
          (point.dy - band.source.top) /
              band.source.height *
              band.destination.height,
    );
  }

  Path regionPath(MushafAyahRegion region) {
    final points = region.polygon.length >= 3
        ? region.polygon
        : <MushafPoint>[
            MushafPoint(region.x, region.y),
            MushafPoint(region.x + region.width, region.y),
            MushafPoint(region.x + region.width, region.y + region.height),
            MushafPoint(region.x, region.y + region.height),
          ];
    final sourcePath = Path()
      ..addPolygon([for (final p in points) Offset(p.x, p.y)], true);
    final result = Path();
    // Highlight geometry uses exactly the same transform as the page raster.
    for (final band in bands) {
      final fragment = Path.combine(
        PathOperation.intersect,
        sourcePath,
        Path()..addRect(band.source),
      );
      final scaleX = band.destination.width / band.source.width;
      final scaleY = band.destination.height / band.source.height;
      final transform = Matrix4.identity()
        ..setEntry(0, 0, scaleX)
        ..setEntry(1, 1, scaleY)
        ..setEntry(0, 3, band.destination.left - band.source.left * scaleX)
        ..setEntry(1, 3, band.destination.top - band.source.top * scaleY);
      result.addPath(fragment.transform(transform.storage), Offset.zero);
    }
    return result;
  }
}
