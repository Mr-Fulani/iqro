import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/memorization/memorization_tajweed_text.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_breakdown.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'tajweed_test_data.dart';

void main() {
  testWidgets('steps follow the ayah rule by rule, then sum it up', (
    tester,
  ) async {
    await _pumpBreakdown(tester);

    expect(_label(tester), '1 из 3');
    expect(find.bySemanticsLabel('1 из 3: Идгам без гунны'), findsOneWidget);
    expect(find.text('Идгам без гунны'), findsOneWidget);
    // The idgham crosses into the next word: one step, both words lit.
    expect(_stepWord(tester), 'يَكُن لَّهُۥ');
    expect(_lit(tester), [2, 3]);
    expect(
      find.text('Нун с сукуном или танвин в конце слова перед ل или ر.'),
      findsOneWidget,
    );
    expect(_button(tester, 'tajweed-back').onPressed, isNull);

    await _next(tester);
    expect(_label(tester), '2 из 3');
    expect(find.text('Мадд табии · Мадд силя сугра'), findsOneWidget);
    expect(find.text('Хаъ местоимения между огласованными буквами.'), findsOne);
    expect(_stepWord(tester), 'لَّهُۥ');
    expect(_lit(tester), [3]);

    await _next(tester);
    expect(_label(tester), '3 из 3');
    expect(find.text('Калькаля · Калькаля при остановке'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Итог'), findsOneWidget);

    await _next(tester);
    expect(_label(tester), 'Итог');
    expect(find.text('Правила, которые встретились в аяте'), findsOneWidget);
    expect(_lit(tester), isEmpty);
    expect(
      tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data),
      ['Идгам без гунны', 'Мадд табии', 'Калькаля'],
    );
    expect(find.widgetWithText(FilledButton, 'Готово'), findsOneWidget);

    // A rule's card from the summary leads to its step.
    await tester.tap(find.byKey(const ValueKey('tajweed-summary-qalaqah')));
    await _settle(tester);
    expect(find.text('Когда действует'), findsOneWidget);
    expect(find.text('Где в этом аяте'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tajweed-occurrence-2')));
    await _settle(tester);
    expect(_label(tester), '3 из 3');
    expect(find.byKey(const ValueKey('tajweed-rule-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a step plays its words; turning the step stops the sound', (
    tester,
  ) async {
    final harness = await _pumpBreakdown(tester);
    await tester.tap(find.byKey(const ValueKey('tajweed-slow')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tajweed-listen')));
    await _settle(tester);

    var source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.child.uri, Uri.parse('https://cdn.example/112.mp3'));
    // Both words of the idgham, from the first word's start to the second's end.
    expect(source.start, const Duration(milliseconds: 9600));
    expect(source.end, const Duration(milliseconds: 10600));
    expect(harness.engine.speed, .75);
    expect(find.text('Остановить'), findsOneWidget);

    await _next(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(find.text('Послушать фрагмент'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tajweed-listen')));
    await _settle(tester);
    source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 10100));
    expect(source.end, const Duration(milliseconds: 10600));
    expect(
      harness.audio.state.standalone?.mediaItem.id,
      'tajweed:recitation-1:112:4:step1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole ayah lights the word being recited', (tester) async {
    final harness = await _pumpBreakdown(tester);
    await tester.tap(find.byKey(const ValueKey('tajweed-play-ayah')));
    await _settle(tester);

    final source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 9000));
    expect(source.end, const Duration(milliseconds: 12000));
    expect(find.text('Прослушать весь аят'), findsNothing);

    // The clip's position counts from the ayah's start.
    harness.engine.positions.add(const Duration(milliseconds: 1300));
    await _settle(tester);
    expect(_reading(tester), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow keys turn steps along the reading direction', (
    tester,
  ) async {
    await _pumpBreakdown(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(_label(tester), '2 из 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(_label(tester), '1 из 3');

    await _pumpBreakdown(tester, locale: const Locale('ar'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(_label(tester), '2 من 3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the reciter\'s timings nothing offers to play', (
    tester,
  ) async {
    await _pumpBreakdown(tester, recitation: false);
    expect(find.byKey(const ValueKey('tajweed-listen')), findsNothing);
    expect(find.byKey(const ValueKey('tajweed-play-ayah')), findsNothing);
    expect(_label(tester), '1 из 3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long ayah scrolls the step\'s words into view', (
    tester,
  ) async {
    final harness = await _pumpBreakdown(
      tester,
      size: const Size(375, 812),
      ayah: _longAyahJson,
      glyphs: _longGlyphs,
      timings: {
        2: _timings[2]!,
        3: _timings[3]!,
        88: (
          start: const Duration(milliseconds: 11500),
          end: const Duration(milliseconds: 11900),
        ),
      },
    );
    final line = find.byKey(const ValueKey('tajweed-ayah-line'));
    // Far longer than the phone is wide, the ayah wraps in a short box.
    expect(tester.getSize(line).height, lessThan(160));
    void expectShown(List<int> positions) {
      final box = tester.getRect(line);
      for (final position in positions) {
        final word = tester.getRect(
          find.byKey(ValueKey('tajweed-glyph-$position')),
        );
        expect(
          box.inflate(1).contains(word.topLeft) &&
              box.inflate(1).contains(word.bottomRight),
          isTrue,
          reason: 'word $position at $word, box $box',
        );
      }
    }

    expect(_label(tester), '1 из 5');
    expectShown([2, 3]);
    await _next(tester);
    expectShown([3]);
    await _next(tester);
    expectShown([5]);
    await _next(tester);
    expect(_label(tester), '4 из 5');
    expectShown([45]);
    await _next(tester);
    expectShown([88]);
    await tester.tap(find.byKey(const ValueKey('tajweed-back')));
    await _settle(tester);
    expect(_label(tester), '4 из 5');
    expectShown([45]);
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.byKey(const ValueKey('tajweed-back')));
      await _settle(tester);
    }
    expect(_label(tester), '1 из 5');
    expectShown([2, 3]);

    // While the whole ayah plays, the box follows the reciter's word.
    await tester.tap(find.byKey(const ValueKey('tajweed-play-ayah')));
    await _settle(tester);
    harness.engine.positions.add(const Duration(milliseconds: 2600));
    await _settle(tester);
    expectShown([88]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the coloured memorization ayah opens its breakdown', (
    tester,
  ) async {
    await _pumpMemorization(tester);
    final open = find.byKey(const ValueKey('tajweed-breakdown-4'));
    expect(open, findsOneWidget);
    expect(find.text('Разбор таджвида'), findsOneWidget);
    await tester.tap(open);
    await _settle(tester);
    expect(find.byType(TajweedBreakdownSheet), findsOneWidget);
    expect(_label(tester), '1 из 3');
    expect(find.byKey(const ValueKey('tajweed-listen')), findsOneWidget);

    await tester.tap(find.byTooltip('Закрыть'));
    await _settle(tester);
    expect(find.byType(TajweedBreakdownSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('steps keep reading order and split the rules of one word', () {
    final reference = TajweedReference.fromJson(tajweedRulesJson);
    final ayah = TajweedAyah.fromJson(tajweedAyah1124Json);
    final steps = tajweedSteps(ayah, reference);
    expect(
      [
        for (final step in steps)
          '${step.code} ${step.variant} '
              '${step.parts.map((part) => part.word.position).join(',')}',
      ],
      [
        'idgham_wo_ghunnah null 2,3',
        'madda_normal silah_sughra 3',
        'qalaqah stop 5',
      ],
    );
    expect(
      tajweedStepRules([...steps, steps.first]).map((rule) => rule.steps),
      [
        [0, 3],
        [1],
        [2],
      ],
    );
    expect(tajweedStepTiming(_timings, steps.first), (
      start: const Duration(milliseconds: 9600),
      end: const Duration(milliseconds: 10600),
    ));
    expect(tajweedStepTiming(const {}, steps.first), isNull);
    expect(
      tajweedTimedPosition(_timings, const Duration(milliseconds: 10100)),
      3,
    );
    expect(
      tajweedTimedPosition(_timings, const Duration(milliseconds: 9000)),
      isNull,
    );
  });
}

final _timings = <int, ({Duration start, Duration end})>{
  2: (
    start: const Duration(milliseconds: 9600),
    end: const Duration(milliseconds: 10100),
  ),
  3: (
    start: const Duration(milliseconds: 10100),
    end: const Duration(milliseconds: 10600),
  ),
  5: (
    start: const Duration(milliseconds: 11200),
    end: const Duration(milliseconds: 12000),
  ),
};

final _glyphs = <TajweedGlyph>[
  for (final word in page604Words)
    (
      word: word,
      fontFamily: IqroTheme.arabicFontFamily,
      position: word['char_type_name'] == 'word'
          ? word['position_in_verse']! as int
          : null,
    ),
];

/// 112:4 stretched to 90 words, as long as 2:282, with rules in its middle
/// and near its end.
final _longAyahJson = <String, Object?>{
  ...tajweedAyah1124Json,
  'words': [
    ...tajweedAyah1124Json['words']! as List<Object?>,
    {
      'position': 45,
      'text': 'قَالُوا',
      'rules': [
        {'code': 'madda_normal', 'start': 3, 'end': 4},
      ],
    },
    {
      'position': 88,
      'text': 'أَحَدُۢ',
      'rules': [
        {'code': 'qalaqah', 'start': 4, 'end': 5, 'variant': 'stop'},
      ],
    },
  ],
};

final _longGlyphs = <TajweedGlyph>[
  for (var position = 1; position <= 91; position++)
    (
      word: <String, Object?>{
        'id': position,
        'verse_key': '112:4',
        'position_in_verse': position,
        'char_type_name': position == 91 ? 'end' : 'word',
        'text': 'قل',
      },
      fontFamily: IqroTheme.arabicFontFamily,
      position: position == 91 ? null : position,
    ),
];

typedef _Harness = ({AudioController audio, _Engine engine});

List<Override> _overrides(
  AudioController audio, {
  bool recitation = true,
  List<TajweedGlyph>? glyphs,
  Map<int, ({Duration start, Duration end})>? timings,
}) => [
  tajweedAyahGlyphsProvider((
    page: 604,
    verseKey: '112:4',
  )).overrideWith((ref) async => glyphs ?? _glyphs),
  tajweedRulesProvider.overrideWith(
    (ref) async => TajweedReference.fromJson(tajweedRulesJson),
  ),
  tajweedPageProvider(
    604,
  ).overrideWith((ref) async => TajweedPage.fromJson(tajweedPage604Json, 604)),
  audioRepositoryProvider.overrideWithValue(
    _AudioRepository(recitation ? timings ?? _timings : const {}),
  ),
  audioControllerProvider.overrideWith((ref) => audio),
];

Widget _app(Locale locale, Widget home) => MaterialApp(
  theme: IqroTheme.light(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

Future<_Harness> _pumpBreakdown(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  bool recitation = true,
  Size size = const Size(400, 900),
  Map<String, Object?>? ayah,
  List<TajweedGlyph>? glyphs,
  Map<int, ({Duration start, Duration end})>? timings,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // A new scope for each pump: a test may pump the sheet twice.
      key: UniqueKey(),
      overrides: _overrides(audio, glyphs: glyphs, timings: timings),
      child: _app(
        locale,
        TajweedBreakdownSheet(
          reference: TajweedReference.fromJson(tajweedRulesJson),
          ayah: TajweedAyah.fromJson(ayah ?? tajweedAyah1124Json),
          recitation: recitation ? () async => 'recitation-1' : null,
        ),
      ),
    ),
  );
  await _settle(tester);
  return (audio: audio, engine: engine);
}

Future<void> _pumpMemorization(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  const range = (surah: 112, start: 4, end: 4);
  final audio = AudioController(engine: _Engine());
  addTearDown(audio.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._overrides(audio),
        memorizationTajweedTextProvider(range).overrideWith(
          (ref) async =>
              MemorizationTajweedText(words: {4: _glyphs}, pages: {4: 604}),
        ),
      ],
      child: _app(
        const Locale('ru'),
        const SingleChildScrollView(
          child: MemorizationTajweedAyah(
            ayah: QuranAyah(
              id: 'a',
              surahNumber: 112,
              number: 4,
              textUthmani: 'وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ',
              pages: [604],
            ),
            range: range,
            recitationId: 'recitation-1',
            fallback: Text('plain'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tajweed-next')));
  await _settle(tester);
}

String? _label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('tajweed-step-label'))).data;

ButtonStyleButton _button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));

/// The step's word(s) on the current page of the pager.
String _stepWord(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('tajweed-step-word')).hitTestable())
    .textSpan!
    .toPlainText();

BoxDecoration _decoration(WidgetTester tester, int position) =>
    tester
            .widget<AnimatedContainer>(
              find.byKey(ValueKey('tajweed-glyph-$position')),
            )
            .decoration!
        as BoxDecoration;

/// Positions of the words the current step lights in the ayah.
List<int> _lit(WidgetTester tester) => [
  for (final position in [1, 2, 3, 4, 5])
    if (_decoration(tester, position).border != null) position,
];

int? _reading(WidgetTester tester) {
  final scheme = Theme.of(
    tester.element(find.byType(TajweedBreakdownSheet)),
  ).colorScheme;
  for (final position in [1, 2, 3, 4, 5]) {
    if (_decoration(tester, position).color == scheme.primaryContainer) {
      return position;
    }
  }
  return null;
}

class _AudioRepository implements AudioRepository {
  _AudioRepository(this.timings);
  final Map<int, ({Duration start, Duration end})> timings;

  @override
  Future<AyahPlayback> ayahPlayback({
    required String recitationId,
    required int surah,
    required int ayah,
  }) async => AyahPlayback(
    track: AudioTrack(
      id: 'track-112',
      recitationId: recitationId,
      surah: surah,
      url: 'https://cdn.example/112.mp3',
      duration: const Duration(minutes: 1),
      offlineDownloadAllowed: false,
    ),
    words: timings,
    start: timings.isEmpty ? null : const Duration(milliseconds: 9000),
    end: timings.isEmpty ? null : const Duration(milliseconds: 12000),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements IqroAudioEngine {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final sources = <AudioSource>[];
  var speed = 1.0;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
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
    return null;
  }

  @override
  Future<void> clearAudioSources() async =>
      processingState = ProcessingState.idle;
  @override
  Future<void> setSpeed(double value) async => speed = value;
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> play() async {
    playing = true;
    _states.add(PlayerState(true, processingState));
  }

  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {
    playing = false;
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await _states.close();
  }
}
