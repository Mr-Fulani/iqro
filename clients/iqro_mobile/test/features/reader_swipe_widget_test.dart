import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/quran/reader_page_turn.dart';
import 'package:iqro_mobile/features/quran/mushaf_script.dart';
import 'package:iqro_mobile/features/quran/reader_screen.dart';
import 'package:iqro_mobile/features/quran/reader_words.dart';
import 'package:iqro_mobile/features/quran/rub_mark.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The real Arabic face: the test font's square glyphs would put each
  // word on a line of its own.
  setUpAll(() async {
    final font = File('assets/fonts/AmiriQuran-Regular.ttf').readAsBytesSync();
    await (FontLoader(
      IqroTheme.arabicFontFamily,
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
  });

  testWidgets('a swipe right opens the plain Arabic text at the ayah under '
      'the finger; a swipe back left returns the ayah reached', (tester) async {
    final app = await _pump(tester);
    await _swipe(tester, await _card(tester, 3), 220);

    expect(find.byKey(const ValueKey('reader-flow')), findsOneWidget);
    expect(_place(tester), 'Аят 3 · стр. 1');
    // Only the Arabic: no translation, no buttons of the cards.
    expect(find.text('Перевод аята 3'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byKey(const ValueKey('reader-flow-text-size')), findsOneWidget);

    await tester.dragFrom(const Offset(180, 600), const Offset(0, -900));
    await tester.pumpAndSettle();
    final reached = _placeAyah(tester);
    expect(reached, greaterThan(3));

    await _swipe(tester, const Offset(300, 400), -220);
    expect(find.byKey(const ValueKey('reader-flow')), findsNothing);
    expect(find.byKey(const ValueKey('reader-open-mushaf')), findsOneWidget);
    expect(app.quran.saved.last, reached);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the plain Arabic text announces a quarter of a hizb each time '
      'the reader scrolls to its first ayah', (tester) async {
    await _pump(tester, rubs: const <QuranDivision>[_rub2]);
    await _swipe(tester, await _card(tester, 3), 220);
    expect(find.byKey(const ValueKey('reader-flow')), findsOneWidget);
    // Opening the text announces nothing.
    expect(find.byKey(const ValueKey('rub-mark-toast')), findsNothing);

    Future<void> scrollTo(bool Function() done, double dy) async {
      for (var step = 0; step < 30 && !done(); step++) {
        await tester.dragFrom(const Offset(180, 500), Offset(0, dy));
        await tester.pumpAndSettle();
      }
      expect(done(), isTrue);
    }

    bool announced() => tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text('¼ Хизб 1'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .any((toast) => toast.opacity == 1);

    await scrollTo(announced, -200);
    await tester.pump(rubMarkDuration);
    await tester.pumpAndSettle();
    expect(announced(), isFalse);

    // Away from the ayah and back to it: announced again.
    await scrollTo(() => _placeAyah(tester) > 24, -400);
    await tester.pump(rubMarkDuration);
    expect(announced(), isFalse);
    await scrollTo(announced, 200);
    await tester.pump(rubMarkDuration);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a moment after the text first opens a hand pulls it right, '
      'then left, naming what lies each way, and goes', (tester) async {
    final app = await _pump(tester);
    expect(_hint, findsNothing);

    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(tester.widget<Text>(_hint).data, _hintText);
    expect(app.preferences.readerSwipeHintsShown, 1);

    // A third of the way through the page stands pulled to the right.
    await tester.pump(readerSwipeHintDuration * .3);
    expect(_shift(tester), greaterThan(104));
    expect(find.text('Арабский текст'), findsOneWidget);
    expect(tester.getCenter(_hand).dx, greaterThan(180));

    await tester.pump(readerSwipeHintDuration * .45);
    expect(_shift(tester), lessThan(-104));
    expect(find.text('Мусхаф'), findsOneWidget);
    expect(tester.getCenter(_hand).dx, lessThan(180));

    await tester.pumpAndSettle();
    expect(_hint, findsNothing);
    expect(_shift(tester), 0);
    // It opened nothing.
    expect(find.byKey(const ValueKey('reader-flow')), findsNothing);
    expect(app.mushaf, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the swipe hint reads the same way in Arabic: a swipe is not '
      'mirrored', (tester) async {
    await _pump(tester, locale: const Locale('ar'), theme: IqroTheme.dark());
    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(
      tester.widget<Text>(_hint).data,
      'اسحب يمينًا للنص العربي ويسارًا للمصحف',
    );
    await tester.pump(readerSwipeHintDuration * .3);
    expect(_shift(tester), greaterThan(104));
    expect(find.text('النص العربي'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a touch ends the swipe hint at once', (tester) async {
    await _pump(tester);
    await tester.pump(readerSwipeHintDelay);
    await tester.pump(readerSwipeHintDuration * .3);
    expect(_hint, findsOneWidget);

    final finger = await tester.startGesture(const Offset(180, 300));
    await tester.pump();
    expect(_hint, findsNothing);
    // The page slides back; the finger opens nothing.
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(_shift(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the swipe hint comes three times at most, and never after a '
      'swipe', (tester) async {
    var app = await _pump(
      tester,
      stored: const <String, Object>{'reader_swipe_hint_count': 2},
    );
    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(_hint, findsOneWidget);
    await tester.pumpAndSettle();
    expect(app.preferences.readerSwipeHintsShown, readerSwipeHintLimit);

    await tester.pumpWidget(const SizedBox());
    app = await _pump(
      tester,
      stored: const <String, Object>{'reader_swipe_hint_count': 3},
    );
    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(_hint, findsNothing);

    // The reader swipes before the hint: it has nothing to teach.
    await tester.pumpWidget(const SizedBox());
    app = await _pump(tester);
    await _swipe(tester, await _card(tester, 3), -220);
    expect(app.mushaf, isNotNull);
    expect(app.preferences.readerSwipeHintsShown, readerSwipeHintLimit);
    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(_hint, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations off the swipe hint stands still and the text '
      'does not move', (tester) async {
    await _pump(tester, reducedMotion: true);
    await tester.pump(readerSwipeHintDelay);
    await tester.pump();
    expect(_hint, findsOneWidget);
    expect(_hand, findsOneWidget);
    final hand = tester.getCenter(_hand);

    await tester.pump(readerSwipeHintStill ~/ 2);
    expect(_hint, findsOneWidget);
    expect(_shift(tester), 0);
    expect(tester.getCenter(_hand), hand);

    await tester.pump(readerSwipeHintStill ~/ 2);
    await tester.pump();
    expect(_hint, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a swipe left turns to the Mushaf page of the ayah under the '
      'finger', (tester) async {
    final app = await _pump(tester);
    await _swipe(tester, await _card(tester, 2), -220);

    expect(app.mushaf, isNotNull);
    expect(app.mushaf!.uri.queryParameters['ayah'], '2');
    expect(app.mushaf!.uri.queryParameters['page'], '1');
    expect(app.mushaf!.extra, ReaderPageTurn.routeExtra);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling, a swipe from the screen edge and a swipe across '
      'selected words turn no page', (tester) async {
    final app = await _pump(tester);
    await tester.drag(
      find.byKey(const ValueKey('reader-ayah-2')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    // From the very edge: the system's back gesture.
    await _swipe(tester, Offset(8, (await _card(tester, 3)).dy), 220);
    expect(find.byKey(const ValueKey('reader-flow')), findsNothing);
    expect(app.mushaf, isNull);

    // Hold a word: the words are selected, and a swipe pulls nothing.
    final word = await _card(tester, 4);
    await tester.longPressAt(word);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('word-range-panel')), findsOneWidget);
    await _swipe(tester, word + const Offset(-60, 0), 220);
    expect(find.byKey(const ValueKey('reader-flow')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reader of Arabic keeps Arabic-Indic digits in the place '
      'line', (tester) async {
    await _pump(tester, locale: const Locale('ar'));
    await _swipe(tester, await _card(tester, 3), 220);
    expect(_place(tester), contains('٣'));
    expect(_place(tester), isNot(contains('3')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a line marks the end of a Mushaf page between its ayahs, in '
      'the cards and in the plain text', (tester) async {
    await _pump(tester);
    // Six ayahs to a page here: the first page ends before the seventh.
    await _card(tester, 7);
    final end = find.byKey(const ValueKey('reader-page-end-1'));
    expect(end, findsOneWidget);
    expect(
      find.descendant(of: end, matching: find.text('Страница 1')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(end).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('reader-ayah-7'))).dy,
      ),
    );
    expect(find.byKey(const ValueKey('reader-page-end-0')), findsNothing);

    await _swipe(tester, await _card(tester, 7), 220);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reader-flow-page-end-1')),
      -60,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Страница 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cards and the plain text are written as the selected '
      'Mushaf writes them, at its own page ends', (tester) async {
    await _pump(tester, overrides: _mushafScript);
    // Ayah 2 is on a page of the Mushaf font, word for word.
    expect(_fonts(tester, 'reader-ayah-2'), contains('qf-page-1'));
    // The first ayah has a word less in this Mushaf: the plain text stays.
    expect(_fonts(tester, 'reader-ayah-1'), isNot(contains('qf-page-1')));
    // This Mushaf ends its first page after the third ayah.
    await _card(tester, 4);
    expect(find.byKey(const ValueKey('reader-page-end-1')), findsOneWidget);
    // A page that has not loaded leaves the plain text.
    expect(_fonts(tester, 'reader-ayah-4'), isNot(contains('qf-page-2')));

    await _swipe(tester, await _card(tester, 2, delta: -120), 220);
    expect(_place(tester), 'Аят 2 · стр. 1');
    expect(_fonts(tester, 'reader-flow-ayah-2'), contains('qf-page-1'));
    expect(tester.takeException(), isNull);
  });

  for (final dark in <bool>[false, true]) {
    testWidgets('pictures of the readers in the Mushaf script'
        '${dark ? ', dark' : ''}', (tester) async {
      await _pump(
        tester,
        size: const Size(1080, 2340),
        pixelRatio: 2.75,
        theme: dark ? IqroTheme.dark() : null,
        overrides: await tester.runAsync(_realMushaf) ?? const [],
        repository: _TranslatedQuran(),
      );
      final suffix = dark ? '-dark' : '';
      await _capture(tester, 'app-cards-top$suffix');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reader-page-end-2')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('reader-page-end-2'))),
        alignment: .35,
      );
      await _capture(tester, 'app-cards-page-end$suffix');
      await _swipe(tester, await _card(tester, 4, delta: -120), 220, x: 80);
      // The tint of the ayah the reader came to has gone.
      await tester.pump(const Duration(seconds: 2));
      await _capture(tester, 'app-plain$suffix');
      expect(tester.takeException(), isNull);
    }, skip: _directory.isEmpty);
  }

  for (final (name, size) in <(String, Size)>[
    ('a phone in portrait', Size(360, 800)),
    ('a phone in landscape', Size(800, 360)),
    ('a tablet in landscape', Size(1280, 800)),
  ]) {
    testWidgets('on $name the size reflows the text and keeps its ayah', (
      tester,
    ) async {
      final app = await _pump(tester, size: size);
      await _swipe(
        tester,
        await _card(tester, 2),
        size.width * .5,
        x: size.width * .2,
      );
      expect(_place(tester), 'Аят 2 · стр. 1');
      final before = tester
          .getSize(find.byKey(const ValueKey('reader-flow-ayah-2')))
          .height;

      await tester.tap(find.byKey(const ValueKey('reader-flow-text-size')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('reader-flow-text-size-slider'));
      await tester.drag(slider, const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(app.preferences.readerFlowFontSize, maxReaderFlowFontSize);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-flow-ayah-2'))).height,
        greaterThan(before),
      );
      expect(_place(tester), 'Аят 2 · стр. 1');
      expect(tester.takeException(), isNull);
    });
  }
}

// Pictures of the readers in the script of QCF V4 Tajweed, for the pull
// request and docs/guides/mushaf-script-in-text:
//
//   flutter test test/features/reader_swipe_widget_test.dart \
//     --name "pictures" --dart-define=SCREENSHOT_DIR=/tmp/shots \
//     --dart-define=SCREENSHOT_DATA=/tmp/data
//
// SCREENSHOT_DATA holds page2.json, page3.json (the API's pages of Mushaf
// 19), their fonts p2.ttf, p3.ttf and ayahs2.json (the surah's ayahs).
const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _data = String.fromEnvironment('SCREENSHOT_DATA');
final _scope = GlobalKey();

Future<void> _family(String name, List<String> files) async {
  final loader = FontLoader(name);
  for (final file in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<List<Override>> _realMushaf() async {
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  await _family('Roboto', <String>[
    for (final weight in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$weight.ttf',
  ]);
  await _family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await _family('serif', ['/System/Library/Fonts/Supplemental/Georgia.ttf']);
  final pages = <int, Map<String, MushafScriptWords>>{};
  for (final number in <int>[2, 3]) {
    await _family('qf-page-$number', ['$_data/p$number.ttf']);
    final page =
        jsonDecode(File('$_data/page$number.json').readAsStringSync())
            as Map<String, Object?>;
    final ayahs = pages[number] = <String, MushafScriptWords>{};
    for (final word in (page['words']! as List).cast<Map<String, Object?>>()) {
      ayahs
          .putIfAbsent(
            word['verse_key']! as String,
            () => (
              words: <Map<String, Object?>>[],
              fontFamily: 'qf-page-$number',
              colored: true,
            ),
          )
          .words
          .add(word);
    }
  }
  final ayahs = <QuranAyah>[
    for (final json
        in (jsonDecode(File('$_data/ayahs2.json').readAsStringSync()) as List)
            .cast<Map<String, Object?>>()
            .take(16))
      QuranAyah(
        id: json['id']! as String,
        surahNumber: 2,
        number: json['number']! as int,
        textUthmani: json['text_uthmani']! as String,
        pages: (json['pages']! as List).cast<int>(),
      ),
  ];
  return <Override>[
    ayahsProvider.overrideWith((ref, surah) async => ayahs),
    mushafVersePagesProvider.overrideWith(
      (ref) async => <String, List<int>>{
        for (final MapEntry(:key, :value) in pages.entries)
          for (final ayah in value.keys) ayah: <int>[key],
      },
    ),
    mushafPageScriptProvider.overrideWith((ref, page) async => pages[page]),
  ];
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = _scope.currentContext!.findRenderObject()!;
  final bytes = await tester.runAsync(() async {
    final image = await (boundary as RenderRepaintBoundary).toImage(
      pixelRatio: 2.75,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_directory/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// The middle of [ayah]'s Arabic text, scrolled onto the screen.
Future<Offset> _card(
  WidgetTester tester,
  int ayah, {
  double delta = 120,
}) async {
  final finder = find.byKey(ValueKey('reader-ayah-$ayah'));
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return tester.getCenter(finder);
}

/// The font families of the text drawn for the widget at [key].
Set<String?> _fonts(WidgetTester tester, String key) {
  final families = <String?>{};
  void visit(InlineSpan span) {
    families.add(span.style?.fontFamily);
    span.visitDirectChildren((child) {
      visit(child);
      return true;
    });
  }

  final words = tester.widget(find.byKey(ValueKey(key)));
  if (words is Text) {
    visit(words.textSpan ?? TextSpan(style: words.style));
  } else if (words is ReaderAyahWords) {
    (words.spans ?? words.flowAyahs?.single.spans)?.forEach(visit);
  }
  return families;
}

/// A Mushaf of three ayahs to a page, drawn with a font of each page; its
/// second page never loads.
final _mushafScript = <Override>[
  mushafVersePagesProvider.overrideWith(
    (ref) async => <String, List<int>>{
      for (var ayah = 1; ayah <= 30; ayah++)
        '2:$ayah': <int>[1 + (ayah - 1) ~/ 3],
    },
  ),
  mushafPageScriptProvider.overrideWith(
    (ref, page) async => page != 1
        ? Completer<Map<String, MushafScriptWords>?>().future
        : <String, MushafScriptWords>{
            for (var ayah = 1; ayah <= 3; ayah++)
              '2:$ayah': (
                fontFamily: 'qf-page-1',
                colored: false,
                words: <Map<String, Object?>>[
                  // «الٓمٓ» is one word; the ayah has two here.
                  for (var word = 1; word <= (ayah == 1 ? 2 : 8); word++)
                    <String, Object?>{
                      'text': 'ﱁ',
                      'char_type_name': 'word',
                      'position_in_verse': word,
                    },
                  <String, Object?>{'text': 'ﱂ', 'char_type_name': 'end'},
                ],
              ),
          },
  ),
];

String _place(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('reader-flow-place'))).data!;

int _placeAyah(WidgetTester tester) {
  return int.parse(_place(tester).split(' ')[1]);
}

const _hintText = 'Свайп вправо — арабский текст, влево — Мусхаф';
final _hint = find.byKey(const ValueKey('reader-swipe-hint'));
final _hand = find.byKey(const ValueKey('reader-swipe-hint-hand'));

/// How far the text stands pulled aside.
double _shift(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(ReaderSwipeArea),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .getTranslation()
    .x;

Future<void> _swipe(
  WidgetTester tester,
  Offset start,
  double dx, {
  double? x,
}) async {
  await tester.timedDragFrom(
    Offset(x ?? start.dx, start.dy),
    Offset(dx, 0),
    const Duration(milliseconds: 300),
  );
  await tester.pumpAndSettle();
}

class _App {
  _App(this.quran, this.store);

  final _Quran quran;
  final PreferencesStore store;
  GoRouterState? mushaf;

  AppPreferences get preferences => store.read();
}

Future<_App> _pump(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double pixelRatio = 1,
  Locale locale = const Locale('ru'),
  ThemeData? theme,
  List<Override> overrides = const <Override>[],
  _Quran? repository,
  List<QuranDivision> rubs = const <QuranDivision>[],
  Map<String, Object> stored = const <String, Object>{},
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(stored);
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final database = _Database();
  final quran = repository ?? _Quran();
  final app = _App(quran, store);
  final plan = _Plan();
  final router = GoRouter(
    initialLocation: '/reader/2',
    routes: <RouteBase>[
      GoRoute(
        path: '/reader/:surah',
        builder: (context, state) => const ReaderScreen(surah: 2),
      ),
      GoRoute(
        path: '/mushaf',
        builder: (context, state) {
          app.mushaf = state;
          return const Scaffold(body: Text('Мусхаф'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _scope,
      child: ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => _SignedOut()),
          analyticsBackendProvider.overrideWithValue(null),
          localDatabaseProvider.overrideWithValue(database),
          activeAccountScopeKeyProvider.overrideWith(
            (ref) => accountScopeKey(database.accountScope.current!),
          ),
          appPreferencesProvider.overrideWith(
            (ref) => AppPreferencesController(store, plan),
          ),
          planRepositoryProvider.overrideWithValue(plan),
          quranRepositoryProvider.overrideWithValue(quran),
          audioRepositoryProvider.overrideWithValue(_AudioRepository()),
          audioControllerProvider.overrideWith(
            (ref) => AudioController(engine: _Engine()),
          ),
          ayahsProvider.overrideWith((ref, surah) async => _ayahs),
          quranRubElHizbProvider.overrideWith((ref) async => rubs),
          quranCatalogProvider.overrideWith(
            (ref) async =>
                const QuranCatalog(surahs: <Surah>[_baqara], fromCache: true),
          ),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: theme ?? IqroTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

// The second quarter of the first hizb, at 2:14 for the test.
const _rub2 = QuranDivision(
  number: 2,
  startAyah: QuranAyahReference(id: '', surah: 2, ayah: 14),
  endAyah: QuranAyahReference(id: '', surah: 2, ayah: 20),
  startPage: 1,
  endPage: 1,
  hizbNumber: 1,
  quarterNumber: 2,
);

const _baqara = Surah(
  id: '2',
  number: 2,
  nameAr: 'البقرة',
  nameEn: 'Al-Baqarah',
  nameRu: 'Аль-Бакара',
  ayahCount: 30,
  revelationType: 'medinan',
);

const _verse =
    'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُقِيمُونَ ٱلصَّلَوٰةَ '
    'وَمِمَّا رَزَقْنَٰهُمْ يُنفِقُونَ';

final _ayahs = <QuranAyah>[
  for (var number = 1; number <= 30; number++)
    QuranAyah(
      id: '2:$number',
      surahNumber: 2,
      number: number,
      textUthmani: number == 1
          ? 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ'
          : _verse,
      pages: <int>[1 + (number - 1) ~/ 6],
    ),
];

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('reader');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quran implements QuranRepository {
  final saved = <int>[];

  @override
  Future<List<Map<String, Object?>>> bookmarks({
    AccountScopeSnapshot? accountScope,
  }) async => const <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> ayahAnnotations({
    AccountScopeSnapshot? accountScope,
  }) async => const <Map<String, Object?>>[];

  @override
  Future<void> savePosition({
    required int surah,
    required int ayah,
    required int page,
    AccountScopeSnapshot? accountScope,
  }) async {
    saved.add(ayah);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// For the pictures: the API's own translation of the surah.
class _TranslatedQuran extends _Quran {
  @override
  Future<List<QuranTranslationEdition>> translationEditions(
    String locale, {
    bool forceRefresh = false,
  }) async => const <QuranTranslationEdition>[
    QuranTranslationEdition(
      sourceId: 79,
      languageCode: 'ru',
      name: 'Abu Adel',
      authorName: 'Abu Adel',
    ),
  ];

  @override
  Future<List<QuranTafsirEdition>> tafsirEditions(
    String locale, {
    bool forceRefresh = false,
  }) async => const <QuranTafsirEdition>[];

  @override
  Future<List<QuranAyahTranslation>> translations({
    required int sourceId,
    required int surah,
    bool forceRefresh = false,
  }) async => <QuranAyahTranslation>[
    for (final json
        in (jsonDecode(File('$_data/translation2.json').readAsStringSync())
                as List)
            .cast<Map<String, Object?>>())
      QuranAyahTranslation.fromJson(json),
  ];
}

class _Plan implements PlanRepository {
  @override
  ReadingSessionRecorder startReadingSession({
    required AccountScopeSnapshot accountScope,
    DateTime Function()? clock,
  }) => _Recorder();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recorder implements ReadingSessionRecorder {
  @override
  void observe({required int page, required int surah, required int ayah}) {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  Future<void> finish() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOut extends StateNotifier<AsyncValue<AuthSession?>>
    implements SessionController {
  _SignedOut() : super(const AsyncData(null));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioRepository implements AudioRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements IqroAudioEngine {
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
