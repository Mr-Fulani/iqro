import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'quran_models.dart';

typedef MushafScanBand = ({Rect source, Rect destination});

/// Maps the original scan to the screen without ever stretching the glyphs.
/// Extra portrait height becomes space only at verified shared line boundaries.
class MushafScanLayout {
  const MushafScanLayout({required this.size, required this.bands});

  factory MushafScanLayout.page({
    required MushafPageData page,
    required Size size,
    required bool portrait,
    List<double> verifiedCuts = const [],
  }) {
    final trim =
        portrait &&
            page.number > 2 &&
            page.regions.isNotEmpty &&
            page.regions.every((r) => r.x >= .025 && r.x + r.width <= .975)
        ? .025
        : 0.0;
    final sourceWidth = page.imageWidth * (1 - trim * 2);
    final scale = portrait
        ? math.min(size.width / sourceWidth, size.height / page.imageHeight)
        : size.width / sourceWidth;
    final imageHeight = page.imageHeight * scale;
    final imageWidth = sourceWidth * scale;
    final spare = math.max(0.0, size.height - imageHeight);
    final cuts = portrait && page.number > 2 && spare > 1
        ? verifiedCuts
        : const <double>[];
    // Metadata alone is insufficient: its hit areas can cross diacritics.
    // Until raster whitespace is verified, keep the complete scan intact.
    final spread = cuts.length >= 8;
    final edges = <double>[0, if (spread) ...cuts, 1];
    final gap = spread ? spare / cuts.length : 0.0;
    final top = spread ? 0.0 : spare / 2;
    return MushafScanLayout(
      size: size,
      bands: <MushafScanBand>[
        for (var i = 0; i < edges.length - 1; i++)
          (
            source: Rect.fromLTRB(trim, edges[i], 1 - trim, edges[i + 1]),
            destination: Rect.fromLTWH(
              (size.width - imageWidth) / 2,
              top + edges[i] * imageHeight + i * gap,
              imageWidth,
              (edges[i + 1] - edges[i]) * imageHeight,
            ),
          ),
      ],
    );
  }

  final Size size;
  final List<MushafScanBand> bands;

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

  Offset displayPoint(Offset point, {double? regionCenterY}) {
    final y = regionCenterY ?? point.dy;
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
    // A verified whitespace cut may shift slightly from the hit-map boundary.
    // Split the highlight with the very same bands; never paint over the gap.
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

List<double> mushafLineBoundaries(List<MushafAyahRegion> regions) {
  const epsilon = .000002;
  final result = <double>[];
  for (final region in regions) {
    final boundary = region.y + region.height;
    if (!boundary.isFinite || boundary <= 0 || boundary >= 1) continue;
    if (!regions.any((r) => (r.y - boundary).abs() < epsilon)) continue;
    if (regions.any(
      (r) => r.y < boundary - epsilon && r.y + r.height > boundary + epsilon,
    )) {
      continue;
    }
    if (!result.any((y) => (y - boundary).abs() < epsilon)) {
      result.add(boundary);
    }
  }
  return result..sort();
}
