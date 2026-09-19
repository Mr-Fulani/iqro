import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/core/platform/reader_haptics.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_raster_layout.dart';
import 'package:iqro_mobile/features/quran/mushaf_screen.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'reader menu opens bookmarks and jumps to the mapped Mushaf page',
    (tester) async {
      final harness = await _pump(tester, bookmarks: {'5:84'});
      await _tapAyah(tester, .35);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Закладки'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('bookmark-5-84')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bookmark-5-84')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(harness.quran.mappedAyah, (5, 84));
      expect(find.text('Страница 123'), findsOneWidget);
      expect(find.text('Аят 5:84'), findsOneWidget);
      expect(harness.quran.saved.last, 84);
      expect(find.text('Закладки'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty bookmarks explain how to save an ayah', (tester) async {
    await _pump(tester);
    await _tapAyah(tester, .35);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Закладки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Пока нет закладок.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmark list can retry a failed local read', (tester) async {
    final harness = await _pump(tester, bookmarks: {'5:85'});
    harness.quran.failBookmarkRead = true;
    await _tapAyah(tester, .35);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Закладки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось загрузить закладки'), findsOneWidget);
    harness.quran.failBookmarkRead = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('bookmark-5-85')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmark icon follows saved ayahs, addition and removal', (
    tester,
  ) async {
    final harness = await _pump(tester, bookmarks: {'5:84'});
    final button = find.byKey(const ValueKey('mushaf-bookmark'));
    expect(tester.widget<IconButton>(button).isSelected, true);
    await _tapAyah(tester, .35);
    expect(tester.widget<IconButton>(button).isSelected, false);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(harness.quran.bookmarked, contains('5:85'));
    expect(tester.widget<IconButton>(button).isSelected, true);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.bookmark_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(harness.quran.bookmarked, isNot(contains('5:85')));
    expect(tester.widget<IconButton>(button).isSelected, false);
    await _tapAyah(tester, .15);
    expect(tester.widget<IconButton>(button).isSelected, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late bookmark save does not mark another selected ayah', (
    tester,
  ) async {
    final harness = await _pump(tester);
    final button = find.byKey(const ValueKey('mushaf-bookmark'));
    await _tapAyah(tester, .35);
    harness.quran.pendingBookmark = Completer<void>();
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    await _tapAyah(tester, .15);
    harness.quran.pendingBookmark!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Аят 5:84'), findsOneWidget);
    expect(tester.widget<IconButton>(button).isSelected, false);
    await _tapAyah(tester, .35);
    expect(tester.widget<IconButton>(button).isSelected, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed bookmark removal keeps the filled icon', (tester) async {
    final harness = await _pump(tester, bookmarks: {'5:85'});
    final button = find.byKey(const ValueKey('mushaf-bookmark'));
    await _tapAyah(tester, .35);
    harness.quran.failBookmark = true;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<IconButton>(button).isSelected, true);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'page dots keep controls visible and vibrate once per actual page change',
    (tester) async {
      final vibrations = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReaderHaptics.channel,
        (call) async {
          vibrations.add(call);
          return 'played';
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ReaderHaptics.channel,
          null,
        ),
      );
      await _pump(tester);
      expect(vibrations, isEmpty);
      await _tapAyah(tester, .35);
      await tester.tap(find.byKey(const ValueKey('mushaf-page-dot-123')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Страница 123').hitTestable(), findsOneWidget);
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
      expect(vibrations, hasLength(1));
      expect(vibrations.single.method, 'pageTick');
      await tester.tap(find.byKey(const ValueKey('mushaf-page-dot-123')));
      await tester.pump();
      expect(vibrations, hasLength(1));
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
      expect(vibrations, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tap selects without autoplay, round play button plays only that ayah',
    (tester) async {
      final harness = await _pump(tester);
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
      await _tapAyah(tester, .35);
      expect(find.text('Аят 5:85'), findsOneWidget);
      expect(find.byType(FloatingActionButton).hitTestable(), findsOneWidget);
      expect(harness.controller.ranges, isEmpty);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.controller.ranges, <(int?, int?)>[(85, 85)]);
      expect(harness.audio.requestedSurah, 5);
      expect(harness.quran.saved.last, 85);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mini-player-play-toggle')));
      await tester.pump();
      expect(harness.controller.toggles, 1);
      expect(harness.controller.ranges, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'another selected ayah cancels an obsolete pending audio request',
    (tester) async {
      final harness = await _pump(tester);
      harness.audio.pending = Completer<List<Recitation>>();
      await _tapAyah(tester, .35);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await _tapAyah(tester, .15);
      harness.audio.pending!.complete(<Recitation>[_recitation]);
      await tester.pump();
      expect(find.text('Аят 5:84'), findsOneWidget);
      expect(harness.controller.ranges, isEmpty);
      expect(harness.audio.requestedSurah, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-ayah second tap hides controls but keeps selection', (
    tester,
  ) async {
    await _pump(tester);
    await _tapAyah(tester, .35);
    await _tapAyah(tester, .35);
    expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
    expect(find.text('Аят 5:85'), findsOneWidget);
  });
}

Future<void> _tapAyah(WidgetTester tester, double y) async {
  final detector = find
      .byWidgetPredicate(
        (w) => w is GestureDetector && w.onLongPressStart != null,
      )
      .first;
  final box = tester.renderObject<RenderBox>(detector);
  final layout = MushafRasterLayout.page(
    page: _page(122),
    size: box.size,
    portrait: true,
  );
  await tester.tapAt(box.localToGlobal(layout.displayPoint(Offset(.5, y))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<({_Audio controller, _AudioRepository audio, _Quran quran})> _pump(
  WidgetTester tester, {
  Set<String> bookmarks = const {},
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final database = _Database();
  final plan = _Plan();
  final quran = _Quran(database.accountScope)..bookmarked.addAll(bookmarks);
  final audio = _AudioRepository();
  final controller = _Audio();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        quranRepositoryProvider.overrideWithValue(quran),
        mushafPageProvider.overrideWith((ref, page) async => _page(page)),
        quranCatalogProvider.overrideWith(
          (ref) async => const QuranCatalog(surahs: <Surah>[], fromCache: true),
        ),
        quranJuzProvider.overrideWith((ref) async => const <QuranDivision>[]),
        audioRepositoryProvider.overrideWithValue(audio),
        audioControllerProvider.overrideWith((ref) => controller),
        recitersProvider.overrideWith((ref) async => <Reciter>[_reciter]),
      ],
      child: MaterialApp(
        theme: IqroTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MushafScreen(initialPage: 122, surah: 5, ayah: 84),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (controller: controller, audio: audio, quran: quran);
}

MushafPageData _page(int number) => MushafPageData(
  number: number,
  contentVersion: 'v1',
  checksumSha256: '',
  imageWidth: 900,
  imageHeight: 1380,
  assets: const <MushafAsset>[
    MushafAsset(url: 'https://example.test/page.webp', width: 2700, sha256: ''),
  ],
  regions: <MushafAyahRegion>[
    for (final (ayah, y) in <(int, double)>[(84, .1), (85, .3)])
      MushafAyahRegion(
        id: '$ayah',
        ayah: QuranAyahReference(id: '', surah: 5, ayah: ayah),
        readingOrder: ayah,
        polygon: const [],
        x: .1,
        y: y,
        width: .8,
        height: .1,
      ),
  ],
);

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting('reader');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quran implements QuranRepository {
  _Quran(this.scope);
  final AccountScope scope;
  final saved = <int>[];
  final bookmarked = <String>{};
  Completer<void>? pendingBookmark;
  bool failBookmark = false;
  bool failBookmarkRead = false;
  (int, int)? mappedAyah;
  @override
  Future<int> pageForAyah(int surah, int ayah, {required int fallback}) async {
    mappedAyah = (surah, ayah);
    return 123;
  }

  @override
  Future<List<Map<String, Object?>>> bookmarks({
    AccountScopeSnapshot? accountScope,
  }) async {
    if (failBookmarkRead) throw StateError('read failed');
    return bookmarked.map((key) {
      final parts = key.split(':');
      return <String, Object?>{
        'surah': int.parse(parts[0]),
        'ayah': int.parse(parts[1]),
      };
    }).toList();
  }

  @override
  Future<bool> isBookmarked(
    int surah,
    int ayah, {
    AccountScopeSnapshot? accountScope,
  }) async => bookmarked.contains('$surah:$ayah');
  @override
  Future<bool> toggleBookmark(
    int surah,
    int ayah, {
    int? page,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (pendingBookmark != null) await pendingBookmark!.future;
    if (failBookmark) throw StateError('write failed');
    final key = '$surah:$ayah';
    if (bookmarked.remove(key)) return false;
    bookmarked.add(key);
    return true;
  }

  final pendingImage = Completer<File>();
  @override
  QuranRepository forMushaf(MushafIdentity identity) => this;
  @override
  Future<AccountScopeSnapshot> captureAccount() => scope.capture();
  @override
  Future<ReadingPosition> position({
    AccountScopeSnapshot? accountScope,
  }) async => const ReadingPosition(
    edition: 'madani-hafs',
    entityId: 'position',
    surah: 5,
    ayah: 84,
    page: 122,
    revision: 1,
  );
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
  Future<File> cachedMushafPageAsset(MushafPageData page, MushafAsset asset) =>
      pendingImage.future;
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

final _reciter = Reciter.fromJson(<String, Object?>{
  'id': 'test-reciter',
  'name_ru': 'Тестовый чтец',
});
final _recitation = Recitation(
  id: 'test-recitation',
  code: 'test',
  reciter: _reciter,
  style: 'murattal',
  timingsAvailable: true,
  surahCount: 114,
  streamAllowed: true,
  offlineDownloadAllowed: false,
);

class _AudioRepository implements AudioRepository {
  Completer<List<Recitation>>? pending;
  int? requestedSurah;
  @override
  Future<List<Recitation>> recitations({
    String? reciterId,
    bool forceRefresh = false,
  }) async =>
      pending == null ? <Recitation>[_recitation] : await pending!.future;
  @override
  Future<SurahPlayback> playback({
    required String recitationId,
    required int surah,
    bool forceRefresh = false,
  }) async {
    requestedSurah = surah;
    return SurahPlayback(
      track: AudioTrack(
        id: 'test-track',
        recitationId: recitationId,
        surah: surah,
        url: 'https://example.test/audio.mp3',
        duration: const Duration(minutes: 1),
        offlineDownloadAllowed: false,
      ),
      segments: const <AudioSegment>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio extends AudioController {
  _Audio() : super(engine: _Engine());
  final ranges = <(int?, int?)>[];
  var toggles = 0;
  @override
  Future<void> loadPlayback({
    required SurahPlayback playback,
    required Reciter reciter,
    required String surahName,
    int? startAyah,
    int? endAyah,
    bool autoplay = true,
  }) async {
    ranges.add((startAyah, endAyah));
    state = IqroAudioState(
      track: playback.track,
      reciter: reciter,
      surahName: surahName,
      playing: autoplay,
      activeAyah: startAyah,
      rangeStartAyah: startAyah,
      rangeEndAyah: endAyah,
    );
  }

  @override
  Future<void> toggle() async {
    toggles++;
    state = state.copyWith(playing: !state.playing);
  }
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
