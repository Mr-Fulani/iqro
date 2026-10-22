// Screenshots of the announcements for the pull request and docs:
//
//   flutter test test/features/announcement_screenshots_test.dart \
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

List<Announcement> _announcements() => <Announcement>[
  testAnnouncement(<String, Object?>{
    'image': <String, Object?>{
      'url': 'https://cdn.example.test/yasser.webp',
      'thumb_url': 'https://cdn.example.test/yasser-96.webp',
      'width': 512,
      'height': 512,
      'alt': '',
    },
  }),
  featureAnnouncement(),
];

List<Announcement> _arabic() => <Announcement>[
  testAnnouncement(<String, Object?>{
    'title': 'قارئ جديد: ياسر الدوسري',
    'summary': 'جميع السور الـ114 بترتيل هادئ.',
    'image': <String, Object?>{
      'url': 'https://cdn.example.test/yasser.webp',
      'thumb_url': null,
      'width': 512,
      'height': 512,
      'alt': '',
    },
    'action': <String, Object?>{
      'type': 'reciter',
      'label': 'استمع',
      'web_path': '/ar/audio?reciter=r1&play=1',
      'app_route': '/audio/reciter/r1?play=1',
      'external_url': null,
    },
  }),
  featureAnnouncement(),
];

Future<void> _pumpApp(
  WidgetTester tester, {
  required String location,
  required List<Announcement> active,
  Locale locale = const Locale('ru'),
  Map<String?, AnnouncementFeedPage> pages = const {},
  AnnouncementLocalState stored = const AnnouncementLocalState(),
}) async {
  tester.view.physicalSize = _size;
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
          prayerScheduleProvider.overrideWith((ref, key) async => null),
          prayerMethodsProvider.overrideWith((ref) async => []),
          calendarClockProvider.overrideWith(
            (ref) => Stream.value(DateTime(2026, 10, 22, 12)),
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
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
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

Future<void> _capture(WidgetTester tester, String name) async {
  await _settle(tester);
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    if (_directory.isNotEmpty) await _loadFonts();
  });

  testWidgets('home, window and feed in Russian', (tester) async {
    await _pumpApp(tester, location: '/app?tab=0', active: _announcements());
    await _capture(tester, 'app-home-bubble-ru');

    await tester.tap(find.byKey(const ValueKey('announcement-bubble')));
    await _settle(tester);
    await _capture(tester, 'app-window-reciter-ru');

    await tester.tap(find.byKey(const ValueKey('announcement-next')));
    await _settle(tester);
    await _capture(tester, 'app-window-feature-ru');
  }, skip: _directory.isEmpty);

  testWidgets('More shows unread news', (tester) async {
    await _pumpApp(tester, location: '/app?tab=4', active: _announcements());
    await _capture(tester, 'app-more-ru');
  }, skip: _directory.isEmpty);

  testWidgets('the feed', (tester) async {
    final feature = featureAnnouncement();
    await _pumpApp(
      tester,
      location: '/news',
      active: _announcements(),
      pages: <String?, AnnouncementFeedPage>{
        null: AnnouncementFeedPage(
          nextCursor: 'next',
          results: <Announcement>[
            ..._announcements(),
            testAnnouncement(<String, Object?>{
              'id': announcementIdC,
              'kind': 'app_release',
              'starts_at': '2026-10-15T00:00:00Z',
              'title': 'IQRO 1.1',
              'summary': 'Быстрее открывается Мусхаф, исправлены ошибки.',
              'bubble': <String, Object?>{
                'icon': 'arrow_up',
                'frequency': 'weekly',
                'max_impressions': 3,
              },
              'action': <String, Object?>{
                'type': 'none',
                'label': '',
                'web_path': null,
                'app_route': null,
                'external_url': null,
              },
            }),
          ],
        ),
      },
      stored: markRead(
        const AnnouncementLocalState(),
        feature.id,
        DateTime.utc(2026, 10, 21),
      ),
    );
    await _capture(tester, 'app-news-ru');
  }, skip: _directory.isEmpty);

  testWidgets('Arabic, right to left', (tester) async {
    await _pumpApp(
      tester,
      location: '/app?tab=0',
      active: _arabic(),
      locale: const Locale('ar'),
    );
    await _capture(tester, 'app-home-bubble-ar');
    await tester.tap(find.byKey(const ValueKey('announcement-bubble')));
    await _settle(tester);
    await _capture(tester, 'app-window-reciter-ar');
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
