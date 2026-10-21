import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/memorization/memorization_tajweed_text.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'tajweed_test_data.dart';

void main() {
  testWidgets('the legend lists only the page rules, in reference order', (
    tester,
  ) async {
    await _pumpMushaf(tester);
    expect(find.text('Правила таджвида на странице'), findsOneWidget);
    expect(
      tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data),
      ['Идгам без гунны', 'Калькаля', 'Мадд табии'],
    );
    expect(find.text('Ихфа'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a coloured word opens its card and still selects the ayah', (
    tester,
  ) async {
    final harness = await _pumpMushaf(tester);
    await tester.tapAt(_wordCenter(tester, 2));
    await _settle(tester);

    expect(harness.tajweedWords.map((ayah) => ayah.key), ['112:4']);
    expect(harness.selected, isEmpty);
    expect(find.text('Таджвид в слове'), findsOneWidget);
    expect(find.text('Идгам без гунны'), findsWidgets);
    expect(find.text('الإدغام بغير غنة'), findsOneWidget);
    expect(find.text('Почему здесь'), findsOneWidget);
    expect(find.text('Как читать'), findsOneWidget);
    expect(
      find.text(
        'Нун с сукуном или танвин в конце слова перед ل или ر.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Нун не произносится: сразу читайте удвоенную ل или ر.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // The idgham crosses into the next word: both words are shown together.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('tajweed-why-idgham_wo_ghunnah')),
          )
          .textSpan!
          .toPlainText(),
      'يَكُن لَّهُۥ',
    );
    expect(
      find.text('Пояснения проходят проверку у преподавателя таджвида.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('each rule of a word has its section, variant texts included', (
    tester,
  ) async {
    await _pumpMushaf(tester);
    await tester.tapAt(_wordCenter(tester, 3));
    await _settle(tester);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('tajweed-why-idgham_wo_ghunnah')),
          )
          .textSpan!
          .toPlainText(),
      'يَكُن لَّهُۥ',
    );
    expect(find.text('Мадд табии · Мадд силя сугра'), findsOneWidget);
    expect(
      find.text('Хаъ местоимения между огласованными буквами.'),
      findsOneWidget,
    );
    expect(
      find.text('При слитном чтении тяните на 2 хараката.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('tajweed-why-madda_normal')))
          .textSpan!
          .toPlainText(),
      'لَّهُۥ',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('words without rules and ayah markers select as before', (
    tester,
  ) async {
    final harness = await _pumpMushaf(tester);
    await tester.tapAt(_wordCenter(tester, 1));
    await tester.tapAt(_wordCenter(tester, 4));
    await _settle(tester);
    expect(harness.selected.map((ayah) => ayah.key), ['112:4', '112:4']);
    expect(harness.tajweedWords, isEmpty);
    expect(find.text('Таджвид в слове'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a legend chip opens the rule and its occurrences on the page', (
    tester,
  ) async {
    await _pumpMushaf(tester);
    await tester.tap(find.text('Идгам без гунны'));
    await _settle(tester);

    expect(find.text('Правило таджвида'), findsOneWidget);
    expect(find.text('Когда действует'), findsOneWidget);
    expect(find.text('Где на этой странице'), findsOneWidget);
    final occurrence = find.ancestor(
      of: find.text('112:4'),
      matching: find.byType(ListTile),
    );
    expect(occurrence, findsOneWidget);
    expect(
      find.descendant(
        of: occurrence,
        matching: find.text('يَكُن لَّهُۥ', findRichText: true),
      ),
      findsOneWidget,
    );

    await tester.tap(occurrence);
    await _settle(tester);
    expect(find.text('Таджвид в слове'), findsOneWidget);
    expect(find.text('Правило таджвида'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the word timing there is no listen button', (
    tester,
  ) async {
    await _pumpMushaf(tester, timings: const {});
    await tester.tapAt(_wordCenter(tester, 2));
    await _settle(tester);
    expect(find.text('Таджвид в слове'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-listen')), findsNothing);
    expect(find.text('Послушать фрагмент'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listen plays exactly the word, slower when 0.75× is on', (
    tester,
  ) async {
    final harness = await _pumpMushaf(tester);
    await harness.audio.loadStandalone(
      id: 'dua:1',
      url: 'https://cdn.example/dua.mp3',
      title: 'Dua',
    );
    await tester.tapAt(_wordCenter(tester, 2));
    await _settle(tester);

    expect(find.text('Послушать фрагмент'), findsOneWidget);
    final slow = find.byKey(const ValueKey('tajweed-slow'));
    expect(tester.widget<FilterChip>(slow).selected, isFalse);
    await tester.tap(slow);
    await tester.pump();
    expect(tester.widget<FilterChip>(slow).selected, isTrue);
    expect(
      tester.semantics.find(slow).getSemanticsData().tooltip,
      'Медленнее, 0,75×',
    );

    final stopsBefore = harness.engine.stopCalls;
    await tester.tap(find.byKey(const ValueKey('tajweed-listen')));
    await _settle(tester);

    final source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.child.uri, Uri.parse('https://cdn.example/112.mp3'));
    expect(source.start, const Duration(milliseconds: 9600));
    expect(source.end, const Duration(milliseconds: 10100));
    expect(harness.engine.speed, .75);
    expect(harness.engine.stopCalls, greaterThan(stopsBefore));
    expect(harness.repository.requested, ('recitation-1', 112, 4));
    expect(
      harness.audio.state.standalone?.mediaItem.id,
      'tajweed:recitation-1:112:4:2',
    );
    expect(find.text('Остановить'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tajweed-listen')));
    await _settle(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(find.text('Послушать фрагмент'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without tajweed data the page behaves as before', (
    tester,
  ) async {
    final harness = await _pumpMushaf(tester, tajweed: false);
    expect(find.byType(ActionChip), findsNothing);
    await tester.tapAt(_wordCenter(tester, 2));
    await _settle(tester);
    expect(harness.selected.map((ayah) => ayah.key), ['112:4']);
    expect(find.text('Таджвид в слове'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('another Mushaf edition never shows tajweed', (tester) async {
    final harness = await _pumpMushaf(tester, mushafId: 5);
    expect(find.byType(ActionChip), findsNothing);
    await tester.tapAt(_wordCenter(tester, 2));
    await _settle(tester);
    expect(harness.selected.map((ayah) => ayah.key), ['112:4']);
    expect(harness.tajweedWords, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('memorization', () {
    testWidgets('coloured words open their card; the ayah has its legend', (
      tester,
    ) async {
      await _pumpMemorization(tester);
      expect(find.text('Правила таджвида в аяте'), findsOneWidget);
      expect(find.text('plain'), findsNothing);
      expect(find.byKey(const ValueKey('tajweed-word-4-1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tajweed-word-4-2')));
      await _settle(tester);
      expect(find.text('Таджвид в слове'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('tajweed-why-idgham_wo_ghunnah')),
            )
            .textSpan!
            .toPlainText(),
        'يَكُن لَّهُۥ',
      );
      expect(find.text('Послушать фрагмент'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await _settle(tester);

      await tester.tap(find.text('Калькаля'));
      await _settle(tester);
      expect(find.text('Где в этом аяте'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('أَحَدُۢ', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('without the glyphs the plain text stays', (tester) async {
      await _pumpMemorization(tester, glyphs: false);
      expect(find.text('plain'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

const _fontUrl =
    'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p604.ttf';

Map<String, Object?> _pageJson(int mushafId) => {
  'mushaf_id': mushafId,
  'page_number': 604,
  'pages_count': 604,
  'lines_per_page': 15,
  'source_checksum_sha256': 'a' * 64,
  'verse_mapping': {'112': '4'},
  'rendering': {
    'available': true,
    'version': 2,
    'mode': 'page-font',
    'native_font_url': _fontUrl,
  },
  'words': page604Words,
};

Future<File> _asset(Uri uri, String version) async =>
    File('assets/fonts/AmiriQuran-Regular.ttf');

final _defaultTimings = {
  2: (
    start: const Duration(milliseconds: 9600),
    end: const Duration(milliseconds: 10100),
  ),
};

typedef _Harness = ({
  List<QuranAyahReference> selected,
  List<QuranAyahReference> tajweedWords,
  AudioController audio,
  _Engine engine,
  _AudioRepository repository,
});

Future<_Harness> _pumpMushaf(
  WidgetTester tester, {
  bool tajweed = true,
  int mushafId = 19,
  Map<int, ({Duration start, Duration end})>? timings,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final page = MushafPageData.fromFoundation(_pageJson(mushafId));
  // The page font is loaded once outside the fake clock; the page then finds
  // it ready, as on a second opening.
  await tester.runAsync(
    () => loadFoundationPageResources(page.foundation!, _asset),
  );
  final selected = <QuranAyahReference>[];
  final tajweedWords = <QuranAyahReference>[];
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  final repository = _AudioRepository(timings ?? _defaultTimings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedMushafRepositoryProvider.overrideWithValue(_Quran()),
        mushafPageProvider(604).overrideWith((ref) async => page),
        tajweedRulesProvider.overrideWith(
          (ref) async => TajweedReference.fromJson(tajweedRulesJson),
        ),
        tajweedPageProvider(604).overrideWith(
          (ref) async =>
              tajweed ? TajweedPage.fromJson(tajweedPage604Json, 604) : null,
        ),
        audioRepositoryProvider.overrideWithValue(repository),
        audioControllerProvider.overrideWith((ref) => audio),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NativeMushafPage(
            page: 604,
            controller: NativeMushafPageController(),
            selectedAyah: null,
            playingAyah: null,
            onSelectAyah: selected.add,
            onOpenAyah: (_) {},
            onBackgroundTap: () {},
            onScale: (_) {},
            onTajweedWord: tajweedWords.add,
            tajweedRecitation: () async => 'recitation-1',
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (
    selected: selected,
    tajweedWords: tajweedWords,
    audio: audio,
    engine: engine,
    repository: repository,
  );
}

Future<void> _pumpMemorization(
  WidgetTester tester, {
  bool glyphs = true,
}) async {
  const range = (surah: 112, start: 4, end: 4);
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        memorizationTajweedTextProvider(range).overrideWith((ref) async {
          if (!glyphs) throw const FormatException('No page font');
          return MemorizationTajweedText(
            words: {
              4: [
                for (final word in page604Words)
                  (
                    word: word,
                    fontFamily: IqroTheme.arabicFontFamily,
                    position: word['char_type_name'] == 'word'
                        ? word['position_in_verse']! as int
                        : null,
                  ),
              ],
            },
            pages: {4: 604},
          );
        }),
        tajweedRulesProvider.overrideWith(
          (ref) async => TajweedReference.fromJson(tajweedRulesJson),
        ),
        tajweedPageProvider(604).overrideWith(
          (ref) async => TajweedPage.fromJson(tajweedPage604Json, 604),
        ),
        audioRepositoryProvider.overrideWithValue(
          _AudioRepository(_defaultTimings),
        ),
        audioControllerProvider.overrideWith((ref) => audio),
      ],
      child: MaterialApp(
        theme: IqroTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
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
    ),
  );
  await _settle(tester);
}

/// The page font was loaded on the real clock, so the page also needs real
/// event-loop turns between frames.
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
    orElse: () => painter.layout.words.last,
  );
  return tester.getTopLeft(canvas) + word.rect.center;
}

class _Quran implements QuranRepository {
  @override
  Future<File> foundationAsset(Uri uri, String version) => _asset(uri, version);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioRepository implements AudioRepository {
  _AudioRepository(this.timings);
  final Map<int, ({Duration start, Duration end})> timings;
  (String, int, int)? requested;

  @override
  Future<AyahPlayback> ayahPlayback({
    required String recitationId,
    required int surah,
    required int ayah,
  }) async {
    requested = (recitationId, surah, ayah);
    return AyahPlayback(
      track: AudioTrack(
        id: 'track-112',
        recitationId: recitationId,
        surah: surah,
        url: 'https://cdn.example/112.mp3',
        duration: const Duration(minutes: 1),
        offlineDownloadAllowed: false,
      ),
      words: timings,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements IqroAudioEngine {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final sources = <AudioSource>[];
  var speed = 1.0;
  var stopCalls = 0;

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
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() => _states.close();
}
