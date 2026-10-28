import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/app/app_shell.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/mini_player.dart';
import 'package:iqro_mobile/features/calendar/calendar_catalog.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_service.dart';
import 'package:iqro_mobile/features/home/home_screen.dart';
import 'package:iqro_mobile/features/memorization/memorization_repository.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

// Redmi Note 7 turned to landscape: 2340x1080 px at 2.75, status bar on top
// and the camera cutout on the left.
const _landscape = Size(2340, 1080);
const _pixelRatio = 2.75;

void main() {
  setUpAll(initializeDateFormatting);

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'dark=$dark scale=$scale Home keeps Read clear of the player',
        (tester) async {
          await _pumpShell(tester, tab: 0, dark: dark, scale: scale);
          final read = find.ancestor(
            of: find.text(_l10n(tester).read),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          _expectClearOfPlayer(tester, read);
          _expectClearOfPlayer(
            tester,
            find.byKey(const ValueKey('home-reading')),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('dark=$dark scale=$scale Quran fits beside its surah list', (
        tester,
      ) async {
        await _pumpShell(tester, tab: 1, dark: dark, scale: scale);
        expect(tester.takeException(), isNull);
        final l10n = _l10n(tester);
        final list = find.byType(ListView);
        final search = find.byType(SearchBar);
        expect(list, findsOneWidget);
        expect(search, findsOneWidget);
        // Cards and search scroll in one column, the list fills the other.
        expect(
          tester.getRect(search).right,
          lessThan(tester.getRect(list).left),
        );
        expect(find.text('Аль-Фатиха'), findsOneWidget);
        _expectClearOfPlayer(tester, list);
        await tester.scrollUntilVisible(
          find.text('Ан-Нас'),
          600,
          maxScrolls: 200,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.ensureVisible(search);
        await tester.tap(find.text(l10n.continueSaved));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('dark=$dark scale=$scale Plan and More fit', (tester) async {
        for (final tab in [2, 4]) {
          await _pumpShell(tester, tab: tab, dark: dark, scale: scale);
          expect(tester.takeException(), isNull);
          _expectClearOfPlayer(
            tester,
            find.descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Text),
            ),
          );
        }
      });
    }
  }

  // A Galaxy A55 (1080x2340 px at 420 dpi) with three-button navigation
  // edge-to-edge keeps a 48 dp inset under the tab bar; the player ran
  // under the bar by exactly that much.
  for (final (device, size, ratio) in [
    ('phone', const Size(1080, 2340), 2.625),
    ('phone landscape', const Size(2340, 1080), 2.625),
    ('tablet', const Size(1600, 2560), 2.0),
    ('tablet landscape', const Size(2560, 1600), 2.0),
  ]) {
    for (final buttons in [false, true]) {
      testWidgets('$device buttons=$buttons player sits above the tab bar', (
        tester,
      ) async {
        for (final scale in [1.0, 1.3, 1.6, 2.0]) {
          for (final collapsed in [true, false]) {
            final reason = 'scale=$scale collapsed=$collapsed';
            await _pumpShell(
              tester,
              tab: 0,
              scale: scale,
              size: size,
              pixelRatio: ratio,
              padding: _systemBars(size, ratio, buttons: buttons),
              collapsed: collapsed,
            );
            expect(tester.takeException(), isNull, reason: reason);
            final screen = size / ratio;
            final bar = tester.getRect(find.byType(NavigationBar));
            expect(bar.bottom, screen.height, reason: reason);
            final player = tester.getRect(find.byType(IqroMiniPlayer));
            expect(player.top, greaterThan(0), reason: reason);
            expect(player.bottom, moreOrLessEquals(bar.top), reason: reason);
            final visible = tester.getRect(
              collapsed
                  ? find.byKey(const ValueKey('mini-player-expand'))
                  : find.descendant(
                      of: find.byType(IqroMiniPlayer),
                      matching: find.byType(ListTile),
                    ),
            );
            expect(visible.bottom, lessThanOrEqualTo(bar.top), reason: reason);
            // The page scrolls its last card clear of the bar too.
            final page = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is SingleChildScrollView &&
                      widget.scrollDirection == Axis.vertical,
                )
                .first;
            await tester.drag(page, const Offset(0, -20000));
            await tester.pumpAndSettle();
            final texts = find.descendant(
              of: page,
              matching: find.byType(Text),
            );
            final contentEnd = [
              for (var index = 0; index < texts.evaluate().length; index++)
                tester.getRect(texts.at(index)).bottom,
            ].reduce((a, b) => a > b ? a : b);
            expect(contentEnd, lessThanOrEqualTo(bar.top), reason: reason);
          }
        }
      });
    }
  }

  testWidgets('portrait keeps the cards above the surah list', (tester) async {
    await _pumpShell(tester, tab: 1, size: const Size(1080, 2340));
    expect(
      tester.getRect(find.byType(SearchBar)).bottom,
      lessThan(tester.getRect(find.byType(ListView)).top),
    );
    expect(tester.takeException(), isNull);
  });
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AppShell)));

