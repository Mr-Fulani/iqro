import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

typedef MushafWhitespaceRequest = ({
  TransferableTypedData pixels,
  int width,
  int height,
  List<double> candidates,
});

typedef MushafCropRequest = ({
  TransferableTypedData pixels,
  int width,
  int height,
  List<Rect> regions,
});

List<Rect> verifyMushafCrops(MushafCropRequest request) => findMushafCrops(
  request.pixels.materialize().asUint8List(),
  width: request.width,
  height: request.height,
  regions: request.regions,
);

/// Snaps each hit rectangle to nearby blank pixel boundaries. A crop with no
/// safe boundary is rejected, never returned with clipped letters/diacritics.
List<Rect> findMushafCrops(
  Uint8List rgba, {
  required int width,
  required int height,
  required List<Rect> regions,
}) {
  if (width < 1 || height < 1 || rgba.length != width * height * 4) return [];
  bool ink(int x, int y) {
    final offset = (y * width + x) * 4;
    return rgba[offset + 3] > 8 &&
        math.min(rgba[offset], math.min(rgba[offset + 1], rgba[offset + 2])) <
            248;
  }

  int? nearest(int origin, int radius, int limit, bool Function(int) blank) {
    for (var d = 0; d <= radius; d++) {
      for (final coordinate in [origin - d, origin + d]) {
        if (coordinate < 1 || coordinate >= limit - 1) continue;
        if (blank(coordinate - 1) &&
            blank(coordinate) &&
            blank(coordinate + 1)) {
          return coordinate;
        }
      }
    }
    return null;
  }

  final result = <Rect>[];
  for (final region in regions) {
    final left = (region.left * width).floor().clamp(0, width - 1);
    final right = (region.right * width).ceil().clamp(1, width);
    bool rowBlank(int y) {
      for (var x = left; x < right; x++) {
        if (ink(x, y)) return false;
      }
      return true;
    }

    final radiusY = math.max(
      1,
      (height * math.min(.018, region.height * .28)).floor(),
    );
    final top = nearest(
      (region.top * height).round(),
      radiusY,
      height,
      rowBlank,
    );
    final bottom = nearest(
      (region.bottom * height).round(),
      radiusY,
      height,
      rowBlank,
    );
    if (top == null || bottom == null || bottom <= top) return [];
    bool columnBlank(int x) {
      for (var y = top; y < bottom; y++) {
        if (ink(x, y)) return false;
      }
      return true;
    }

    final radiusX = math.max(
      1,
      (width * math.min(.012, region.width * .12)).floor(),
    );
    final safeLeft = nearest(left, radiusX, width, columnBlank);
    final safeRight = nearest(right, radiusX, width, columnBlank);
    if (safeLeft == null || safeRight == null || safeRight <= safeLeft) {
      return [];
    }
    result.add(
      Rect.fromLTRB(
        safeLeft / width,
        top / height,
        safeRight / width,
        bottom / height,
      ),
    );
  }
  return result;
}

/// Hit-map rectangles are not glyph bounds. Only a genuinely blank raster
/// row may separate scan bands; even a single dark diacritic prevents a cut.
/// Runs outside the UI isolate. The result retains no pixel buffer.
List<double> verifyMushafWhitespace(MushafWhitespaceRequest request) =>
    findMushafWhitespace(
      request.pixels.materialize().asUint8List(),
      width: request.width,
      height: request.height,
      candidates: request.candidates,
    );

List<double> findMushafWhitespace(
  Uint8List rgba, {
  required int width,
  required int height,
  required List<double> candidates,
}) {
  if (width < 1 || height < 1 || rgba.length != width * height * 4) {
    return const [];
  }
  final blankRows = <int, bool>{};
  bool blank(int row) => blankRows.putIfAbsent(row, () {
    for (var x = 0; x < width; x++) {
      final offset = (row * width + x) * 4;
      if (rgba[offset + 3] > 8 &&
          math.min(rgba[offset], math.min(rgba[offset + 1], rgba[offset + 2])) <
              248) {
        return false;
      }
    }
    return true;
  });

  final result = <double>[];
  // Search stays inside the inter-line neighbourhood, not the next line.
  final radius = math.max(1, (height * .018).floor());
  for (final candidate in candidates) {
    if (!candidate.isFinite || candidate <= 0 || candidate >= 1) continue;
    final origin = (candidate * height).round();
    int? cut;
    for (var distance = 0; distance <= radius && cut == null; distance++) {
      for (final row in <int>[origin - distance, origin + distance]) {
        if (row < 2 || row >= height - 2) continue;
        // Keep interpolation away from ink on BOTH sides of the seam.
        if (blank(row - 1) && blank(row) && blank(row + 1)) {
          cut = row;
          break;
        }
      }
    }
    if (cut != null) {
      final value = cut / height;
      if (result.every((other) => (other - value).abs() > .001)) {
        result.add(value);
      }
    }
  }
  return result..sort();
}
