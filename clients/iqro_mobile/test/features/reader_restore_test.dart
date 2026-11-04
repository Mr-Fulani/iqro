import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
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
  testWidgets('an ayah far down a surah of long and short ayahs is opened, '
      'not one near it', (tester) async {
    // Long ayahs first, short ones after: the list's length estimate from the
    // first cards is far off, and a jump by share of it lands elsewhere.
    await _pump(tester, initialAyah: 250, ayahs: _mixedAyahs);
    final target = find.byKey(const ValueKey('reader-ayah-250'));
    expect(target, findsOneWidget);
    expect(_topInList(tester, target), inInclusiveRange(0, 60));
  });

  testWidgets('the opened ayah stays at the top while translations arrive and '
      'the cards above it grow', (tester) async {
    final harness = await _pump(tester, initialAyah: 40);
    final target = find.byKey(const ValueKey('reader-ayah-40'));
    expect(target, findsOneWidget);
    final before = _topInList(tester, target);
    expect(before, lessThan(60));

    // A surah opened for the first time: its translation comes from the
    // network after the reader has jumped to the ayah.
    harness.quran.translationsReady.complete();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byKey(const ValueKey('reader-translation-40')), findsOneWidget);
    expect(_topInList(tester, target), closeTo(before, 24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reader who scrolls away is left where they scrolled', (
    tester,
  ) async {
    final harness = await _pump(tester, initialAyah: 40);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 500));
    final scrolled = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    harness.quran.translationsReady.complete();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      closeTo(scrolled, 1),
    );
  });
}

/// The top of [finder]'s card below the top of the list.
double _topInList(WidgetTester tester, Finder finder) {
  final list = tester.getTopLeft(find.byType(ListView));
  return tester.getTopLeft(finder).dy - list.dy;
}

Future<({_Quran quran})> _pump(
  WidgetTester tester, {
  required int initialAyah,
  List<QuranAyah>? ayahs,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final database = _Database();
  final plan = _Plan();
  final quran = _Quran(database.accountScope, ayahs ?? _ayahs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _SignedOut()),
        localDatabaseProvider.overrideWithValue(database),
        activeAccountScopeKeyProvider.overrideWith(
          (ref) => accountScopeKey(database.accountScope.current!),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            environment: 'production',
            fallbackDownloadUrl: 'https://iqro.forum',
          ),
        ),
        appPreferencesProvider.overrideWith(
          (ref) => AppPreferencesController(store, plan),
        ),
        planRepositoryProvider.overrideWithValue(plan),
        audioRepositoryProvider.overrideWithValue(_AudioRepository()),
        audioControllerProvider.overrideWith(
          (ref) => AudioController(engine: _Engine()),
        ),
        quranRepositoryProvider.overrideWithValue(quran),
        ayahsProvider.overrideWith((ref, surah) async => ayahs ?? _ayahs),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(surahs: <Surah>[], fromCache: true),
        ),
        ayahAnnotationsProvider.overrideWith(
          (ref, account) async => const <Map<String, Object?>>[],
        ),
      ],
      child: MaterialApp(
        theme: IqroTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReaderScreen(surah: 2, initialAyah: initialAyah),
      ),
    ),
  );
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return (quran: quran);
}

final _ayahs = <QuranAyah>[
  for (var number = 1; number <= 60; number++)
    QuranAyah(
      id: 'ayah-$number',
      surahNumber: 2,
      number: number,
      textUthmani: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      pages: const <int>[2],
    ),
];

final _mixedAyahs = <QuranAyah>[
  for (var number = 1; number <= 286; number++)
    QuranAyah(
      id: 'ayah-$number',
      surahNumber: 2,
      number: number,
      textUthmani: number <= 100
          ? List<String>.filled(40, 'ٱلْحَمْدُ لِلَّهِ').join(' ')
          : 'ٱلْحَمْدُ لِلَّهِ',
      pages: const <int>[2],
    ),
];

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('reader');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quran implements QuranRepository {
  _Quran(this.scope, this.surahAyahs);
  final AccountScope scope;
  final List<QuranAyah> surahAyahs;

  /// Holds the surah's translation back, as a first download does.
  final translationsReady = Completer<void>();

  @override
  Future<List<QuranTranslationEdition>> translationEditions(
    String locale, {
    bool forceRefresh = false,
  }) async => const <QuranTranslationEdition>[
    QuranTranslationEdition(
      sourceId: 1,
      languageCode: 'ru',
      name: 'Test',
      authorName: 'Test',
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
  }) async {
    await translationsReady.future;
    return <QuranAyahTranslation>[
      for (final ayah in surahAyahs)
        QuranAyahTranslation(
          verseKey: '2:${ayah.number}',
          surah: 2,
          ayah: ayah.number,
          // Long enough to make every card several lines taller.
          text: List<String>.filled(
            12,
            'Хвала Аллаху, Господу миров.',
          ).join(' '),
          footnotes: const <String>[],
        ),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> bookmarks({
    AccountScopeSnapshot? accountScope,
  }) async => const <Map<String, Object?>>[];

  @override
  Future<AccountScopeSnapshot> captureAccount() => scope.capture();

  @override
  Future<void> savePosition({
    required int surah,
    required int ayah,
    required int page,
    AccountScopeSnapshot? accountScope,
  }) async {}

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
