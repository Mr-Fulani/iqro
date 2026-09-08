import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';

void main() {
  const source = Size(1200, 1800);

  test('viewport orientation resets only after a real rotation', () {
    final orientation = MushafViewportOrientation();

    expect(orientation.update(const Size(400, 800)), isFalse);
    expect(orientation.update(const Size(360, 780)), isFalse);
    expect(orientation.update(const Size(800, 400)), isTrue);
    expect(orientation.update(const Size(900, 420)), isFalse);
    expect(orientation.update(const Size(400, 800)), isTrue);
  });

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

  test('landscape preserves both book edges without changing aspect ratio', () {
    final layout = calculateMushafPageLayout(
      viewport: const Size(800, 400),
      source: source,
    );

    expect(layout.fillsLandscapeWidth, isTrue);
    expect(layout.width, closeTo(800, .001));
    expect(layout.height, closeTo(1200, .001));
    expect(layout.horizontalOffset, closeTo(0, .001));
    expect(layout.width / layout.height, closeTo(2 / 3, .001));
  });

  test(
    'short portrait viewport keeps equal side margins and the full page',
    () {
      final layout = calculateMushafPageLayout(
        viewport: const Size(500, 600),
        source: source,
      );
      expect(layout.width, 400);
      expect(layout.height, 600);
      expect(layout.horizontalOffset, 50);
      expect(500 - layout.width - layout.horizontalOffset, 50);
    },
  );
}
