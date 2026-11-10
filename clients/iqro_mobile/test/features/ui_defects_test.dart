import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/favorites/favorites_screen.dart';
import 'package:iqro_mobile/features/notes/notes_screen.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_calendar_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/settings/settings_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Defects seen on a Redmi (1080 × 2340, 392 dp wide) on 09.11.2026.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting();
  });

  void phone(WidgetTester tester, {double width = 1080}) {
    tester.view.physicalSize = Size(width, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {String locale = 'ru', List<Override>? overrides}) =>
      ProviderScope(
        overrides: overrides ?? const <Override>[],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: IqroTheme.light(),
          home: home,
        ),
      );

  for (final locale in <String>['ru', 'en', 'ar', 'tr']) {
    testWidgets('the month calendar shows all six times on a phone ($locale)', (
      tester,
    ) async {
      // A narrow phone: 360 dp.
      phone(tester, width: 990);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: IqroPage(
              child: PrayerCalendarDay(schedule: _schedule, locale: locale),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget); // the page
      final card = tester.getRect(find.byType(PrayerCalendarDay));
      for (final code in _codes) {
        final column = find.byKey(ValueKey<String>('prayer-calendar-$code'));
        final rect = tester.getRect(column);
        expect(card.contains(rect.topLeft), isTrue, reason: code);
        expect(card.contains(rect.bottomRight), isTrue, reason: code);
      }
      expect(find.text('18:40'), findsOneWidget);
      expect(find.text('20:05'), findsOneWidget);
    });
  }

  testWidgets('no notes yet is a compact card, not a block the screen tall', (
    tester,
  ) async {
    phone(tester);
    const AccountScopeKey key = (userId: 'guest', epoch: 1);
    await tester.pumpWidget(
      app(
        const NotesScreen(),
        overrides: <Override>[
          activeAccountScopeKeyProvider.overrideWithValue(key),
          ayahAnnotationsProvider(key).overrideWith((ref) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Пока нет заметок. Добавьте заметку к аяту в Мусхафе.'),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(IqroStatusBanner)).height, lessThan(200));
  });

  group('settings', () {
    Future<void> pump(
      WidgetTester tester,
      String locale, {
      double width = 1080,
    }) async {
      phone(tester, width: width);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = PreferencesStore(await SharedPreferences.getInstance());
      final sql = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
      ))!;
      addTearDown(() => tester.runAsync(sql.close));
      await tester.pumpWidget(
        app(
          const SettingsScreen(),
          locale: locale,
          overrides: <Override>[
            preferencesStoreProvider.overrideWithValue(store),
            appPreferencesProvider.overrideWith((ref) => _Preferences()),
            appPreferencesProvider.overrideWith((ref) => _Preferences()),
            planProvider.overrideWith((ref) => _Plan()),
            localDatabaseProvider.overrideWithValue(
              LocalDatabase.forTesting(sql),
            ),
            analyticsBackendProvider.overrideWithValue(_Backend()),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final locale in <String>['ru', 'en', 'ar', 'tr']) {
      testWidgets('every theme label stays on one line ($locale)', (
        tester,
      ) async {
        await pump(tester, locale);
        final theme = find.byKey(const Key('settings-theme'));
        for (final text in tester.widgetList<Text>(
          find.descendant(of: theme, matching: find.byType(Text)),
        )) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byWidget(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: text.data);
          // Scaled only as the last resort, never below readable.
          expect(paragraph.size.height, greaterThan(14), reason: text.data);
        }
        // On a phone «Системная» has no room beside an icon: the icons go.
        if (locale == 'ru') {
          expect(
            find.descendant(of: theme, matching: find.byType(Icon)),
            findsNothing,
          );
        }
      });
    }

    testWidgets('a wide screen keeps the theme icons', (tester) async {
      await pump(tester, 'en', width: 2200);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-theme')),
          matching: find.byType(Icon),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('the switch rows share the other rows\' title style', (
      tester,
    ) async {
      await pump(tester, 'ru');
      TextStyle? style(String text) =>
          tester.widget<Text>(find.text(text)).style;
      final row = style('Пройти знакомство заново');
      expect(row, isNotNull);
      expect(style('Вибрация при перелистывании'), row);
      expect(style('Статистика использования'), row);

      await tester.ensureVisible(find.text('Вибрация при перелистывании'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вибрация при перелистывании'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(container.read(appPreferencesProvider).readerHaptics, isFalse);
    });
  });

  testWidgets('favorites show an ayah added in the reader on the way back', (
    tester,
  ) async {
    phone(tester);
    // The screen only checks the account; the queries go to the fakes.
    final sql = (await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    ))!;
    addTearDown(() => tester.runAsync(sql.close));
    final accountScope = AccountScope.forTesting('guest');
    final database = LocalDatabase.forTesting(sql, accountScope: accountScope);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = PreferencesStore(await SharedPreferences.getInstance());
    final bookmarks = <Map<String, Object?>>[
      <String, Object?>{'surah': 2, 'ayah': 255},
    ];
    final router = GoRouter(
      initialLocation: '/favorites',
      routes: <RouteBase>[
        GoRoute(
          path: '/favorites',
          builder: (context, state) => const FavoritesScreen(),
        ),
        GoRoute(
          path: '/reader/:surah',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () {
                bookmarks.add(<String, Object?>{'surah': 2, 'ayah': 256});
                context.pop();
              },
              child: const Text('bookmark and back'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(database),
          preferencesStoreProvider.overrideWithValue(store),
          appPreferencesProvider.overrideWith((ref) => _Preferences()),
          activeAccountScopeKeyProvider.overrideWithValue(
            accountScopeKey(accountScope.current!),
          ),
          quranRepositoryProvider.overrideWithValue(_Quran(bookmarks)),
          duaRepositoryProvider.overrideWithValue(_Dua()),
          quranCatalogProvider.overrideWith((ref) async => throw 'offline'),
        ],
        child: MaterialApp.router(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: IqroTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сура 2 · Аят 255'), findsOneWidget);
    expect(find.text('Сура 2 · Аят 256'), findsNothing);

    await tester.tap(find.text('Сура 2 · Аят 255'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bookmark and back'));
    await tester.pumpAndSettle();

    expect(find.text('Сура 2 · Аят 256'), findsOneWidget);
  });
}

const _codes = <String>['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

final _schedule = PrayerSchedule(
  date: DateTime(2026, 11, 9),
  timezone: 'Europe/Moscow',
  times: <String, DateTime>{
    'fajr': DateTime(2026, 11, 9, 6, 11),
    'sunrise': DateTime(2026, 11, 9, 7, 45),
    'dhuhr': DateTime(2026, 11, 9, 12, 50),
    'asr': DateTime(2026, 11, 9, 15, 30),
    'maghrib': DateTime(2026, 11, 9, 18, 40),
    'isha': DateTime(2026, 11, 9, 20, 5),
  },
  timesUtc: const <String, DateTime>{},
  methodName: 'mwl',
  warnings: const <String>[],
);

class _Backend implements AnalyticsBackend {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {}
}

class _Quran implements QuranRepository {
  _Quran(this.items);

  final List<Map<String, Object?>> items;

  @override
  Future<List<Map<String, Object?>>> bookmarks({
    AccountScopeSnapshot? accountScope,
  }) async => List<Map<String, Object?>>.of(items);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Dua implements DuaRepository {
  @override
  Future<List<DuaEntry>> favorites({
    String? locale,
    AccountScopeSnapshot? accountScope,
  }) async => const <DuaEntry>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences() : super(const AppPreferences.defaults());

  @override
  Future<void> setReaderHaptics(bool value) async =>
      state = state.copyWith(readerHaptics: value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plan extends StateNotifier<AsyncValue<DailyPlan>>
    implements PlanController {
  _Plan() : super(const AsyncLoading());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
