import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster_layout.dart';

void main() {
  testWidgets('book paper, Tajweed colours and all four edges stay unchanged', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final sourceRecorder = ui.PictureRecorder();
      final sourceCanvas = Canvas(sourceRecorder);
      const colours = [Colors.white, Colors.red, Colors.green, Colors.blue];
      for (var i = 0; i < colours.length; i++) {
        sourceCanvas.drawRect(
          Rect.fromLTWH((i % 2) * 8, (i ~/ 2) * 8, 8, 8),
          Paint()..color = colours[i],
        );
      }
      final sourcePicture = sourceRecorder.endRecording();
      final source = await sourcePicture.toImage(16, 16);
      final targetRecorder = ui.PictureRecorder();
      MushafRasterPainter(
        image: source,
        layout: const MushafRasterLayout(
          size: Size(16, 16),
          bands: [
            (
              source: Rect.fromLTWH(0, 0, 1, 1),
              destination: Rect.fromLTWH(0, 0, 16, 16),
            ),
          ],
        ),
      ).paint(Canvas(targetRecorder), const Size(16, 16));
      final targetPicture = targetRecorder.endRecording();
      final target = await targetPicture.toImage(16, 16);
      try {
        final original = (await source.toByteData())!.buffer.asUint8List();
        final painted = (await target.toByteData())!.buffer.asUint8List();
        // Cubic filtering can mix adjacent colours at a boundary, even at
        // unit scale. Flat interiors and all four outer edges must retain
        // their original channels: a sepia tint fails this check.
        for (final y in [0, 2, 12, 15]) {
          for (final x in [0, 2, 12, 15]) {
            final offset = (y * 16 + x) * 4;
            expect(
              painted.sublist(offset, offset + 4),
              orderedEquals(original.sublist(offset, offset + 4)),
              reason: 'source pixel ($x, $y)',
            );
          }
        }
      } finally {
        target.dispose();
        source.dispose();
        targetPicture.dispose();
        sourcePicture.dispose();
      }
    });
  });
}
