import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/courses/lesson_video_fullscreen.dart';
import 'package:iqro_mobile/features/courses/lesson_video_player.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'course_test_data.dart';
import 'lesson_video_test_data.dart';

const _lesson = '/courses/ramadan/namerenie';
const _facade = ValueKey('lesson-video-facade');

void main() {
  test('the video of the example is read as the contract has it', () {
    final document = CourseDocument.fromJson(courseDocumentJson());
    expect(document.lesson('smysl-posta')!.video, isNull);
    final video = document.lesson('namerenie')!.video!;
    expect(video.url, endsWith('/courses/videos/abcdef0123456789abcd.mp4'));
    expect(video.bytes, 113246208);
    expect(video.duration, const Duration(minutes: 9, seconds: 48));
    expect(video.spokenLanguage, 'ru');
    expect(video.poster.smallUrl, endsWith('-640.webp'));
  });

  testWidgets('the poster costs no traffic until it is tapped', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester, location: _lesson);
    expect(find.byKey(_facade), findsOneWidget);
    expect(find.text('9:48 · 108 МБ'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-video-resume')), findsNothing);
    // The document is in Russian and so is the video.
    expect(find.byKey(const ValueKey('lesson-video-language')), findsNothing);
    expect(
      tester.getSemantics(find.byKey(_facade)),
      isSemantics(
        label: 'Смотреть видео «Намерение (ният)», 9:48 · 108 МБ',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(harness.videos.made, isEmpty);
    // The notes are below the video.
    expect(
      tester.getRect(find.byKey(_facade)).bottom,
      lessThan(tester.getRect(find.text('Конспект')).top),
    );
    harness.dispose();
    semantics.dispose();
  });

  testWidgets('a video in another language says so', (tester) async {
    var harness = await _pump(
      tester,
      location: _lesson,
      remote: _withVideo((video) => video['spoken_language'] = 'ar'),
    );
    expect(find.text('Видео на арабском языке'), findsOneWidget);
    harness.dispose();

    // Named in the language of the interface.
    final document = _documentWithVideo((video) {});
    (document['course']! as Map)['language'] = 'en';
    harness = await _pump(
      tester,
      location: _lesson,
      locale: 'en',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    expect(find.text('Video in Russian'), findsOneWidget);
    expect(find.text('9:48 · 108 MB'), findsOneWidget);
    harness.dispose();

    // A video without speech has no language.
    harness = await _pump(
      tester,
      location: _lesson,
      remote: _withVideo((video) => video['spoken_language'] = ''),
    );
    expect(find.byKey(const ValueKey('lesson-video-language')), findsNothing);
    harness.dispose();
  });

  testWidgets(
    'playing pauses the audio, keeps the screen on, keeps the place',
    (tester) async {
      final harness = await _pump(tester, location: _lesson);
      await tester.tap(find.byKey(_facade));
      await _settle(tester);

      final video = harness.videos.last;
      expect(
        video.uri,
        Uri.parse(
          'https://media.iqro.forum/courses/videos/abcdef0123456789abcd.mp4',
        ),
      );
      expect(video.value.isPlaying, isTrue);
      expect(harness.audio.lessonVideoPauses, 1);
      expect(harness.wake, [true]);
      expect(find.byKey(const ValueKey('lesson-video-player')), findsOneWidget);

      // Every 5 seconds while it plays.
      video.playTo(const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      expect(await _position(tester, harness), 7000);

      // And on pause. The controls hid while it played; a tap brings them.
      expect(find.byKey(const ValueKey('lesson-video-controls')), findsNothing);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('lesson-video-player'))) +
            const Offset(20, 20),
      );
      await _settle(tester);
      video.playTo(const Duration(minutes: 4, seconds: 12));
      await tester.tap(find.byKey(const ValueKey('lesson-video-toggle')));
      await _settle(tester);
      expect(video.value.isPlaying, isFalse);
      expect(harness.wake, [true, false]);
      expect(await _position(tester, harness), 252000);

      // Playing again pauses other audio again.
      await tester.tap(find.byKey(const ValueKey('lesson-video-toggle')));
      await _settle(tester);
      expect(harness.audio.lessonVideoPauses, 2);

      // Watched to the end: the place is forgotten.
      video.finish();
      await _settle(tester);
      expect(await _position(tester, harness), isNull);
      expect(harness.wake, [true, false, true, false]);
      harness.dispose();
    },
  );

  testWidgets('the video continues from where it stopped', (tester) async {
    final harness = await _pump(
      tester,
      location: '/courses/ramadan',
      positions: {'namerenie': const Duration(minutes: 4, seconds: 12)},
      studied: {'smysl-posta'},
    );
    // The course continues with the video of the next lesson.
    expect(find.text('Продолжить с 4:12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('course-continue')));
    await _settle(tester);

    expect(find.text('Продолжить с 4:12'), findsOneWidget);
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    expect(harness.videos.last.seeks, [
      const Duration(minutes: 4, seconds: 12),
    ]);

    // The catalog shows the place too.
    harness.router.go('/courses');
    await _settle(tester);
    expect(find.text('Рамадан · Намерение (ният)'), findsOneWidget);
    expect(find.text('Видео с 4:12'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the video pauses when the app goes away or is left', (
    tester,
  ) async {
    final harness = await _pump(tester, location: _lesson);
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    final video = harness.videos.last;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester);
    expect(video.value.isPlaying, isFalse);
    expect(harness.wake, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    // Another screen over the lesson.
    await tester.tap(find.byKey(const ValueKey('lesson-video-toggle')));
    await _settle(tester);
    expect(video.value.isPlaying, isTrue);
    unawaited(harness.router.push('/elsewhere'));
    await _settle(tester);
    expect(video.value.isPlaying, isFalse);
    harness.router.pop();
    await _settle(tester);

    // Leaving the lesson lets the video go and keeps its place.
    await tester.tap(find.byKey(const ValueKey('lesson-video-toggle')));
    await _settle(tester);
    video.playTo(const Duration(seconds: 30));
    harness.router.pop();
    await _settle(tester);
    expect(video.disposed, isTrue);
    expect(harness.wake.last, isFalse);
    expect(await _position(tester, harness), 30000);
    harness.dispose();
  });

  testWidgets('a video that does not load leaves the notes and can retry', (
    tester,
  ) async {
    final videos = FakeVideoFactory(fails: true);
    final harness = await _pump(tester, location: _lesson, videos: videos);
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    expect(find.text('Видео не загрузилось'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-lesson-notes')), findsOneWidget);
    expect(videos.last.disposed, isTrue);

    videos.fails = false;
    await tester.tap(find.byKey(const ValueKey('lesson-video-retry')));
    await _settle(tester);
    expect(videos.made, hasLength(2));
    expect(videos.last.value.isPlaying, isTrue);

    // Breaking down while it plays: it continues from there on retry.
    videos.last.playTo(const Duration(seconds: 90));
    videos.last.breakDown();
    await _settle(tester);
    expect(find.text('Видео не загрузилось'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lesson-video-retry')));
    await _settle(tester);
    expect(videos.last.seeks, [const Duration(seconds: 90)]);
    harness.dispose();
  });

  testWidgets('a video from another host is not opened', (tester) async {
    final harness = await _pump(
      tester,
      location: _lesson,
      remote: _withVideo(
        (video) => video['url'] = 'https://example.com/courses/videos/a.mp4',
      ),
    );
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    expect(harness.videos.made, isEmpty);
    expect(find.text('Видео не загрузилось'), findsOneWidget);
    harness.dispose();
  });

  testWidgets('the controls run left to right and are large enough', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final document = _documentWithVideo((video) {});
    (document['course']! as Map)['language'] = 'ar';
    final harness = await _pump(
      tester,
      location: _lesson,
      locale: 'ar',
      remote: FakeCourseGateway(documents: {'1': document}),
    );
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    final video = harness.videos.last;
    // The Arabic interface names the Russian video.
    expect(find.text('الفيديو باللغة الروسية'), findsOneWidget);

    const keys = <String>[
      'lesson-video-back',
      'lesson-video-toggle',
      'lesson-video-forward',
      'lesson-video-fullscreen',
    ];
    for (final key in keys) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }
    final back = tester.getRect(
      find.byKey(const ValueKey('lesson-video-back')),
    );
    final forward = tester.getRect(
      find.byKey(const ValueKey('lesson-video-forward')),
    );
    expect(back.left, lessThan(forward.left));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('lesson-video-seek'))),
      isSemantics(label: 'موضع الفيديو', value: '0:00 / 9:48'),
    );

    video.playTo(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('lesson-video-back')));
    await _settle(tester);
    expect(video.seeks.last, Duration.zero);
    await tester.tap(find.byKey(const ValueKey('lesson-video-forward')));
    await _settle(tester);
    expect(video.seeks.last, const Duration(seconds: 10));
    expect(find.text('0:10 / 9:48'), findsOneWidget);
    harness.dispose();
    semantics.dispose();
  });

  testWidgets('the full screen turns sideways and gives everything back', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    List<String> made() => [
      for (final call in calls) '${call.method} ${call.arguments}',
    ];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations' ||
            call.method == 'SystemChrome.setEnabledSystemUIMode') {
          calls.add(call);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final harness = await _pump(tester, location: _lesson);
    await tester.tap(find.byKey(_facade));
    await _settle(tester);
    final video = harness.videos.last;

    await tester.tap(find.byKey(const ValueKey('lesson-video-fullscreen')));
    await _settle(tester);
    expect(find.byType(LessonVideoFullscreen), findsOneWidget);
    expect(made(), [
      'SystemChrome.setPreferredOrientations '
          '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
      'SystemChrome.setEnabledSystemUIMode SystemUiMode.immersiveSticky',
    ]);
    // The same video carries on: covering the lesson does not pause it.
    expect(video.value.isPlaying, isTrue);
    expect(harness.videos.made, hasLength(1));
    final exit = find.byKey(const ValueKey('lesson-video-fullscreen'));
    expect(
      find.descendant(
        of: exit,
        matching: find.byTooltip('Выйти из полноэкранного режима'),
      ),
      findsOneWidget,
    );

    calls.clear();
    await tester.tap(exit);
    await _settle(tester);
    expect(find.byType(LessonVideoFullscreen), findsNothing);
    expect(made(), [
      'SystemChrome.setPreferredOrientations []',
      'SystemChrome.setEnabledSystemUIMode SystemUiMode.edgeToEdge',
    ]);
    expect(video.value.isPlaying, isTrue);
    expect(video.disposed, isFalse);
    harness.dispose();
  });
}

Map<String, Object?> _documentWithVideo(
  void Function(Map<String, Object?> video) change,
) {
  final document = courseDocumentJson();
  final lesson = (document['lessons']! as List).cast<Map>().firstWhere(
    (lesson) => lesson['slug'] == 'namerenie',
  );
  change((lesson['video']! as Map).cast<String, Object?>());
  return document;
}

FakeCourseGateway _withVideo(
  void Function(Map<String, Object?> video) change,
) => FakeCourseGateway(documents: {'1': _documentWithVideo(change)});

Future<int?> _position(WidgetTester tester, _Harness harness) async {
  final stored = await tester.runAsync(
    () => harness.database.readState('courses.position.ramadan'),
  );
  final entry = stored?['namerenie'] as Map?;
  if (entry != null) expect(entry['updated_at'], isA<String>());
  return entry?['ms'] as int?;
}

typedef _Harness = ({
  GoRouter router,
  LocalDatabase database,
  FakeVideoFactory videos,
  RecordingAudioController audio,
  List<bool> wake,
  void Function() dispose,
});

Future<_Harness> _pump(
  WidgetTester tester, {
  required String location,
  String locale = 'ru',
  FakeCourseGateway? remote,
  FakeVideoFactory? videos,
  Map<String, Duration> positions = const {},
  Set<String> studied = const {},
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final factory = videos ?? FakeVideoFactory();
  final audio = RecordingAudioController();
  final wake = <bool>[];
  final (Database sql, LocalDatabase database) = (await tester.runAsync(
    openCourseTestDatabase,
  ))!;
  await tester.runAsync(() async {
    final store = CourseProgressStore(database);
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
        path: '/elsewhere',
        builder: (_, _) => const Scaffold(body: Text('elsewhere')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        courseGatewayProvider.overrideWithValue(remote ?? FakeCourseGateway()),
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
        courseImageProvider.overrideWithValue((_) => MemoryImage(Uint8List(0))),
        lessonVideoControllerProvider.overrideWithValue(factory.call),
        lessonVideoWakeProvider.overrideWithValue((on) async => wake.add(on)),
        audioControllerProvider.overrideWith((ref) => audio),
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
  unawaited(router.push(location));
  await _settle(tester);
  return (
    router: router,
    database: database,
    videos: factory,
    audio: audio,
    wake: wake,
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
