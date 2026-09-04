import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';

void main() {
  const source = Size(1200, 1800);

  test('portrait page is contained without changing its aspect ratio', () {
    final layout = calculateMushafPageLayout(
      viewport: const Size(400, 800),
      source: source,
    );

    expect(layout.fillsLandscapeWidth, isFalse);
    expect(layout.width, closeTo(400, .001));
    expect(layout.height, closeTo(600, .001));
    expect(layout.horizontalOffset, closeTo(0, .001));
    expect(layout.width / layout.height, closeTo(2 / 3, .001));
  });

  test('landscape page bleeds scan gutters without changing aspect ratio', () {
    final layout = calculateMushafPageLayout(
      viewport: const Size(800, 400),
      source: source,
    );

    expect(layout.fillsLandscapeWidth, isTrue);
    expect(layout.width, closeTo(896, .001));
    expect(layout.height, closeTo(1344, .001));
    expect(layout.horizontalOffset, closeTo(-48, .001));
    expect(layout.width, greaterThan(800));
    expect(layout.width / layout.height, closeTo(2 / 3, .001));
  });
}
