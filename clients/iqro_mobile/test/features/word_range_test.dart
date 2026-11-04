import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/quran/reader_words.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'tajweed_test_data.dart';

void main() {
  group('words of an ayah', () {
    test('a pause mark written apart belongs to the word before it', () {
      final words = quranWords(
        'ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ',
      );
      expect(words, hasLength(7));
      expect(words[3], 'رَيْبَ ۛ');
      expect(words[4], 'فِيهِ ۛ');
    });

    test('the basmala before a first ayah is not one of its words', () {
      const ayah = QuranAyah(
        id: '2:1',
        surahNumber: 2,
        number: 1,
        textUthmani: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ',
        pages: <int>[2],
      );
      expect(ayahWords(ayah), ['الٓمٓ']);
    });

    test('a range is ordered, stays in one surah and spans ayah ends', () {
      const a = QuranWord(1, 6, 2);
      const b = QuranWord(1, 5, 3);
      final range = QuranWordRange.between(a, b)!;
      expect(range.start, b);
      expect(range.end, a);
      expect(range.contains(const QuranWord(1, 5, 4)), isTrue);
      expect(range.contains(const QuranWord(1, 6, 3)), isFalse);
      expect(range.spansAyahEnd(1, 5), isTrue);
      expect(range.spansAyahEnd(1, 6), isFalse);
      expect(QuranWordRange.between(a, const QuranWord(2, 1, 1)), isNull);
    });
  });

  group('QCF page', () {
    testWidgets('a long press and a drag select the words between', (
      tester,
    ) async {
      final harness = await _pumpPage(tester);
      final gesture = await tester.startGesture(_wordCenter(tester, 1));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(_wordCenter(tester, 2));
      await tester.pump();
      await gesture.moveTo(_wordCenter(tester, 3));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(harness.ranges.last.range.start, const QuranWord(112, 4, 1));
      expect(harness.ranges.last.range.end, const QuranWord(112, 4, 3));
      expect(harness.ranges.last.count, 3);
      expect(harness.opened, isEmpty);
      expect(
        find.byKey(const ValueKey('word-range-start-handle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('word-range-end-handle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long press released in place opens the word menu', (
      tester,
    ) async {
      final harness = await _pumpPage(tester);
      final gesture = await tester.startGesture(_wordCenter(tester, 2));
      await tester.pump(const Duration(milliseconds: 600));
      // The menu waits for the finger: holding still opens nothing yet.
      expect(harness.opened, isEmpty);
      await gesture.up();
      await tester.pump();

      expect(harness.opened, ['112:4:2']);
      expect(harness.ranges, isEmpty);
    });

    testWidgets('a tap beside the selected words only clears them', (
      tester,
    ) async {
      final harness = await _pumpPage(
        tester,
        initial: const QuranWordRange.single(QuranWord(112, 4, 1)),
      );
      await tester.tapAt(_wordCenter(tester, 3));
      await tester.pump(const Duration(milliseconds: 400));

      expect(harness.backgroundTaps, hasLength(1));
      expect(harness.selected, isEmpty);
    });

    testWidgets('a handle pulls the end of the selection to another word', (
      tester,
    ) async {
      final harness = await _pumpPage(
        tester,
        initial: QuranWordRange.between(
          const QuranWord(112, 4, 1),
          const QuranWord(112, 4, 2),
        ),
      );
      final handle = find.byKey(const ValueKey('word-range-end-handle'));
      final knob = _knobCenter(tester, handle);
      final gesture = await tester.startGesture(knob);
      await gesture.moveBy(const Offset(-4, 0));
      await tester.pump();
      final target = _wordCenter(tester, 4);
      await gesture.moveTo(
        target + (knob - tester.getTopLeft(handle)) - const Offset(22, 0),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(harness.ranges.last.range.start, const QuranWord(112, 4, 1));
      expect(harness.ranges.last.range.end.position, greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('QCF page among the reader pages', () {
    for (final (name, offset) in <(String, Offset)>[
      ('sideways', Offset(-90, 0)),
      ('down to the next line', Offset(20, 40)),
    ]) {
      testWidgets('a finger pulls a handle $name, the page stays', (
        tester,
      ) async {
        final harness = await _pumpPage(
          tester,
          inPageView: true,
          initial: QuranWordRange.between(
            const QuranWord(112, 4, 1),
            const QuranWord(112, 4, 2),
          ),
        );
        final handle = find.byKey(const ValueKey('word-range-end-handle'));
        final knob = _knobCenter(tester, handle);
        await _fingerDrag(tester, knob, knob + offset);

        expect(harness.ranges, isNotEmpty);
        expect(harness.ranges.last.range.start, const QuranWord(112, 4, 1));
        expect(harness.ranges.last.range.end.position, greaterThanOrEqualTo(3));
        expect(find.byType(NativeMushafPage), findsOneWidget);
        expect(wordRangePulling.value, isFalse);
      });
    }

    testWidgets('a long press and a drag still select words', (tester) async {
      final harness = await _pumpPage(tester, inPageView: true);
      final gesture = await tester.startGesture(_wordCenter(tester, 1));
      await tester.pump(const Duration(milliseconds: 600));
      final from = _wordCenter(tester, 1);
      final to = _wordCenter(tester, 3);
      for (var step = 1; step <= 10; step++) {
        await gesture.moveTo(Offset.lerp(from, to, step / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      expect(harness.ranges.last.range.end, const QuranWord(112, 4, 3));
    });
  });

  group('playback', () {
    testWidgets('plays from the first word to the end of the last', (
      tester,
    ) async {
      final harness = await _pumpPanel(tester);
      harness.controller().select(
        QuranWordRange.between(
          const QuranWord(1, 5, 3),
          const QuranWord(1, 6, 2),
        )!,
        wordCount: 4,
      );
      await _settle(tester);
      expect(find.text('1:5, слово 3 — 1:6, слово 2'), findsOneWidget);
      expect(find.text('4 слова · Husary'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('word-range-play')));
      await _settle(tester);

      final source = harness.engine.sources.single as ClippingAudioSource;
      expect(source.start, const Duration(milliseconds: 21300));
      expect(source.end, const Duration(milliseconds: 25600));
      expect(harness.repository.requested, containsAll(<String>['1:5', '1:6']));
      expect(
        harness.controller().playingWordAt(const Duration(milliseconds: 23500)),
        const QuranWord(1, 6, 1),
      );
      // Words outside the selection never light up.
      expect(
        harness.controller().playingWordAt(const Duration(milliseconds: 20000)),
        isNull,
      );
    });

    testWidgets('three repeats play the clip three times', (tester) async {
      final harness = await _pumpPanel(tester);
      harness.controller().select(
        const QuranWordRange.single(QuranWord(1, 5, 3)),
        wordCount: 1,
      );
      await _settle(tester);
      await tester.tap(find.text('3 раза'));
      await tester.tap(find.byKey(const ValueKey('word-range-play')));
      await _settle(tester);
      expect(harness.engine.plays, 1);

      for (var round = 0; round < 3; round++) {
        harness.engine.complete();
        await _settle(tester);
      }
      expect(harness.engine.plays, 3);
    });

    testWidgets('a reciter without word timings explains why', (tester) async {
      await _pumpPanel(tester, timed: false);
      final harness = _lastPanel!;
      harness.controller().select(
        const QuranWordRange.single(QuranWord(1, 5, 3)),
        wordCount: 1,
      );
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('word-range-unavailable')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('word-range-play')))
            .onPressed,
        isNull,
      );
    });
  });

  group('teaching voice', () {
    testWidgets('words the chosen reciter has no timings of play in the '
        'teaching al-Husary', (tester) async {
      final harness = await _pumpPanel(
        tester,
        timed: false,
        withTeaching: true,
      );
      harness.controller().select(
        QuranWordRange.between(
          const QuranWord(1, 5, 3),
          const QuranWord(1, 6, 2),
        )!,
        wordCount: 4,
      );
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('word-range-unavailable')),
        findsNothing,
      );
      expect(
        find.text(
          'Голос: аль-Хусари, учебное чтение. '
          'У выбранного чтеца нет разметки по словам.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('word-range-play')));
      await _settle(tester);

      final source = harness.engine.sources.single as ClippingAudioSource;
      expect(source.start, const Duration(milliseconds: 21300));
      expect(source.end, const Duration(milliseconds: 25600));
      expect(harness.repository.requestedBy, contains('rec-12:1:5'));
      expect(harness.controller().recitation?.id, 'rec-12');
      expect(harness.controller().teachingVoice, isTrue);
      // The words light up by the teaching voice's timings.
      expect(
        harness.controller().playingWordAt(const Duration(milliseconds: 23500)),
        const QuranWord(1, 6, 1),
      );
    });

    testWidgets('the chosen reciter plays when it has the timings', (
      tester,
    ) async {
      final harness = await _pumpPanel(tester, withTeaching: true);
      harness.controller().select(
        const QuranWordRange.single(QuranWord(1, 5, 3)),
        wordCount: 1,
      );
      await _settle(tester);

      expect(harness.controller().recitation?.id, 'rec-1');
      expect(
        find.byKey(const ValueKey('word-range-teaching-voice')),
        findsNothing,
      );
      expect(harness.repository.requestedBy, isNot(contains('rec-12:1:5')));
    });

    testWidgets('where the Muallim has no timings his Murattal plays', (
      tester,
    ) async {
      final harness = await _pumpPanel(
        tester,
        withTeaching: true,
        teachingTimed: false,
        teachingChosen: true,
        withMurattal: true,
      );
      harness.controller().select(
        const QuranWordRange.single(QuranWord(1, 5, 3)),
        wordCount: 1,
      );
      await _settle(tester);

      expect(harness.controller().recitation?.id, 'rec-6');
      expect(
        find.text(
          'Голос: аль-Хусари · Мурратталь. '
          'У выбранного чтеца здесь нет разметки по словам.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('word-range-unavailable')),
        findsNothing,
      );
    });

    testWidgets('without the teaching voice either the note stays', (
      tester,
    ) async {
      final harness = await _pumpPanel(
        tester,
        timed: false,
        withTeaching: true,
        teachingTimed: false,
      );
      harness.controller().select(
        const QuranWordRange.single(QuranWord(1, 5, 3)),
        wordCount: 1,
      );
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('word-range-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('word-range-teaching-voice')),
        findsNothing,
      );
    });
  });

  group('text reader', () {
    testWidgets('a long press selects a word and a drag the next ayah', (
      tester,
    ) async {
      final ranges = <QuranWordRange>[];
      final registry = ReaderWordRegistry();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(
                children: <Widget>[
                  for (final (ayah, text) in <(int, String)>[
                    (5, 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ'),
                    (6, 'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ'),
                  ])
                    ReaderAyahWords(
                      key: ValueKey('ayah-$ayah'),
                      surah: 1,
                      ayah: ayah,
                      words: quranWords(text),
                      style: const TextStyle(fontSize: 28),
                      registry: registry,
                      range: ranges.lastOrNull,
                      onRange: (range) => setState(() => ranges.add(range)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final first = tester.getRect(find.byKey(const ValueKey('ayah-5')));
      final second = tester.getRect(find.byKey(const ValueKey('ayah-6')));
      // RTL: the first word is at the right end of the line.
      final gesture = await tester.startGesture(
        Offset(first.right - 30, first.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(ranges.single, const QuranWordRange.single(QuranWord(1, 5, 1)));
      await gesture.moveTo(Offset(second.left + 30, second.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(ranges.last.start, const QuranWord(1, 5, 1));
      expect(ranges.last.end, const QuranWord(1, 6, 3));
      expect(
        find.byKey(const ValueKey('word-range-end-handle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a finger pulls a handle down into the next ayah', (
      tester,
    ) async {
      // A list scrolls once a finger moves past the device's touch slop.
      tester.view.gestureSettings = const ui.GestureSettings(
        physicalTouchSlop: 8,
      );
      addTearDown(tester.view.resetGestureSettings);
      var range = const QuranWordRange.single(QuranWord(1, 5, 1));
      final registry = ReaderWordRegistry();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(
                controller: scroll,
                children: <Widget>[
                  for (final (ayah, text) in <(int, String)>[
                    (5, 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ'),
                    (6, 'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ'),
                  ])
                    // The translation under each ayah in the reader.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: ReaderAyahWords(
                        key: ValueKey('ayah-$ayah'),
                        surah: 1,
                        ayah: ayah,
                        words: quranWords(text),
                        style: const TextStyle(fontSize: 28),
                        registry: registry,
                        range: range,
                        onRange: (value) => setState(() => range = value),
                      ),
                    ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      final handle = find.byKey(const ValueKey('word-range-end-handle'));
      final knob = _knobCenter(tester, handle);
      final second = tester.getRect(find.byKey(const ValueKey('ayah-6')));
      // To the last word of the next ayah (RTL: its left end). The handle
      // leaves its card on the way, and the drag must go on in the other one.
      await _fingerDrag(
        tester,
        knob,
        Offset(second.left + 30, second.center.dy) +
            (knob - tester.getTopLeft(handle)) -
            const Offset(22, 0),
      );

      expect(range.end, const QuranWord(1, 6, 3));
      expect(scroll.offset, 0);
      expect(wordRangePulling.value, isFalse);
    });
  });
}

typedef _PageHarness = ({
  List<({QuranWordRange range, int count})> ranges,
  List<String> opened,
  List<String> selected,
  List<int> backgroundTaps,
});

Future<_PageHarness> _pumpPage(
  WidgetTester tester, {
  QuranWordRange? initial,
  bool inPageView = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  if (inPageView) {
    // Android phones report a touch slop under the 18 px default: the page
    // swipe then claims a moving finger before an 18 px recognizer would.
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8,
    );
    addTearDown(tester.view.resetGestureSettings);
  }
  final page = MushafPageData.fromFoundation(_pageJson);
  await tester.runAsync(
    () => loadFoundationPageResources(page.foundation!, _asset),
  );
  final ranges = <({QuranWordRange range, int count})>[];
  final opened = <String>[];
  final selected = <String>[];
  final backgroundTaps = <int>[];
  var range = initial;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedMushafRepositoryProvider.overrideWithValue(_Quran()),
        mushafPageProvider(604).overrideWith((ref) async => page),
        tajweedPageProvider(604).overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => _MaybePageView(
              inPageView: inPageView,
              child: NativeMushafPage(
                page: 604,
                controller: NativeMushafPageController(),
                selectedAyah: null,
                playingAyah: null,
                onSelectAyah: (ayah) => selected.add(ayah.key),
                onOpenAyah: (ayah) => opened.add(ayah.key),
                onBackgroundTap: () => backgroundTaps.add(1),
                onScale: (_) {},
                wordRange: range,
                onWordRange: (value, count) {
                  ranges.add((range: value, count: count));
                  setState(() => range = value);
                },
                onOpenWord: (ayah, position) {
                  opened.add('${ayah.key}:$position');
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (
    ranges: ranges,
    opened: opened,
    selected: selected,
    backgroundTaps: backgroundTaps,
  );
}

/// The reader's pages, as in MushafScreen: a drag on a handle competes
/// with the page swipe.
class _MaybePageView extends StatelessWidget {
  const _MaybePageView({required this.inPageView, required this.child});

  final bool inPageView;
  final Widget child;

  @override
  Widget build(BuildContext context) => !inPageView
      ? child
      : PageView(
          controller: PageController(initialPage: 1),
          reverse: true,
          children: <Widget>[const SizedBox(), child, const SizedBox()],
        );
}

/// The middle of a handle's knob: the handle is its line plus
/// [WordRangeHandle.extra], and the knob starts 4 px under the line.
Offset _knobCenter(WidgetTester tester, Finder handle) {
  final rect = tester.getRect(handle);
  final line = rect.height - WordRangeHandle.extra;
  return rect.topLeft +
      Offset(rect.width / 2, line + 4 + WordRangeHandle.knob / 2);
}

/// Moves a finger like a person does: many small steps, never a jump.
Future<void> _fingerDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  const steps = 12;
  for (var step = 1; step <= steps; step++) {
    await gesture.moveTo(Offset.lerp(from, to, step / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

typedef _PanelHarness = ({
  WordRangeController Function() controller,
  _Engine engine,
  _AudioRepository repository,
});

_PanelHarness? _lastPanel;

Future<_PanelHarness> _pumpPanel(
  WidgetTester tester, {
  bool timed = true,
  bool withTeaching = false,
  bool teachingTimed = true,
  bool withMurattal = false,
  bool teachingChosen = false,
}) async {
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  final repository = _AudioRepository(
    timed: timed,
    withTeaching: withTeaching,
    teachingTimed: teachingTimed,
    withMurattal: withMurattal,
    teachingChosen: teachingChosen,
  );
  final host = GlobalKey<_HostState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioRepositoryProvider.overrideWithValue(repository),
        audioControllerProvider.overrideWith((ref) => audio),
        appPreferencesProvider.overrideWith((ref) => _Preferences()),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Host(key: host),
      ),
    ),
  );
  final harness = (
    controller: () => host.currentState!.controller,
    engine: engine,
    repository: repository,
  );
  _lastPanel = harness;
  return harness;
}

class _Host extends ConsumerStatefulWidget {
  const _Host({super.key});

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  late final controller = WordRangeController(ref);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: WordRangePanel(controller: controller),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Offset _wordCenter(WidgetTester tester, int position) {
  final canvas = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is FoundationPagePainter,
  );
  final painter =
      tester.widget<CustomPaint>(canvas).painter! as FoundationPagePainter;
  final word = painter.layout.words.firstWhere(
    (word) => word.reference.key == '112:4' && word.position == position,
  );
  return tester.getTopLeft(canvas) + word.rect.center;
}

final _pageJson = <String, Object?>{
  'mushaf_id': 19,
  'page_number': 604,
  'pages_count': 604,
  'lines_per_page': 15,
  'source_checksum_sha256': 'a' * 64,
  'verse_mapping': {'112': '4'},
  'rendering': {
    'available': true,
    'version': 2,
    'mode': 'page-font',
    'native_font_url':
        'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p604.ttf',
  },
  'words': page604Words,
};

Future<File> _asset(Uri uri, String version) async =>
    File('assets/fonts/AmiriQuran-Regular.ttf');

class _Quran implements QuranRepository {
  @override
  Future<File> foundationAsset(Uri uri, String version) => _asset(uri, version);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

({Duration start, Duration end}) _ms(int start, int end) =>
    (start: Duration(milliseconds: start), end: Duration(milliseconds: end));

class _AudioRepository implements AudioRepository {
  _AudioRepository({
    required this.timed,
    this.withTeaching = false,
    this.teachingTimed = true,
    this.withMurattal = false,
    this.teachingChosen = false,
  });

  /// Whether the chosen reciter (`rec-1`) has the words' timings.
  final bool timed;

  /// Whether the catalog also has al-Husary's Muallim, and whether it has them.
  final bool withTeaching;
  final bool teachingTimed;

  /// al-Husary's Murattal (`rec-6`), with every word timed; and whether the
  /// Muallim is the catalog's teaching reciter, so the Mushaf plays it.
  final bool withMurattal;
  final bool teachingChosen;
  final requested = <String>[];
  final requestedBy = <String>[];

  static final _words = <int, Map<int, ({Duration start, Duration end})>>{
    5: {
      1: _ms(18000, 19200),
      2: _ms(19200, 20400),
      3: _ms(21300, 22300),
      4: _ms(22300, 23000),
    },
    6: {1: _ms(23300, 24600), 2: _ms(24600, 25600), 3: _ms(25600, 27000)},
  };

  @override
  Future<List<Recitation>> recitationsForRole(
    AudioRecitationRole role, {
    bool forceRefresh = false,
  }) async => <Recitation>[
    Recitation.fromJson(const <String, Object?>{
      'id': 'rec-1',
      'code': 'qf-7-1',
      'reciter': {'id': 'husary', 'name_en': 'Husary', 'name_ru': 'Husary'},
      'rights': {'stream': true},
      'coverage': {'surah_count': 114},
      'timings': {'available': true, 'complete': true},
      'capabilities': {
        'listen': true,
        'ayah_playback': true,
        'memorization': true,
        'offline': false,
      },
    }),
    if (withMurattal)
      Recitation.fromJson(const <String, Object?>{
        'id': 'rec-6',
        'code': 'qf-6-murattal-01a15bc65dc9',
        'style': 'murattal',
        'reciter': {
          'id': 'al-husary-6',
          'name_en': 'al-Husary',
          'name_ru': 'аль-Хусари',
        },
        'rights': {'stream': true},
        'coverage': {'surah_count': 114},
        'timings': {'available': true, 'complete': true},
        'capabilities': {
          'listen': true,
          'ayah_playback': true,
          'memorization': true,
          'offline': false,
        },
      }),
    if (withTeaching)
      Recitation.fromJson(<String, Object?>{
        'id': 'rec-12',
        'code': 'qf-12-muallim-01a15bc65dc9',
        'style': 'muallim',
        'teaching_default': teachingChosen,
        'reciter': {
          'id': 'al-husary',
          'name_en': 'al-Husary',
          'name_ru': 'аль-Хусари',
        },
        'rights': {'stream': true},
        'coverage': {'surah_count': 114},
        'timings': {'available': true, 'complete': true},
        'capabilities': {
          'listen': true,
          'ayah_playback': true,
          'memorization': true,
          'offline': false,
        },
      }),
  ];

  @override
  Future<AyahPlayback> ayahPlayback({
    required String recitationId,
    required int surah,
    required int ayah,
  }) async {
    requested.add('$surah:$ayah');
    requestedBy.add('$recitationId:$surah:$ayah');
    final has = switch (recitationId) {
      'rec-12' => teachingTimed,
      'rec-6' => true,
      _ => timed,
    };
    return AyahPlayback(
      track: AudioTrack(
        id: 'track-$recitationId',
        recitationId: recitationId,
        surah: surah,
        url: 'https://cdn.example/$recitationId/001.mp3',
        duration: const Duration(minutes: 1),
        offlineDownloadAllowed: false,
      ),
      words: has ? _words[ayah] ?? const {} : const {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences() : super(const AppPreferences.defaults());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements IqroAudioEngine {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final sources = <AudioSource>[];
  var plays = 0;

  void complete() {
    processingState = ProcessingState.completed;
    _states.add(PlayerState(playing, ProcessingState.completed));
  }

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    sources.add(source);
    processingState = ProcessingState.ready;
    return const Duration(seconds: 1);
  }

  @override
  Future<void> clearAudioSources() async =>
      processingState = ProcessingState.idle;
  @override
  Future<void> setSpeed(double value) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> play() async {
    plays++;
    playing = true;
    processingState = ProcessingState.ready;
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    playing = false;
    _states.add(PlayerState(false, processingState));
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {
    playing = false;
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() => _states.close();
}
