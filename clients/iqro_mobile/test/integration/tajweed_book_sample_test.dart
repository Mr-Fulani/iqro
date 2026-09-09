import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/tajweed_book_preview_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['IQRO_TAJWEED_BOOK_SAMPLES'];
  for (final sample in TajweedBookSample.samples) {
    test(
      'original Tajweed page ${sample.page}: exact bytes and native decode',
      () async {
        final bytes = await File('$root/${sample.page}.jpg').readAsBytes();
        expect(sample.verifies(bytes), isTrue);
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, TajweedBookSample.width);
            expect(frame.image.height, TajweedBookSample.height);
            final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
            // All four edges contain printed content. Arbitrary margin trimming
            // or text-bounds cropping would remove the frame / colour legend.
            for (final side in ['left', 'right', 'top', 'bottom']) {
              var ink = 0;
              final count = side == 'left' || side == 'right' ? 1000 : 645;
              for (var i = 0; i < count; i++) {
                final x = side == 'left'
                    ? 0
                    : side == 'right'
                    ? 644
                    : i;
                final y = side == 'top'
                    ? 0
                    : side == 'bottom'
                    ? 999
                    : i;
                final offset = (y * 645 + x) * 4;
                if (rgba[offset] < 230 ||
                    rgba[offset + 1] < 230 ||
                    rgba[offset + 2] < 230) {
                  ink++;
                }
              }
              expect(
                ink,
                greaterThan(0),
                reason: 'Printed $side edge must remain',
              );
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      },
      skip: root == null
          ? 'Set IQRO_TAJWEED_BOOK_SAMPLES to the three original JPEGs'
          : false,
    );
  }
}
