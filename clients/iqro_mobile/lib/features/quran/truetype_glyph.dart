import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// One TrueType glyph outline in font units, with y pointing down.
class GlyphOutline {
  GlyphOutline(this.path, this.bounds);
  final Path path;
  final Rect bounds;
}

/// Reads a simple glyph's quadratic outline straight from `glyf`/`loca`.
///
/// The QUL surah-header glyphs have thousands of points that Skia's glyph
/// rasterizer partly drops; filling the same outline as a path is exact.
/// Returns null for empty or composite glyphs; malformed data throws.
///
/// With [keep], only contours whose bounds it accepts are drawn, and the
/// outline's bounds are theirs; null when it accepts none.
GlyphOutline? readTrueTypeGlyph(
  ByteData font,
  int glyphId, {
  bool Function(Rect contour)? keep,
}) {
  final tables = <String, int>{};
  for (var index = 0; index < font.getUint16(4); index++) {
    final record = 12 + index * 16;
    tables[String.fromCharCodes(
      Uint8List.sublistView(font, record, record + 4),
    )] = font.getUint32(
      record + 8,
    );
  }
  final head = tables['head'];
  final maxp = tables['maxp'];
  final loca = tables['loca'];
  final glyf = tables['glyf'];
  if (head == null || maxp == null || loca == null || glyf == null) {
    return null;
  }
  if (glyphId < 0 || glyphId >= font.getUint16(maxp + 4)) return null;
  final longOffsets = font.getInt16(head + 50) == 1;
  int location(int id) => longOffsets
      ? font.getUint32(loca + id * 4)
      : font.getUint16(loca + id * 2) * 2;
  if (location(glyphId + 1) <= location(glyphId)) return null;
  final start = glyf + location(glyphId);
  final contours = font.getInt16(start);
  if (contours <= 0) return null;
  final ends = [
    for (var index = 0; index < contours; index++)
      font.getUint16(start + 10 + index * 2),
  ];
  final points = ends.last + 1;
  var offset = start + 10 + contours * 2;
  offset += 2 + font.getUint16(offset);
  final flags = Uint8List(points);
  for (var index = 0; index < points;) {
    final flag = font.getUint8(offset++);
    flags[index++] = flag;
    if (flag & 8 != 0) {
      for (var repeat = font.getUint8(offset++); repeat > 0; repeat--) {
        flags[index++] = flag;
      }
    }
  }
  List<double> coordinates(int short, int sameOrPositive) {
    final values = Float64List(points);
    var value = 0;
    for (var index = 0; index < points; index++) {
      final flag = flags[index];
      if (flag & short != 0) {
        final delta = font.getUint8(offset++);
        value += flag & sameOrPositive != 0 ? delta : -delta;
      } else if (flag & sameOrPositive == 0) {
        value += font.getInt16(offset);
        offset += 2;
      }
      values[index] = value.toDouble();
    }
    return values;
  }

  final xs = coordinates(2, 16);
  final ys = coordinates(4, 32);
  final path = Path();
  Rect? kept;
  var first = 0;
  for (final last in ends) {
    final count = last - first + 1;
    if (keep != null) {
      var left = double.infinity, top = double.infinity;
      var right = double.negativeInfinity, bottom = double.negativeInfinity;
      for (var index = first; index <= last; index++) {
        left = math.min(left, xs[index]);
        right = math.max(right, xs[index]);
        top = math.min(top, -ys[index]);
        bottom = math.max(bottom, -ys[index]);
      }
      final bounds = Rect.fromLTRB(left, top, right, bottom);
      if (!keep(bounds)) {
        first = last + 1;
        continue;
      }
      kept = kept?.expandToInclude(bounds) ?? bounds;
    }
    Offset at(int index) =>
        Offset(xs[first + index % count], -ys[first + index % count]);
    bool onCurve(int index) => flags[first + index % count] & 1 != 0;
    var startIndex = 0;
    while (startIndex < count && !onCurve(startIndex)) {
      startIndex++;
    }
    // A contour of off-curve points starts on their implied midpoint.
    final allOff = startIndex == count;
    final origin = allOff
        ? Offset.lerp(at(count - 1), at(0), .5)!
        : at(startIndex);
    path.moveTo(origin.dx, origin.dy);
    Offset? control;
    void to(Offset point) => control == null
        ? path.lineTo(point.dx, point.dy)
        : path.quadraticBezierTo(control.dx, control.dy, point.dx, point.dy);
    for (
      var index = allOff ? 0 : startIndex + 1;
      index < (allOff ? count : startIndex + count);
      index++
    ) {
      final point = at(index);
      if (onCurve(index)) {
        to(point);
        control = null;
      } else {
        if (control != null) to(Offset.lerp(control, point, .5)!);
        control = point;
      }
    }
    to(origin);
    path.close();
    first = last + 1;
  }
  if (keep != null) return kept == null ? null : GlyphOutline(path, kept);
  return GlyphOutline(
    path,
    Rect.fromLTRB(
      font.getInt16(start + 2).toDouble(),
      -font.getInt16(start + 8).toDouble(),
      font.getInt16(start + 6).toDouble(),
      -font.getInt16(start + 4).toDouble(),
    ),
  );
}
