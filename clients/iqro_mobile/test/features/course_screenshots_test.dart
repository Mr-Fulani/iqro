// Screenshots of the courses for the pull request, on the shared examples
// of docs/courses:
//
//   flutter test test/features/course_screenshots_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Real fonts come from the Flutter SDK (Roboto, Material icons), the app
// (Amiri Quran) and macOS (Georgia for `serif`, SF Arabic for the Arabic
// interface).
// Without SCREENSHOT_DIR the test is skipped: CI checks behaviour elsewhere.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/courses/course_catalog_screen.dart';
import 'package:iqro_mobile/features/courses/course_home_screen.dart';
import 'package:iqro_mobile/features/courses/course_lesson_screen.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/courses/lesson_video_player.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'course_test_data.dart';
import 'lesson_video_test_data.dart';

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
  await family(IqroTheme.arabicFontFamily, [
    'assets/fonts/AmiriQuran-Regular.ttf',
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
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.copyWith(textStyle: label),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  FakeCourseGateway? remote,
  Set<String> studied = const {},
  Map<String, Duration> positions = const {},
  FakeVideoFactory? videos,
  String locale = 'ru',
  bool dark = false,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = _pixelRatio;
  tester.view.padding = const FakeViewPadding(top: 66);
  addTearDown(tester.view.reset);
  final (sql, database) = (await tester.runAsync(openCourseTestDatabase))!;
  addTearDown(() => tester.runAsync(sql.close));
  await tester.runAsync(() async {
    var minute = 0;
    final store = CourseProgressStore(
      database,
      clock: () => DateTime.utc(2026, 10, 24, 9, minute++),
    );
    for (final lesson in studied) {
      await store.markDone(
        course: 'ramadan',
        lesson: lesson,
        contentVersion: '1',
      );
    }
    for (final MapEntry(:key, :value) in positions.entries) {
      await store.savePosition(course: 'ramadan', lesson: key, position: value);
    }
  });
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
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          courseGatewayProvider.overrideWithValue(
            remote ?? FakeCourseGateway(),
          ),
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
          // The examples' covers are not real files: the placeholder shows.
          courseImageProvider.overrideWithValue(
            (_) => MemoryImage(Uint8List(0)),
          ),
          lessonVideoControllerProvider.overrideWithValue(
            (videos ?? FakeVideoFactory()).call,
          ),
          lessonVideoWakeProvider.overrideWithValue((_) async {}),
          audioControllerProvider.overrideWith(
            (ref) => RecordingAudioController(),
          ),
          courseFeedbackGatewayProvider.overrideWithValue(
            FakeCourseFeedbackGateway(),
          ),
          feedbackRepositoryProvider.overrideWithValue(
            FakeFeedbackRepository(),
          ),
          sessionProvider.overrideWith((ref) => _Guest()),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: _withArabic(IqroTheme.light()),
          darkTheme: _withArabic(IqroTheme.dark()),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          locale: Locale(locale),
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
  if (location != '/courses') {
    unawaited(router.push(location));
    await _settle(tester);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
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
    if (_directory.isNotEmpty) await _loadFonts();
  });

  testWidgets('catalog', (tester) async {
    await _pump(tester, location: '/courses', studied: {'smysl-posta'});
    await _capture(tester, 'app-courses-catalog-ru');
  }, skip: _directory.isEmpty);

  testWidgets('catalog before the server has courses', (tester) async {
    await _pump(
      tester,
      location: '/courses',
      remote: FakeCourseGateway(list: notFoundError),
    );
    await _capture(tester, 'app-courses-catalog-empty-ru');
  }, skip: _directory.isEmpty);

  testWidgets('catalog offline', (tester) async {
    await _pump(
      tester,
      location: '/courses',
      remote: FakeCourseGateway(list: offlineError),
    );
    await _capture(tester, 'app-courses-catalog-offline-ru');
  }, skip: _directory.isEmpty);

  testWidgets('course', (tester) async {
    await _pump(tester, location: '/courses/ramadan', studied: {'smysl-posta'});
    await _capture(tester, 'app-course-home-ru');
  }, skip: _directory.isEmpty);

  testWidgets('lesson', (tester) async {
    await _pump(tester, location: '/courses/ramadan/smysl-posta');
    await tester.tap(find.text('Источники'));
    await _capture(tester, 'app-course-lesson-ru');
  }, skip: _directory.isEmpty);

  testWidgets('studied lesson', (tester) async {
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      studied: {'smysl-posta', 'namerenie'},
    );
    await _capture(tester, 'app-course-lesson-done-ru');
  }, skip: _directory.isEmpty);

  testWidgets('lesson with a video', (tester) async {
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      positions: {'namerenie': const Duration(minutes: 4, seconds: 12)},
    );
    await _capture(tester, 'app-course-video-facade-ru');
  }, skip: _directory.isEmpty);

  testWidgets('catalog continuing a video', (tester) async {
    await _pump(
      tester,
      location: '/courses',
      studied: {'smysl-posta'},
      positions: {'namerenie': const Duration(minutes: 4, seconds: 12)},
    );
    await _capture(tester, 'app-courses-catalog-video-ru');
  }, skip: _directory.isEmpty);

  testWidgets('video playing', (tester) async {
    final videos = FakeVideoFactory();
    await _pump(tester, location: '/courses/ramadan/namerenie', videos: videos);
    await tester.tap(find.byKey(const ValueKey('lesson-video-facade')));
    await _settle(tester);
    await videos.last.pause();
    videos.last.playTo(const Duration(minutes: 4, seconds: 12));
    await _capture(tester, 'app-course-video-player-ru');
  }, skip: _directory.isEmpty);

  testWidgets('video full screen', (tester) async {
    final videos = FakeVideoFactory();
    await _pump(tester, location: '/courses/ramadan/namerenie', videos: videos);
    await tester.tap(find.byKey(const ValueKey('lesson-video-facade')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('lesson-video-fullscreen')));
    // The test view does not turn by itself.
    tester.view.physicalSize = _size.flipped;
    await _settle(tester);
    await videos.last.pause();
    videos.last.playTo(const Duration(minutes: 4, seconds: 12));
    await _capture(tester, 'app-course-video-fullscreen-ru');
  }, skip: _directory.isEmpty);

  testWidgets('video that did not load', (tester) async {
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      videos: FakeVideoFactory(fails: true),
    );
    await tester.tap(find.byKey(const ValueKey('lesson-video-facade')));
    await _capture(tester, 'app-course-video-failed-ru');
  }, skip: _directory.isEmpty);

  testWidgets('video in another language, Arabic interface', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      locale: 'ar',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await _capture(tester, 'app-course-video-language-ar');
  }, skip: _directory.isEmpty);

  testWidgets('lesson in the dark theme', (tester) async {
    await _pump(tester, location: '/courses/ramadan/taraviikh', dark: true);
    await _capture(tester, 'app-course-lesson-dark-ru');
  }, skip: _directory.isEmpty);

  testWidgets('lesson in the Arabic interface', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/courses/ramadan/smysl-posta',
      locale: 'ar',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await _capture(tester, 'app-course-lesson-ar');
  }, skip: _directory.isEmpty);

  testWidgets('rating the course after the last lesson', (tester) async {
    await _pump(
      tester,
      location: '/courses/ramadan/taraviikh',
      studied: {'smysl-posta', 'namerenie', 'taraviikh'},
    );
    final rating = find.byKey(const ValueKey('course-rating'));
    await tester.ensureVisible(rating);
    await tester.tap(find.byKey(const ValueKey('course-rating-star-4')));
    await tester.enterText(
      find.byKey(const ValueKey('course-rating-comment')),
      'Спасибо, всё понятно и по делу.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await _capture(tester, 'app-course-rating-ru');
    await tester.tap(find.byKey(const ValueKey('course-rating-send')));
    await _settle(tester);
    await _capture(tester, 'app-course-rating-thanks-ru');
  }, skip: _directory.isEmpty);

  testWidgets('a report sent', (tester) async {
    await _pump(tester, location: '/courses/ramadan/namerenie');
    await tester.ensureVisible(
      find.byKey(const ValueKey('course-lesson-report')),
    );
    await tester.tap(find.byKey(const ValueKey('course-lesson-report')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('course-report-message')),
      'В цитате аята 2:183 опечатка.',
    );
    await tester.tap(find.byKey(const ValueKey('course-report-send')));
    await _capture(tester, 'app-course-report-sent-ru');
  }, skip: _directory.isEmpty);

  testWidgets('lesson blocks in the Arabic interface', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/courses/ramadan/taraviikh',
      locale: 'ar',
      studied: {'taraviikh'},
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await _capture(tester, 'app-course-feedback-ar');
  }, skip: _directory.isEmpty);
}

class _Guest extends StateNotifier<AsyncValue<AuthSession?>>
    implements SessionController {
  _Guest() : super(const AsyncData(null));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences(String locale)
    : super(const AppPreferences.defaults().copyWith(locale: locale));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
