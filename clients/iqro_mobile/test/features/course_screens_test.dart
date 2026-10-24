import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/courses/course_catalog_screen.dart';
import 'package:iqro_mobile/features/courses/course_home_screen.dart';
import 'package:iqro_mobile/features/courses/course_lesson_screen.dart';
import 'package:iqro_mobile/features/more/more_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'course_test_data.dart';
import 'lesson_media_test_data.dart';

void main() {
  testWidgets('«More» opens the courses, which hold prayer and tajweed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: MoreToolsGrid()),
          ),
        ),
        GoRoute(
          path: '/courses',
          builder: (_, _) => const Scaffold(body: Text('courses-opened')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
      ),
    );
    // Both courses open from the catalog, not from tiles of their own.
    expect(find.text('Обучение намазу'), findsNothing);
    expect(find.text('Таджвид'), findsNothing);
    final tile = find.byKey(const ValueKey('more-courses'));
    expect(
      tester.getSemantics(tile),
      isSemantics(hint: 'Темы с конспектами', hasTapAction: true),
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('courses-opened'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('without the section on the server: prayer, tajweed, a note', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      remote: FakeCourseGateway(list: notFoundError),
    );
    expect(find.byKey(const ValueKey('courses-empty')), findsOneWidget);
    expect(find.text('Новые курсы появятся здесь.'), findsOneWidget);
    expect(find.byKey(const ValueKey('courses-error')), findsNothing);
    expect(find.byKey(const ValueKey('courses-offline')), findsNothing);
    expect(find.byKey(const ValueKey('courses-resume')), findsNothing);
    final salah = tester.getRect(find.byKey(const ValueKey('courses-salah')));
    final tajweed = tester.getRect(
      find.byKey(const ValueKey('courses-tajweed')),
    );
    final empty = tester.getRect(find.byKey(const ValueKey('courses-empty')));
    expect(salah.top, lessThan(tajweed.top));
    expect(tajweed.top, lessThan(empty.top));
    await tester.tap(find.byKey(const ValueKey('courses-tajweed')));
    await _settle(tester);
    expect(find.text('tajweed-opened'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the API courses come after prayer and tajweed', (tester) async {
    final harness = await _pump(tester);
    final tajweed = tester.getRect(
      find.byKey(const ValueKey('courses-tajweed')),
    );
    final ramadan = tester.getRect(
      find.byKey(const ValueKey('course-ramadan')),
    );
    expect(tajweed.top, lessThan(ramadan.top));
    expect(find.text('Рамадан'), findsOneWidget);
    expect(find.text('3 темы · 30 мин'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-status-ramadan')), findsNothing);
    harness.dispose();
  });

  testWidgets('offline without saved courses: a banner and a note', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      remote: FakeCourseGateway(list: offlineError),
    );
    expect(find.byKey(const ValueKey('courses-offline')), findsOneWidget);
    expect(
      find.text('Нет интернета — показаны сохранённые курсы'),
      findsOneWidget,
    );
    expect(find.textContaining('Сохранённых курсов пока нет'), findsOneWidget);
    expect(find.byKey(const ValueKey('courses-salah')), findsOneWidget);
    harness.dispose();
  });

  testWidgets('a course is studied lesson by lesson and continues', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('course-ramadan')));
    await _settle(tester);
    expect(find.byType(CourseHomeScreen), findsOneWidget);
    expect(find.text('Пройдено тем: 0 из 3'), findsOneWidget);
    expect(find.text('[автор и источники — после проверки]'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('course-continue')));
    await _settle(tester);

    expect(find.byType(CourseLessonScreen), findsOneWidget);
    expect(find.text('Смысл поста'), findsOneWidget);
    expect(find.text('Рамадан · тема 1 из 3'), findsOneWidget);
    expect(find.text('Конспект'), findsOneWidget);
    // Sources are folded until asked for.
    expect(find.text('[источник 1 — после проверки]'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('course-lesson-sources')),
    );
    await tester.tap(find.text('Источники'));
    await _settle(tester);
    expect(find.text('[источник 1 — после проверки]'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('course-lesson-done')));
    await _settle(tester);
    expect(find.text('Тема пройдена'), findsOneWidget);
    final stored = await tester.runAsync(
      () => harness.database.readState('courses.progress.ramadan'),
    );
    final entry = (stored!['lessons']! as Map)['smysl-posta']! as Map;
    expect(entry['status'], 'completed');
    expect(entry['step_slug'], '');
    expect(entry['content_version'], '1');

    await tester.tap(find.byKey(const ValueKey('course-lesson-next')));
    await _settle(tester);
    expect(find.text('Намерение (ният)'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-lesson-done')), findsOneWidget);

    // Back to the catalog: «Continue» opens the first lesson not studied.
    harness.router.go('/courses');
    await _settle(tester);
    expect(find.byKey(const ValueKey('courses-resume')), findsOneWidget);
    expect(find.text('Рамадан · Намерение (ният)'), findsOneWidget);
    expect(find.text('Начат · 1/3'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('courses-resume')),
        matching: find.byType(FilledButton),
      ),
    );
    await _settle(tester);
    expect(find.text('Рамадан · тема 2 из 3'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the mark can be taken back; the last lesson leads to all', (
    tester,
  ) async {
    final harness = await _pump(tester, location: '/courses/ramadan/taraviikh');
    expect(find.text('Рамадан · тема 3 из 3'), findsOneWidget);
    // Without sources the section is not shown.
    expect(find.byKey(const ValueKey('course-lesson-sources')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('course-lesson-done')));
    await _settle(tester);
    expect(find.text('Все темы'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('course-lesson-unmark')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('course-lesson-done')), findsOneWidget);
    final stored = await tester.runAsync(
      () => harness.database.readState('courses.progress.ramadan'),
    );
    expect(stored!['lessons'], {
      'taraviikh': containsPair('status', 'in_progress'),
    });
    harness.dispose();
  });

  testWidgets('a newer document asks to update the app', (tester) async {
    final harness = await _pump(
      tester,
      location: '/courses/ramadan',
      remote: FakeCourseGateway(
        documents: {'1': courseDocumentJson()..['schema_version'] = 2},
      ),
    );
    expect(find.text('Обновите приложение'), findsOneWidget);
    expect(
      find.text('Этот курс сделан для новой версии IQRO.'),
      findsOneWidget,
    );
    harness.dispose();
  });

  testWidgets('a hidden course and a missing lesson say so', (tester) async {
    var harness = await _pump(tester, location: '/courses/fasting');
    expect(find.text('Курс сейчас недоступен'), findsOneWidget);
    harness.dispose();
    harness = await _pump(tester, location: '/courses/ramadan/nothing');
    expect(find.text('Такой темы нет в курсе'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('an Arabic course reads right to left', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    final harness = await _pump(
      tester,
      locale: 'ar',
      location: '/courses/ramadan/taraviikh',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    expect(tester.takeException(), isNull);
    final done = tester.getRect(
      find.byKey(const ValueKey('course-lesson-done')),
    );
    final back = tester.getRect(
      find.byKey(const ValueKey('course-lesson-previous')),
    );
    // «Back» is at the start edge, which is on the right.
    expect(back.left, greaterThan(done.left));
    expect(harness.remote.listRequests, ['ar']);
    harness.dispose();
  });
}

typedef _Harness = ({
  GoRouter router,
  LocalDatabase database,
  FakeCourseGateway remote,
  void Function() dispose,
});

Future<_Harness> _pump(
  WidgetTester tester, {
  String location = '/courses',
  String locale = 'ru',
  FakeCourseGateway? remote,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final gateway = remote ?? FakeCourseGateway();
  final (Database sql, LocalDatabase database) = (await tester.runAsync(
    openCourseTestDatabase,
  ))!;
  final router = GoRouter(
    initialLocation: '/courses',
    routes: <RouteBase>[
      GoRoute(
        path: '/courses',
        builder: (context, state) => const CourseCatalogScreen(),
      ),
      GoRoute(
        path: '/courses/:course',
        builder: (context, state) =>
            CourseHomeScreen(courseSlug: state.pathParameters['course']!),
      ),
      GoRoute(
        path: '/courses/:course/:lesson',
        builder: (context, state) => CourseLessonScreen(
          courseSlug: state.pathParameters['course']!,
          lessonSlug: state.pathParameters['lesson']!,
        ),
      ),
      GoRoute(
        path: '/salah',
        builder: (_, _) => const Scaffold(body: Text('salah-opened')),
      ),
      GoRoute(
        path: '/tajweed',
        builder: (_, _) => const Scaffold(body: Text('tajweed-opened')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        courseGatewayProvider.overrideWithValue(gateway),
        localDatabaseProvider.overrideWithValue(database),
        activeAccountScopeKeyProvider.overrideWithValue((
          userId: 'test-owner',
          epoch: 1,
        )),
        appPreferencesProvider.overrideWith((ref) => _Preferences(locale)),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            fallbackDownloadUrl: 'https://iqro.forum',
            environment: 'production',
          ),
        ),
        // Covers fall back to their placeholder.
        courseImageProvider.overrideWithValue((_) => MemoryImage(Uint8List(0))),
        ...lessonMediaOverrides(),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
      ),
    ),
  );
  await _settle(tester);
  if (location != '/courses') {
    unawaited(router.push(location));
    await _settle(tester);
  }
  return (
    router: router,
    database: database,
    remote: gateway,
    dispose: () {
      router.dispose();
      unawaited(sql.close());
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences(String locale)
    : super(const AppPreferences.defaults().copyWith(locale: locale));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
