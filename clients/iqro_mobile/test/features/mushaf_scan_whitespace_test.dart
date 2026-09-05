import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_scan_whitespace.dart';

void main() {
  test('excerpt crop snaps away from diacritics on all four sides', () {
    final rgba = Uint8List(200 * 1000 * 4)..fillRange(0, 200 * 1000 * 4, 255);
    for (var y = 197; y < 255; y++) {
      for (var x = 50; x < 170; x++) {
        rgba[(y * 200 + x) * 4] = 0;
      }
    }
    final crops = findMushafCrops(
      rgba,
      width: 200,
      height: 1000,
      regions: [const Rect.fromLTRB(.245, .2, .86, .27)],
    );
    expect(crops, hasLength(1));
    expect(crops.single.top, lessThan(.197));
    expect(crops.single.left, lessThan(.25));
    expect(crops.single.bottom, greaterThan(.255));
    expect(crops.single.right, greaterThan(.85));
  });

  test('excerpt rejects a crop when no safe blank edge exists nearby', () {
    final rgba = Uint8List(200 * 1000 * 4)..fillRange(0, 200 * 1000 * 4, 255);
    for (var y = 170; y < 230; y++) {
      rgba[(y * 200 + 90) * 4] = 0;
    }
    expect(
      findMushafCrops(
        rgba,
        width: 200,
        height: 1000,
        regions: [const Rect.fromLTRB(.2, .2, .9, .3)],
      ),
      isEmpty,
    );
  });
  test('moves a metadata seam away from even a single diacritic pixel', () {
    final rgba = Uint8List(20 * 1000 * 4)..fillRange(0, 20 * 1000 * 4, 255);
    for (var y = 497; y <= 503; y++) {
      rgba[(y * 20 + 10) * 4] = 0;
    }
    final cuts = findMushafWhitespace(
      rgba,
      width: 20,
      height: 1000,
      candidates: [.5],
    );
    expect(cuts, [.495]);
    for (final cut in cuts) {
      final row = (cut * 1000).round();
      for (var y = row - 1; y <= row + 1; y++) {
        expect(rgba[(y * 20 + 10) * 4], 255);
      }
    }
  });

  test(
    'rejects a seam without a complete blank band, including page frames',
    () {
      final rgba = Uint8List(20 * 1000 * 4)..fillRange(0, 20 * 1000 * 4, 255);
      for (var y = 475; y <= 525; y++) {
        rgba[y * 20 * 4] = 0;
      }
      expect(
        findMushafWhitespace(rgba, width: 20, height: 1000, candidates: [.5]),
        isEmpty,
      );
      expect(
        findMushafWhitespace(
          Uint8List(1),
          width: 20,
          height: 1000,
          candidates: [.5],
        ),
        isEmpty,
      );
    },
  );
}
