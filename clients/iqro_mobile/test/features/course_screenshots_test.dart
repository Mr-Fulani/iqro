// Screenshots of the courses for the pull request, on the shared examples
// of docs/courses (and docs/tajweed and docs/salah for the media of a
// tajweed and a prayer lesson):
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
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/courses/course_catalog_screen.dart';
import 'package:iqro_mobile/features/courses/course_home_screen.dart';
import 'package:iqro_mobile/features/courses/course_lesson_screen.dart';
import 'package:iqro_mobile/features/courses/course_notes_view.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/courses/lesson_video_player.dart';
import 'package:iqro_mobile/features/salah/salah_lesson_screen.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_models.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_progress.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_repository.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_lesson_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'course_test_data.dart';
import 'lesson_media_test_data.dart';
import 'lesson_video_test_data.dart';
import 'salah_models_test.dart' show salahFixture;
import 'tajweed_course_test_data.dart';

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
  Map<String, Object?>? tajweed,
  Map<String, Object?>? salah,
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
      GoRoute(
        path: '/tajweed/lesson/:lesson',
        builder: (context, state) =>
            TajweedLessonScreen(lessonSlug: state.pathParameters['lesson']!),
      ),
      GoRoute(
        path: '/salah/lesson/:lesson',
        builder: (context, state) =>
            SalahLessonScreen(lessonSlug: state.pathParameters['lesson']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  final pictures = (await tester.runAsync(_pictures))!;
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
          // The examples' slides and banner, drawn here.
          ...lessonMediaOverrides(
            images: (url) => MemoryImage(
              pictures.entries
                  .firstWhere((entry) => url.contains(entry.key))
                  .value,
            ),
          ),
          lessonVideoControllerProvider.overrideWithValue(
            (videos ?? FakeVideoFactory()).call,
          ),
          lessonVideoWakeProvider.overrideWithValue((_) async {}),
          audioControllerProvider.overrideWith(
            (ref) => RecordingAudioController(),
          ),
          // A tajweed lesson on its first step; the examples never arrive.
          tajweedCourseProvider.overrideWith(
            (ref, slug) async => TajweedCourseDocument.fromJson(
              tajweed ?? tajweedCourseDocumentWithMediaJson(),
            ),
          ),
          tajweedCourseRepositoryProvider.overrideWithValue(
            _PendingTajweedExamples(),
          ),
          tajweedCourseProgressStoreProvider.overrideWithValue(
            TajweedCourseProgressStore(database),
          ),
          tajweedProgressSyncProvider.overrideWithValue(_NoTajweedSync()),
          tajweedCourseRecitationProvider.overrideWithValue(() async => null),
          audioRepositoryProvider.overrideWithValue(_NoAudioRepository()),
          // A prayer lesson on its first step, without the offline pictures.
          salahCourseProvider.overrideWith(
            (ref, slug) async =>
                SalahCourseDocument.fromJson(salah ?? salahFixture()),
          ),
          salahOfflineImagesProvider.overrideWith(
            (ref, slug) async => const <String, String>{},
          ),
          // The next step's picture is fetched ahead; no disk cache in tests.
          salahImageProvider.overrideWithValue(
            (_) => MemoryImage(pictures['2222222222']!),
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

/// Stand-ins for the pictures of the examples, by the start of their name.
Future<Map<String, Uint8List>> _pictures() async {
  Future<Uint8List> draw(Size size, void Function(Canvas canvas) paint) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    final image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void text(
    Canvas canvas,
    String value,
    Offset center,
    double width, {
    double size = 30,
    Color color = const Color(0xFF073E34),
    String family = 'Roboto',
    FontWeight weight = FontWeight.w700,
    TextDirection direction = TextDirection.ltr,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              textDirection: direction,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: size,
              fontFamily: family,
              fontWeight: weight,
            ),
          )
          ..addText(value);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(
      paragraph,
      center - Offset(width / 2, paragraph.height / 2),
    );
  }

  const green = Color(0xFF0B5D4A);
  const gold = Color(0xFFD5A34C);
  final scheme = await draw(const Size(800, 600), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 600),
      Paint()..color = const Color(0xFFF7F1E3),
    );
    text(canvas, 'Когда делать намерение', const Offset(400, 70), 700);
    const stops = <(String, String, Color)>[
      ('Ночь', 'после магриба', Color(0xFF1F3A5F)),
      ('Сухур', 'до рассвета', green),
      ('Рассвет', 'начало поста', gold),
    ];
    for (final (index, (title, note, color)) in stops.indexed) {
      final left = 60.0 + index * 240;
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 180, 200, 170),
        const Radius.circular(24),
      );
      canvas.drawRRect(box, Paint()..color = color);
      text(canvas, title, Offset(left + 100, 245), 190, color: Colors.white);
      text(
        canvas,
        note,
        Offset(left + 100, 295),
        190,
        size: 20,
        weight: FontWeight.w400,
        color: Colors.white,
      );
      if (index < 2) {
        canvas.drawPath(
          Path()
            ..moveTo(left + 207, 250)
            ..lineTo(left + 233, 265)
            ..lineTo(left + 207, 280)
            ..close(),
          Paint()..color = const Color(0xFF6B7F78),
        );
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(140, 420, 520, 110),
        const Radius.circular(20),
      ),
      Paint()..color = const Color(0xFFE4EFE9),
    );
    text(
      canvas,
      'Намерение — сердцем, до рассвета',
      const Offset(400, 475),
      500,
      size: 26,
    );
  });
  final niyya = await draw(const Size(800, 450), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 450),
      Paint()..color = const Color(0xFF073E34),
    );
    canvas.drawRect(
      const Rect.fromLTWH(24, 24, 752, 402),
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    text(
      canvas,
      'نَوَيْتُ صَوْمَ غَدٍ',
      const Offset(400, 225),
      700,
      size: 92,
      color: Colors.white,
      family: IqroTheme.arabicFontFamily,
      weight: FontWeight.w400,
      direction: TextDirection.rtl,
    );
  });
  final banner = await draw(const Size(800, 450), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 450),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, 450),
          const <Color>[
            Color(0xFF1B2A4A),
            Color(0xFFB4574A),
            Color(0xFFF2B36B),
          ],
          const <double>[0, .62, 1],
        ),
    );
    final dark = Paint()..color = const Color(0xFF15161F);
    canvas
      ..drawCircle(
        const Offset(590, 120),
        54,
        Paint()..color = const Color(0xFFF7E3B0),
      )
      ..drawCircle(
        const Offset(615, 104),
        50,
        Paint()..color = const Color(0xFF263459),
      )
      ..drawRect(const Rect.fromLTWH(0, 380, 800, 70), dark)
      ..drawRect(const Rect.fromLTWH(250, 170, 44, 220), dark)
      ..drawRect(const Rect.fromLTWH(238, 215, 68, 12), dark)
      ..drawPath(
        Path()
          ..moveTo(250, 170)
          ..quadraticBezierTo(272, 120, 294, 170)
          ..close(),
        dark,
      )
      ..drawRect(const Rect.fromLTWH(320, 300, 280, 90), dark)
      ..drawCircle(const Offset(460, 300), 70, dark);
  });
  // The slides of the tajweed example's «izhar».
  final letters = await draw(const Size(800, 450), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 450),
      Paint()..color = const Color(0xFFF7F1E3),
    );
    text(canvas, 'Гортанные буквы изхара', const Offset(400, 62), 700);
    // From the depth of the throat to its start, right to left.
    const groups = <(String, String)>[
      ('ء ه', 'глубина'),
      ('ع ح', 'середина'),
      ('غ خ', 'начало'),
    ];
    for (final (index, (pair, note)) in groups.indexed) {
      final left = 540.0 - index * 240;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 130, 200, 210),
          const Radius.circular(24),
        ),
        Paint()..color = const Color(0xFF7B5EA7),
      );
      text(
        canvas,
        pair,
        Offset(left + 100, 200),
        190,
        size: 60,
        color: Colors.white,
        family: IqroTheme.arabicFontFamily,
        weight: FontWeight.w400,
        direction: TextDirection.rtl,
      );
      text(
        canvas,
        note,
        Offset(left + 100, 310),
        190,
        size: 22,
        weight: FontWeight.w400,
        color: Colors.white,
      );
    }
    text(
      canvas,
      'нун звучит ясно, без гунны',
      const Offset(400, 395),
      600,
      size: 24,
      weight: FontWeight.w400,
    );
  });
  final word = await draw(const Size(800, 450), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 450),
      Paint()..color = const Color(0xFF073E34),
    );
    canvas.drawRect(
      const Rect.fromLTWH(24, 24, 752, 402),
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    text(
      canvas,
      'مِنْ خَوْفٍ',
      const Offset(400, 225),
      700,
      size: 104,
      color: Colors.white,
      family: IqroTheme.arabicFontFamily,
      weight: FontWeight.w400,
      direction: TextDirection.rtl,
    );
  });
  // The slide of the prayer example's «wudu»: the order of the washing.
  final wudu = await draw(const Size(800, 450), (canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 450),
      Paint()..color = const Color(0xFFF7F1E3),
    );
    text(canvas, 'Обязательное в вуду', const Offset(400, 62), 700);
    const parts = <String>['Лицо', 'Руки', 'Голова', 'Ноги'];
    for (final (index, part) in parts.indexed) {
      final left = 40.0 + index * 185;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 140, 165, 170),
          const Radius.circular(24),
        ),
        Paint()..color = index.isEven ? green : const Color(0xFF1F6F8B),
      );
      text(
        canvas,
        '${index + 1}',
        Offset(left + 82, 195),
        150,
        size: 48,
        color: Colors.white,
      );
      text(
        canvas,
        part,
        Offset(left + 82, 265),
        150,
        size: 26,
        weight: FontWeight.w400,
        color: Colors.white,
      );
    }
    text(
      canvas,
      'по порядку и без долгих перерывов',
      const Offset(400, 380),
      700,
      size: 26,
      weight: FontWeight.w400,
    );
  });
  return {
    '9999999999': wudu,
    '1111111111': scheme,
    '3333333333': niyya,
    '2222222222': banner,
    '6666666666': letters,
    '7777777777': word,
  };
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

  testWidgets('lesson media: a video, then slides', (tester) async {
    await _pump(tester, location: '/courses/ramadan/namerenie');
    await _capture(tester, 'app-media-lesson-ru');
  }, skip: _directory.isEmpty);

  testWidgets('lesson slides in the Arabic interface', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      locale: 'ar',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await tester.tap(find.byKey(const ValueKey('lesson-media-slide-next')));
    await _capture(tester, 'app-media-slides-ar');
  }, skip: _directory.isEmpty);

  testWidgets('lesson banner', (tester) async {
    await _pump(tester, location: '/courses/ramadan/smysl-posta');
    await _capture(tester, 'app-media-banner-ru');
  }, skip: _directory.isEmpty);

  testWidgets('tajweed lesson media: a video, then slides', (tester) async {
    await _pump(tester, location: '/tajweed/lesson/izhar');
    await _capture(tester, 'app-tajweed-media-ru');
  }, skip: _directory.isEmpty);

  testWidgets('tajweed lesson media in the Arabic interface', (tester) async {
    final document = tajweedCourseDocumentWithMediaJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      locale: 'ar',
      tajweed: document,
    );
    await tester.tap(find.byKey(const ValueKey('lesson-media-slide-next')));
    await _capture(tester, 'app-tajweed-media-ar');
  }, skip: _directory.isEmpty);

  testWidgets(
    'notes with «?» and «!» after words and an ayah link',
    (tester) async {
      await _pump(tester, location: '/courses/ramadan/namerenie');
      await tester.scrollUntilVisible(
        find.byType(NoteMarkButton).last,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 260));
      await _capture(tester, 'app-notes-marks-ru');
      await tester.tap(find.byType(NoteMarkButton).first);
      await _capture(tester, 'app-notes-sheet-ru');
    },
    skip: _directory.isEmpty,
  );

  testWidgets('a note in the Arabic interface', (tester) async {
    final document = courseDocumentJson();
    (document['course']! as Map)['language'] = 'ar';
    await _pump(
      tester,
      location: '/courses/ramadan/namerenie',
      locale: 'ar',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await tester.scrollUntilVisible(
      find.byType(NoteMarkButton).last,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(NoteMarkButton).last);
    await _capture(tester, 'app-notes-sheet-ar');
  }, skip: _directory.isEmpty);

  testWidgets('tajweed explanation with a note', (tester) async {
    await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      tajweed: tajweedCourseExampleDocumentJson(),
    );
    await tester.scrollUntilVisible(
      find.byType(NoteMarkButton).first,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await _capture(tester, 'app-tajweed-notes-ru');
  }, skip: _directory.isEmpty);

  testWidgets('prayer lesson media on its first step', (tester) async {
    await _pump(tester, location: '/salah/lesson/wudu');
    await _capture(tester, 'app-salah-media-ru');
  }, skip: _directory.isEmpty);

  testWidgets(
    'prayer lesson media further down: the slide and the banner',
    (tester) async {
      await _pump(tester, location: '/salah/lesson/wudu');
      await tester.drag(
        find.byKey(const ValueKey('lesson-media-slides')),
        const Offset(0, -560),
      );
      await _capture(tester, 'app-salah-media-banner-ru');
    },
    skip: _directory.isEmpty,
  );

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

class _PendingTajweedExamples implements TajweedCourseRepository {
  @override
  Future<TajweedExamplesPage> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) => Completer<TajweedExamplesPage>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTajweedSync implements TajweedProgressSync {
  @override
  Future<TajweedCourseProgress?> sync(String course) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAudioRepository implements AudioRepository {
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
