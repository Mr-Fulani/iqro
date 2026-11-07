// Screenshots of the new Home (sky of prayers, plan traveller, section
// tiles) for the pull request and docs/guides/home:
//
//   flutter test test/features/home_screenshots_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Real fonts come from the Flutter SDK (Roboto, Material icons) and macOS
// (Georgia for `serif`, SF Arabic); the portrait is the site's own file.
// Without SCREENSHOT_DIR the test is skipped: CI checks behaviour elsewhere.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/app/app_shell.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/announcements/announcement_controller.dart';
import 'package:iqro_mobile/features/announcements/announcement_logic.dart';
import 'package:iqro_mobile/features/announcements/announcement_parts.dart';
import 'package:iqro_mobile/features/announcements/news_screen.dart';
import 'package:iqro_mobile/features/calendar/calendar_catalog.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_service.dart';
import 'package:iqro_mobile/features/memorization/memorization_repository.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'announcement_test_data.dart';

const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _size = Size(1080, 2340); // Redmi Note 7
const _pixelRatio = 2.75;
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Roboto', <String>[
    for (final weight in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$weight.ttf',
  ]);
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('serif', <String>[
    '/System/Library/Fonts/Supplemental/Georgia.ttf',
    '/System/Library/Fonts/Supplemental/Georgia Bold.ttf',
  ]);
  await family('SF Arabic', ['/System/Library/Fonts/SFArabic.ttf']);
}

/// The test engine has no system font fallback: name the Arabic font.
ThemeData _withArabic(ThemeData theme) {
  final text = theme.textTheme.apply(fontFamilyFallback: const ['SF Arabic']);
  final label = WidgetStatePropertyAll(text.labelLarge);
  return theme.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(textStyle: label),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(textStyle: label),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String location,
  required List<Announcement> active,
  Locale locale = const Locale('ru'),
  Map<String?, AnnouncementFeedPage> pages = const {},
  AnnouncementLocalState stored = const AnnouncementLocalState(),
  bool dark = false,
  bool still = true,
  DateTime? clock,
  double textScale = 1,
  Size size = _size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = _pixelRatio;
  tester.view.padding = const FakeViewPadding(top: 66);
  addTearDown(tester.view.reset);
  final portrait = MemoryImage(
    File(
      '../../services/web/public/reciters/yasser-ad-dussary.webp',
    ).readAsBytesSync(),
  );
  final repository = FakeAnnouncementRepository(active: active, pages: pages)
    ..stored = stored;
  final router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(
        path: '/app',
        builder: (context, state) => AppShell(
          initialIndex: int.parse(state.uri.queryParameters['tab'] ?? '0'),
        ),
      ),
      GoRoute(path: '/news', builder: (context, state) => const NewsScreen()),
    ],
  );
  addTearDown(router.dispose);
  final database = _Database();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: [
          announcementRepositoryProvider.overrideWithValue(repository),
          announcementImageProvider.overrideWithValue((_) => portrait),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              apiBaseUrl: 'https://iqro.forum',
              fallbackDownloadUrl: 'https://iqro.forum',
              environment: 'production',
            ),
          ),
          sessionProvider.overrideWith(
            (ref) => FakeSessionController(testSession(status: 'guest')),
          ),
          localDatabaseProvider.overrideWithValue(database),
          activeAccountScopeKeyProvider.overrideWithValue(
            accountScopeKey(database.accountScope.current!),
          ),
          appPreferencesProvider.overrideWith((ref) => _Preferences()),
          audioControllerProvider.overrideWith((ref) => _IdleAudio()),
          recitersProvider.overrideWith((ref) async => []),
          planProvider.overrideWith((ref) => _Plan()),
          memorizationProvider.overrideWith((ref) => _Memorization()),
          duaEntriesProvider.overrideWith((ref) async => []),
          prayerScheduleProvider.overrideWith((ref, key) async => _schedule),
          prayerMethodsProvider.overrideWith((ref) async => []),
          calendarClockProvider.overrideWith(
            (ref) => Stream.value(clock ?? DateTime(2026, 11, 6, 13, 8)),
          ),
          calendarCatalogProvider.overrideWith((ref) => const Stream.empty()),
          readingPositionProvider.overrideWith(
            (ref, key) async => const ReadingPosition(
              edition: 'madani',
              entityId: 'position',
              surah: 18,
              ayah: 10,
              page: 294,
              revision: 1,
            ),
          ),
          quranCatalogProvider.overrideWith(
            (ref) async => const QuranCatalog(
              surahs: [
                Surah(
                  id: 'surah-18',
                  number: 18,
                  nameAr: 'الكهف',
                  nameEn: 'Al-Kahf',
                  nameRu: 'Аль-Кахф',
                  ayahCount: 110,
                  revelationType: 'meccan',
                ),
              ],
              fromCache: true,
            ),
          ),
          mushafRenditionsProvider.overrideWith((ref) async => []),
          mushafDownloadProvider.overrideWithValue(
            const MushafDownloadSnapshot.empty(),
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: _withArabic(IqroTheme.light()),
          darkTheme: _withArabic(IqroTheme.dark()),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: still,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (still) await _settle(tester);
}