/// The collapsed mini player floats at the end edge over every tab, so
/// content must end before it at any scroll offset.
void _expectClearOfPlayer(WidgetTester tester, Finder target) {
  final player = tester.getRect(
    find.byKey(const ValueKey('mini-player-expand')),
  );
  expect(target, findsWidgets);
  for (var index = 0; index < target.evaluate().length; index++) {
    final rect = tester.getRect(target.at(index));
    expect(
      rect.right,
      lessThanOrEqualTo(player.left),
      reason:
          '${target.at(index)} ends at ${rect.right}, '
          'the player starts at ${player.left}',
    );
  }
}

/// System bars in physical pixels: the status bar on top and the navigation
/// inset, 48 dp for buttons and 16 dp for the gesture handle. A phone moves
/// the buttons to the side in landscape; a tablet keeps them at the bottom.
FakeViewPadding _systemBars(Size size, double ratio, {required bool buttons}) {
  final landscape = size.width > size.height;
  final tablet = size.shortestSide / ratio >= 600;
  final inset = (buttons ? 48 : 16) * ratio;
  final status = 24 * ratio;
  return landscape && !tablet && buttons
      ? FakeViewPadding(top: status, right: inset)
      : FakeViewPadding(top: status, bottom: inset);
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required int tab,
  bool dark = false,
  double scale = 1,
  Size size = _landscape,
  double pixelRatio = _pixelRatio,
  FakeViewPadding? padding,
  bool collapsed = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.padding =
      padding ??
      (size.width > size.height
          ? const FakeViewPadding(left: 79, top: 66)
          : const FakeViewPadding(top: 66));
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/app?tab=$tab',
    routes: <RouteBase>[
      GoRoute(
        path: '/app',
        builder: (context, state) => AppShell(
          initialIndex: int.parse(state.uri.queryParameters['tab'] ?? '0'),
        ),
      ),
      GoRoute(
        path: '/mushaf',
        builder: (context, state) => const Scaffold(body: Text('MUSHAF')),
      ),
      GoRoute(
        path: '/reader/:surah',
        builder: (context, state) => const Scaffold(body: Text('READER')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final database = _Database();
  final account = accountScopeKey(database.accountScope.current!);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            fallbackDownloadUrl: 'https://iqro.forum',
            environment: 'production',
          ),
        ),
        sessionProvider.overrideWith((ref) => _SignedOut()),
        localDatabaseProvider.overrideWithValue(database),
        activeAccountScopeKeyProvider.overrideWithValue(account),
        appPreferencesProvider.overrideWith((ref) => _Preferences()),
        audioControllerProvider.overrideWith((ref) => _IdleAudio()),
        miniPlayerCollapsedProvider.overrideWith((ref) => collapsed),
        recitersProvider.overrideWith((ref) async => []),
        planProvider.overrideWith((ref) => _Plan()),
        memorizationProvider.overrideWith((ref) => _Memorization()),
        duaEntriesProvider.overrideWith((ref) async => []),
        prayerScheduleProvider.overrideWith((ref, key) async => null),
        prayerMethodsProvider.overrideWith((ref) async => []),
        calendarClockProvider.overrideWith(
          (ref) => Stream.value(DateTime(2026, 10, 17, 12)),
        ),
        calendarCatalogProvider.overrideWith((ref) => const Stream.empty()),
        readingPositionProvider.overrideWith(
          (ref, key) async => const ReadingPosition(
            edition: 'madani',
            entityId: 'position',
            surah: 83,
            ayah: 12,
            page: 588,
            revision: 1,
          ),
        ),
        quranCatalogProvider.overrideWith(
          (ref) async => QuranCatalog(
            surahs: [
              for (var number = 1; number <= 114; number++)
                Surah(
                  id: 'surah-$number',
                  number: number,
                  nameAr: 'سورة',
                  nameEn: 'Surah $number',
                  nameRu: switch (number) {
                    1 => 'Аль-Фатиха',
                    83 => 'Аль-Мутаффифин',
                    114 => 'Ан-Нас',
                    _ => 'Сура $number',
                  },
                  ayahCount: 7,
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
        theme: IqroTheme.light(),
        darkTheme: IqroTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(HomeScreen), tab == 0 ? findsOneWidget : findsNothing);
}

class _SignedOut extends StateNotifier<AsyncValue<AuthSession?>>
    implements SessionController {
  _SignedOut() : super(const AsyncData(null));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
