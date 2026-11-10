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
import 'package:iqro_mobile/features/quran/reader_screen.dart';
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

  testWidgets('the end of a surah offers the next one; a tap opens it from '
      'its first ayah', (tester) async {
    final app = await _pump(tester);
    await _toEnd(tester);
    expect(find.text('3. Али Имран'), findsOneWidget);
    expect(find.text('Потяните вверх или нажмите'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('next-surah-card')));
    await tester.pumpAndSettle();
    expect(app.location, '/reader/3');
    expect(find.text('Али Имран'), findsWidgets);
    expect(app.quran.saved.last, (3, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pull past the end opens the next surah; a short one does '
      'not', (tester) async {
    final app = await _pump(tester);
    await _toEnd(tester);
    final list = find.byType(ListView).first;

    await tester.drag(list, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(app.location, '/reader/2');

    final gesture = await tester.startGesture(tester.getCenter(list));
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Отпустите — откроется сура 3'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(app.location, '/reader/3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected words keep the end of the surah where it is', (
    tester,
  ) async {
    final app = await _pump(tester);
    await _toEnd(tester);
    await tester.longPressAt(
      tester.getCenter(find.byKey(const ValueKey('reader-ayah-12'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('word-range-panel')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('next-surah-card')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(app.location, '/reader/2');
  });

  testWidgets('after an-Nas the Quran ends: no next surah', (tester) async {
    await _pump(tester, surah: 114);
    await _toEnd(tester, key: 'quran-end');
    expect(find.text('Конец Корана'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-surah-card')), findsNothing);
    expect(find.byKey(const ValueKey('quran-end-surah-list')), findsOneWidget);
  });

  testWidgets('the plain text moves on to the next surah, and the cards open '
      'on it when it is left', (tester) async {
    final app = await _pump(tester);
    final card = tester.getCenter(find.byKey(const ValueKey('reader-ayah-2')));
    await tester.timedDragFrom(
      card,
      const Offset(220, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-flow')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('next-surah-card')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reader-flow')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('سُورَةُ آل عمران'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-surah-card')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('reader-flow-place'))).data,
      'Аят 1 · стр. 3',
    );
    // The new surah's own title at the top.
    expect(find.text('سُورَةُ آل عمران'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(300, 400),
      const Offset(-220, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-flow')), findsNothing);
    expect(app.location, '/reader/3');
    expect(tester.takeException(), isNull);
  });
}

/// Scrolls the reader to the card after the last ayah.
Future<void> _toEnd(
  WidgetTester tester, {
  String key = 'next-surah-card',
}) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  // To the very end, no further: the next pull goes past it.
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

class _App {
  _App(this.quran, this.store, this.router);

  final _Quran quran;
  final PreferencesStore store;
  final GoRouter router;

  String get location => router.routerDelegate.state.uri.path;

  AppPreferences get preferences => store.read();
}

Future<_App> _pump(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  int surah = 2,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final database = _Database();
  final quran = _Quran();
  final plan = _Plan();
  final router = GoRouter(
    initialLocation: '/reader/$surah',
    routes: <RouteBase>[
      GoRoute(
        path: '/reader/:surah',
        builder: (context, state) => ReaderScreen(
          key: ValueKey(state.uri.toString()),
          surah: int.parse(state.pathParameters['surah']!),
          initialAyah:
              int.tryParse(state.uri.queryParameters['ayah'] ?? '') ?? 1,
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => const Scaffold(body: Text('Суры')),
      ),
      GoRoute(
        path: '/mushaf',
        builder: (context, state) => const Scaffold(body: Text('Мусхаф')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final app = _App(quran, store, router);
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
        ayahsProvider.overrideWith((ref, surah) async => _ayahsOf(surah)),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(
            surahs: <Surah>[_baqara, _imran, _falaq, _nas],
            fromCache: true,
          ),
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

const _baqara = Surah(
  id: '2',
  number: 2,
  nameAr: 'البقرة',
  nameEn: 'Al-Baqarah',
  nameRu: 'Аль-Бакара',
  ayahCount: 12,
  revelationType: 'medinan',
);

const _imran = Surah(
  id: '3',
  number: 3,
  nameAr: 'آل عمران',
  nameEn: 'Ali Imran',
  nameRu: 'Али Имран',
  ayahCount: 8,
  revelationType: 'medinan',
);

const _falaq = Surah(
  id: '113',
  number: 113,
  nameAr: 'الفلق',
  nameEn: 'Al-Falaq',
  nameRu: 'Аль-Фалак',
  ayahCount: 5,
  revelationType: 'meccan',
);

const _nas = Surah(
  id: '114',
  number: 114,
  nameAr: 'الناس',
  nameEn: 'An-Nas',
  nameRu: 'Ан-Нас',
  ayahCount: 6,
  revelationType: 'meccan',
);

const _verse =
    'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُقِيمُونَ ٱلصَّلَوٰةَ '
    'وَمِمَّا رَزَقْنَٰهُمْ يُنفِقُونَ';

List<QuranAyah> _ayahsOf(int surah) => <QuranAyah>[
  for (
    var number = 1;
    number <=
        switch (surah) {
          2 => 12,
          3 => 8,
          _ => 6,
        };
    number++
  )
    QuranAyah(
      id: '$surah:$number',
      surahNumber: surah,
      number: number,
      textUthmani: number == 1
          ? 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ'
          : _verse,
      pages: <int>[surah == 3 ? 3 : 1 + (number - 1) ~/ 6],
    ),
];

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('reader');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quran implements QuranRepository {
  final saved = <(int, int)>[];

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
    saved.add((surah, ayah));
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
