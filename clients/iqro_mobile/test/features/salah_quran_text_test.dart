import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';
import 'package:iqro_mobile/features/quran/mushaf_script.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';
import 'package:iqro_mobile/features/salah/salah_quran_text.dart';

// The formulas as the published course sends them.
const _ikhlas =
    'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿١﴾ '
    'ٱللَّهُ ٱلصَّمَدُ ﴿٢﴾ لَمْ يَلِدْ وَلَمْ يُولَدْ ﴿٣﴾ '
    'وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ ﴿٤﴾';
const _fatiha =
    'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ ﴿٢﴾ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ ﴿٣﴾';
const _basmala = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ ﴿١﴾';

SalahFormula _formula(
  String arabic, {
  required int surah,
  required int from,
  required int to,
  String kind = 'quran',
}) => SalahFormula(
  id: 'formula',
  arabic: arabic,
  translation: '',
  source: SalahFormulaSource(
    kind: kind,
    surah: surah,
    ayahFrom: from,
    ayahTo: to,
  ),
);

final _ikhlasAyahs = salahQuranAyahs(
  _formula(_ikhlas, surah: 112, from: 1, to: 4),
)!;

/// Al-Ikhlas on page 604 of a Mushaf with a font of its own.
Map<String, MushafScriptWords> _page({bool colored = false}) =>
    <String, MushafScriptWords>{
      for (final (index, words) in <int>[4, 2, 4, 5].indexed)
        '112:${index + 1}': (
          fontFamily: 'qf-page-604',
          colored: colored,
          words: <Map<String, Object?>>[
            for (var word = 1; word <= words; word++)
              <String, Object?>{
                'text': 'ﱁ',
                'char_type_name': 'word',
                'position_in_verse': word,
              },
            <String, Object?>{'text': 'ﱂ', 'char_type_name': 'end'},
          ],
        ),
    };

final _versePages = mushafVersePagesProvider.overrideWith(
  (ref) async => <String, List<int>>{
    for (var ayah = 1; ayah <= 4; ayah++) '112:$ayah': <int>[604],
  },
);

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides, {
  Brightness brightness = Brightness.light,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SalahQuranText(
          surah: 112,
          ayahs: _ikhlasAyahs,
          style: const TextStyle(
            fontFamily: IqroTheme.arabicFontFamily,
            fontSize: 30,
          ),
        ),
      ),
    ),
  ),
);

Text _ayah(WidgetTester tester, int number) =>
    tester.widget(find.byKey(ValueKey('salah-ayah-112-$number')));

Set<String?> _fonts(Text text) {
  final families = <String?>{};
  text.textSpan!.visitChildren((span) {
    families.add(span.style?.fontFamily);
    return true;
  });
  return families;
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byType(SalahQuranText),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  test('a formula of the Quran is split into its ayahs', () {
    expect(_ikhlasAyahs.map((ayah) => ayah.number), <int>[1, 2, 3, 4]);
    // The basmala is not a word of the first ayah.
    expect(
      _ikhlasAyahs.first.opening,
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    );
    expect(_ikhlasAyahs.first.text, 'قُلْ هُوَ ٱللَّهُ أَحَدٌ');
    expect(_ikhlasAyahs.last.text, 'وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ');
    expect(_ikhlasAyahs.skip(1).every((ayah) => ayah.opening == null), isTrue);

    final fatiha = salahQuranAyahs(
      _formula(_fatiha, surah: 1, from: 2, to: 3),
    )!;
    expect(fatiha.map((ayah) => ayah.number), <int>[2, 3]);
    expect(fatiha.last.text, 'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ');
    // In al-Fatiha the basmala is the first ayah itself.
    final basmala = salahQuranAyahs(
      _formula(_basmala, surah: 1, from: 1, to: 1),
    )!;
    expect(basmala.single.opening, isNull);
    expect(basmala.single.text, 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ');
  });

  test('other formulas and unexpected texts keep their one line', () {
    expect(
      salahQuranAyahs(
        _formula(_ikhlas, surah: 112, from: 1, to: 4, kind: 'dua'),
      ),
      isNull,
    );
    // Not the four ayahs the source names.
    expect(
      salahQuranAyahs(_formula(_ikhlas, surah: 112, from: 1, to: 3)),
      isNull,
    );
    expect(
      salahQuranAyahs(
        _formula('قُلْ هُوَ ٱللَّهُ أَحَدٌ', surah: 112, from: 1, to: 1),
      ),
      isNull,
    );
  });

  testWidgets('each ayah stands on its own lines in the script of the '
      'selected Mushaf, with its end sign', (tester) async {
    final page = Completer<Map<String, MushafScriptWords>?>();
    await _pump(tester, <Override>[
      _versePages,
      mushafPageScriptProvider.overrideWith((ref, number) => page.future),
    ]);
    await tester.pump();
    // Nothing is shown in the plain font first, to be redrawn a moment later.
    expect(_opacity(tester), 0);

    page.complete(_page());
    await tester.pump();
    await tester.pump();
    expect(_opacity(tester), 1);
    for (var number = 1; number <= 4; number++) {
      final ayah = _ayah(tester, number);
      expect(_fonts(ayah), contains('qf-page-604'));
      expect(ayah.textSpan!.toPlainText(), endsWith(' ﱂ'));
      expect(ayah.textAlign, TextAlign.center);
      expect(ayah.textDirection, TextDirection.rtl);
    }
    expect(_ayah(tester, 2).textSpan!.toPlainText(), 'ﱁ ﱁ ﱂ');
    // The basmala above the surah, on a line of its own.
    expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
    expect(
      tester
          .getBottomLeft(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'))
          .dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('salah-ayah-112-1'))).dy,
      ),
    );
    expect(find.byType(DecoratedBox), findsNothing);
  });

  testWidgets('a Mushaf of pictures leaves the plain Quran font, an ayah to a '
      'line', (tester) async {
    await _pump(tester, <Override>[
      mushafVersePagesProvider.overrideWith((ref) async => null),
    ]);
    await tester.pump();
    expect(_opacity(tester), 1);
    expect(_ayah(tester, 2).textSpan!.toPlainText(), 'ٱللَّهُ ٱلصَّمَدُ ﴿٢﴾');
    expect(_fonts(_ayah(tester, 2)), <String?>{null});
  });

  testWidgets('a page that does not come in a second leaves the plain font', (
    tester,
  ) async {
    await _pump(tester, <Override>[
      _versePages,
      mushafPageScriptProvider.overrideWith(
        (ref, number) => Completer<Map<String, MushafScriptWords>?>().future,
      ),
    ]);
    await tester.pump();
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(seconds: 1));
    expect(_opacity(tester), 1);
    expect(
      _ayah(tester, 1).textSpan!.toPlainText(),
      'قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿١﴾',
    );
  });

  testWidgets('a Mushaf with tajweed gets its paper in the dark theme', (
    tester,
  ) async {
    final overrides = <Override>[
      _versePages,
      mushafPageScriptProvider.overrideWith(
        (ref, number) async => _page(colored: true),
      ),
    ];
    await _pump(tester, overrides, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    final paper = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    expect((paper.decoration as BoxDecoration).color, mushafPaperColor);
    expect(_ayah(tester, 1).style?.color, mushafInkColor);

    await _pump(tester, overrides);
    await tester.pumpAndSettle();
    expect(find.byType(DecoratedBox), findsNothing);
  });
}