/// Image decoding runs outside the fake clock.
Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  if (settle) await _settle(tester);
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_directory/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  expect(tester.takeException(), isNull);
}

final _schedule = PrayerSchedule(
  date: DateTime(2026, 11, 6),
  timezone: 'Europe/Moscow',
  times: {
    'fajr': DateTime(2026, 11, 6, 5, 52),
    'sunrise': DateTime(2026, 11, 6, 7, 41),
    'dhuhr': DateTime(2026, 11, 6, 12, 15),
    'asr': DateTime(2026, 11, 6, 14, 18),
    'maghrib': DateTime(2026, 11, 6, 16, 38),
    'isha': DateTime(2026, 11, 6, 18, 22),
  },
  timesUtc: const {},
  methodName: 'test',
  warnings: const [],
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    if (_directory.isNotEmpty) await _loadFonts();
  });

  testWidgets('day, light', (tester) async {
    await _pumpApp(tester, location: '/app?tab=0', active: const []);
    await _capture(tester, 'home-day-ru');
  }, skip: _directory.isEmpty);

  testWidgets('the whole page', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      size: const Size(1080, 3000),
    );
    await _capture(tester, 'home-full-ru');
  }, skip: _directory.isEmpty);

  testWidgets('evening, dark', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      dark: true,
      clock: DateTime(2026, 11, 6, 16, 5),
    );
    await _capture(tester, 'home-evening-dark-ru');
  }, skip: _directory.isEmpty);

  testWidgets('night, dark', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      dark: true,
      clock: DateTime(2026, 11, 6, 21, 40),
    );
    await _capture(tester, 'home-night-dark-ru');
  }, skip: _directory.isEmpty);

  testWidgets('dawn, Arabic', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      locale: const Locale('ar'),
      clock: DateTime(2026, 11, 6, 6, 40),
    );
    await _capture(tester, 'home-dawn-ar');
  }, skip: _directory.isEmpty);

  testWidgets('large text', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      textScale: 1.3,
    );
    await _capture(tester, 'home-large-ru');
  }, skip: _directory.isEmpty);

  testWidgets('the opening animation, frame by frame', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      still: false,
    );
    for (var frame = 0; frame <= 62; frame++) {
      await _capture(
        tester,
        'home-anim-${frame.toString().padLeft(2, '0')}',
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, skip: _directory.isEmpty);

  testWidgets('the night opening: the sun sets, the moon rises', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: const [],
      dark: true,
      still: false,
      clock: DateTime(2026, 11, 6, 19, 30),
    );
    for (var frame = 0; frame <= 62; frame++) {
      if (frame % 10 == 0 || frame == 62) {
        await _capture(
          tester,
          'home-night-anim-${frame.toString().padLeft(2, '0')}',
          settle: false,
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, skip: _directory.isEmpty);

  testWidgets('More lists the downloads', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=4',
      active: const [],
      size: const Size(1080, 3600),
    );
    await _capture(tester, 'more-ru');
  }, skip: _directory.isEmpty);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences() : super(const AppPreferences.defaults());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleAudio extends StateNotifier<IqroAudioState>
    implements AudioController {
  _IdleAudio() : super(const IqroAudioState());

  @override
  IqroAudioPresentation listeningPresentation(IqroAudioState current) =>
      iqroAudioPresentation(current);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plan extends StateNotifier<AsyncValue<DailyPlan>>
    implements PlanController {
  _Plan()
    : super(
        AsyncData(const DailyPlan.initial(target: 5).copyWith(achieved: 3)),
      );
  @override
  bool isBoundTo(AccountScopeSnapshot scope) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Memorization extends StateNotifier<AsyncValue<MemorizationDashboard>>
    implements MemorizationController {
  _Memorization() : super(const AsyncLoading());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
