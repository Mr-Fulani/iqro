import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:iqro_mobile/features/quran/reader_screen.dart';
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
    expect(_place(tester), 'Аят ٣ · стр. ١');
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
      expect(_place(tester), 'Аят ٢ · стр. ١');
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
      expect(_place(tester), 'Аят ٢ · стр. ١');
      expect(tester.takeException(), isNull);
    });
  }
}

/// The middle of [ayah]'s Arabic text, scrolled onto the screen.
Future<Offset> _card(WidgetTester tester, int ayah) async {
  final finder = find.byKey(ValueKey('reader-ayah-$ayah'));
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return tester.getCenter(finder);
}

String _place(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('reader-flow-place'))).data!;

int _placeAyah(WidgetTester tester) {
  final digits = _place(tester).split(' ')[1];
  return int.parse(
    String.fromCharCodes(digits.codeUnits.map((unit) => unit - 0x0660 + 48)),
  );
}

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
  List<QuranDivision> rubs = const <QuranDivision>[],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final database = _Database();
  final quran = _Quran();
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
    ProviderScope(
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
      ],
      child: MaterialApp.router(
        theme: IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
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
