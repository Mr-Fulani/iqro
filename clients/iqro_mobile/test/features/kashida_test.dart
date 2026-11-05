import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/kashida.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('assets/fonts/AmiriQuran-Regular.ttf').readAsBytesSync();
    await (FontLoader(
      IqroTheme.arabicFontFamily,
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
  });

  test('a kashida goes between joined letters, after their marks', () {
    // نَادَىٰ: nun joins alef; alef joins nothing after it.
    expect(kashidaSpots('نَادَىٰ'), <int>[2]);
    // رَبِّكَ: ra joins nothing; ba joins kaf after its shadda and kasra.
    expect(kashidaSpots('رَبِّكَ'), <int>[5]);
  });

  test('never inside lam-alef nor in the name of Allah', () {
    expect(kashidaSpots('لَا'), isEmpty);
    expect(kashidaSpots('ٱللَّهِ'), isEmpty);
    expect(kashidaSpots('وَٱللَّهُ'), isEmpty);
    expect(kashidaSpots('بِٱللَّهِ'), isEmpty);
  });

  test('a pause mark or an ayah number has no join to draw out', () {
    expect(kashidaSpots('ۚ'), isEmpty);
    expect(kashidaSpots('﴿٥﴾'), isEmpty);
  });

  test('every line but the last reaches the edge, and none goes past it', () {
    const style = TextStyle(
      fontFamily: IqroTheme.arabicFontFamily,
      fontSize: 40,
    );
    final words = quranWords(
      'وَإِنِّى خِفْتُ ٱلْمَوَٰلِىَ مِن وَرَآءِى وَكَانَتِ ٱمْرَأَتِى عَاقِرًا '
      'فَهَبْ لِى مِن لَّدُنكَ وَلِيًّا',
    );
    for (final width in <double>[320, 520, 760]) {
      final layout = kashidaLayout(
        words: words,
        style: style,
        width: width,
        marker: ' ﴿٥﴾',
      );
      expect(layout.words.length, words.length);
      // The words are the same, only drawn out.
      for (final (index, word) in layout.words.indexed) {
        expect(word.replaceAll(tatweel, ''), words[index]);
      }
      var start = 0;
      final lines = <List<String>>[];
      for (var i = 0; i < words.length; i++) {
        if (layout.breaks.contains(i) || i == words.length - 1) {
          lines.add(layout.words.sublist(start, i + 1));
          start = i + 1;
        }
      }
      for (final (index, line) in lines.indexed) {
        final last = index == lines.length - 1;
        final painter = TextPainter(
          text: TextSpan(
            text: line.join(' ') + (last ? ' ﴿٥﴾' : ''),
            style: style,
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        expect(painter.width, lessThanOrEqualTo(width), reason: '$width');
        if (!last && line.length > 1) {
          // Short of the edge by less than one more stroke of a join.
          expect(painter.width, greaterThan(width - 24), reason: '$width');
        }
        painter.dispose();
      }
    }
  });
}
