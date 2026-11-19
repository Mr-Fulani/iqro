import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/reader_words.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';

void main() {
  testWidgets(
    'a plate is painted under its word and leaves the text as it is',
    (tester) async {
      const fill = Color(0xFF00FF00);
      const edge = Color(0xFF00FF00);
      const text = Color(0xFF000000);
      const paper = Color(0xFFFFFFFF);
      final registry = ReaderWordRegistry();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: paper,
                child: SizedBox(
                  width: 300,
                  child: ReaderAyahWords.flow(
                    surah: 1,
                    ayahs: const <ReaderAyahText>[
                      ReaderAyahText(
                        ayah: 1,
                        words: <String>['aaa', 'bbb', 'ccc'],
                      ),
                    ],
                    // The test font draws every letter as a full square.
                    style: const TextStyle(
                      fontSize: 20,
                      color: text,
                      height: 1,
                    ),
                    registry: registry,
                    onRange: (_) {},
                    textAlign: TextAlign.start,
                    plates: const <ReaderWordPlate>[
                      (word: QuranWord(1, 1, 2), fill: fill, edge: edge),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final origin = render.localToGlobal(Offset.zero);
      late ui.Image image;
      late List<int> pixels;
      await tester.runAsync(() async {
        image = await render.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        pixels = data!.buffer.asUint8List();
      });
      Color at(Offset global) {
        final local = global - origin;
        final i = (local.dy.floor() * image.width + local.dx.floor()) * 4;
        return Color.fromARGB(
          pixels[i + 3],
          pixels[i],
          pixels[i + 1],
          pixels[i + 2],
        );
      }

      // Every letter keeps the text's colour, on the plate too; the plate
      // shows beside its word, a little wider than it, and nowhere else.
      final first = registry.wordRect(const QuranWord(1, 1, 1))!;
      final second = registry.wordRect(const QuranWord(1, 1, 2))!;
      final third = registry.wordRect(const QuranWord(1, 1, 3))!;
      expect(at(first.center), text);
      expect(at(second.center), text);
      expect(at(third.center), text);
      // (Green all but pure: the edge of a letter beside it is smoothed.)
      bool plate(Color colour) =>
          colour.g > .8 && colour.r < .1 && colour.b < .2;
      expect(plate(at(Offset(second.right + .5, second.center.dy))), isTrue);
      expect(plate(at(Offset(second.left - .5, second.center.dy))), isTrue);
      expect(at(Offset(second.right + 6, second.center.dy)), paper);
      expect(at(Offset(second.left - 6, second.center.dy)), paper);
    },
  );
}
