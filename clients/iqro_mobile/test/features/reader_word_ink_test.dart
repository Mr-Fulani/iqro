import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/reader_words.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';

void main() {
  testWidgets('inked words are the text\'s own glyphs in another colour', (
    tester,
  ) async {
    const ink = Color(0xFF8A5E10);
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
                  style: const TextStyle(fontSize: 20, color: text, height: 1),
                  registry: registry,
                  onRange: (_) {},
                  textAlign: TextAlign.start,
                  inked: <ReaderWordInk>[
                    (
                      words: QuranWordRange.between(
                        const QuranWord(1, 1, 1),
                        const QuranWord(1, 1, 2),
                      )!,
                      color: ink,
                    ),
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

    // The two words read are in the ink, the third in the text's colour,
    // and the paper between and around them is untouched.
    expect(at(registry.wordRect(const QuranWord(1, 1, 1))!.center), ink);
    expect(at(registry.wordRect(const QuranWord(1, 1, 2))!.center), ink);
    expect(at(registry.wordRect(const QuranWord(1, 1, 3))!.center), text);
    final first = registry.wordRect(const QuranWord(1, 1, 1))!;
    final second = registry.wordRect(const QuranWord(1, 1, 2))!;
    final gap = Offset((first.left + second.right) / 2, first.center.dy);
    expect(at(gap), paper);
  });
}
