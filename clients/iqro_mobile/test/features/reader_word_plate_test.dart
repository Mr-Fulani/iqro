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

  testWidgets('a filled text has every line but the last from edge to edge, '
      'at any size', (tester) async {
    final registry = ReaderWordRegistry();
    Future<void> pump(double size) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SizedBox(
            width: 250,
            child: ReaderAyahWords.flow(
              surah: 1,
              ayahs: const <ReaderAyahText>[
                ReaderAyahText(
                  ayah: 1,
                  words: <String>['aaa', 'bbb', 'ccc', 'ddd', 'eee'],
                ),
              ],
              style: TextStyle(fontSize: size, height: 1),
              registry: registry,
              onRange: (_) {},
              textAlign: TextAlign.center,
              fill: true,
            ),
          ),
        ),
      ),
    );
    Rect word(int index) => registry.wordRect(QuranWord(1, 1, index))!;
    final left = (800 - 250) / 2;

    // Three words of three squares and two gaps are 220 wide: the 30 left
    // over go into the gaps, and the line is as wide as the paragraph.
    // (Latin letters go from the left, whatever the paragraph.)
    await pump(20);
    expect(word(1).left, closeTo(left, 1.5));
    expect(word(3).right, closeTo(left + 250, 1.5));
    expect(word(2).top, word(1).top);
    // The last line stays in the middle, its words as near as they were.
    expect(word(4).top, greaterThan(word(1).top));
    expect(word(5).left - word(4).right, closeTo(20, .5));
    expect((word(4).left + word(5).right) / 2, closeTo(left + 125, 1));

    // Larger, the lines are broken anew and filled again: two words to a
    // line, the gap between them no wider than a letter or so.
    await pump(32);
    expect(word(2).top, word(1).top);
    expect(word(3).top, greaterThan(word(1).top));
    expect(word(1).left, closeTo(left, 1.5));
    expect(word(2).right, closeTo(left + 250, 1.5));
    expect(word(5).center.dx, closeTo(left + 125, 1));
  });
}
