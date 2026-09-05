import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in <double>[320, 780]) {
      testWidgets('ayah paper: $brightness, width $width, large text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const ayah = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';
        final text = List.filled(12, ayah).join(' ');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: MushafAyahText(text: text),
                  ),
                ),
              ),
            ),
          ),
        );
        final rendered = tester.widget<Text>(find.text(text));
        expect(rendered.textDirection, TextDirection.rtl);
        expect(rendered.style?.color, mushafInkColor);
        expect(rendered.maxLines, isNull);
        final paper = tester.widget<Container>(
          find.descendant(
            of: find.byType(MushafAyahText),
            matching: find.byType(Container),
          ),
        );
        expect((paper.decoration! as BoxDecoration).color, mushafPaperColor);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
