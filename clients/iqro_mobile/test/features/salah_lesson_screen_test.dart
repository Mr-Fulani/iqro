import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/salah/salah_3d.dart';
import 'package:iqro_mobile/features/salah/salah_home_screen.dart';
import 'package:iqro_mobile/features/salah/salah_lesson_screen.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';
import 'package:iqro_mobile/features/salah/salah_offline_repository.dart';
import 'package:iqro_mobile/features/salah/salah_progress.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'salah_models_test.dart' show salahFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('steps forward and back with the buttons and finishes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester, location: '/salah/lesson/fajr');

    expect(find.text('Шаг 1 из 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Ракаат 1 из 2'), findsOneWidget);
    expect(_button(tester, 'salah-back').onPressed, isNull);
    expect(harness.store.progress.lessons['fajr']?.stepSlug, 'fajr.r1.takbir');

    await _tapNext(tester);
    expect(find.text('Шаг 2 из 5'), findsOneWidget);
    expect(_button(tester, 'salah-back').onPressed, isNotNull);
    expect(harness.store.progress.lessons['fajr']?.stepSlug, 'fajr.r1.fatiha');

    await tester.tap(find.byKey(const ValueKey('salah-back')));
    await tester.pumpAndSettle();
    expect(find.text('Шаг 1 из 5'), findsOneWidget);

    for (var step = 0; step < 4; step++) {
      await _tapNext(tester);
    }
    expect(find.text('Шаг 5 из 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Ракаат 2 из 2'), findsOneWidget);
    expect(find.text('Завершить'), findsOneWidget);
    expect(
      harness.store.progress.statusOf('fajr'),
      SalahLessonStatus.inProgress,
    );

    await _tapNext(tester);
    expect(
      harness.store.progress.statusOf('fajr'),
      SalahLessonStatus.completed,
    );
    expect(find.text('Урок пройден'), findsOneWidget);
    expect(find.text('1 из 3 уроков'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('opens an unfinished lesson on its saved step', (tester) async {
    await _pump(
      tester,
      location: '/salah/lesson/fajr',
      progress: _progress('fajr', 'fajr.r2.tashahhud'),
    );
    expect(find.text('Шаг 4 из 5'), findsOneWidget);
  });

  group('schematic 3D', () {
    final switcher = find.byKey(const ValueKey('salah-visual-switch'));
    final view = find.byKey(const ValueKey('salah-3d-view'));

    testWidgets('loads on demand, follows the steps and pauses in background', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fake = _Fake3D();
      await _pump(tester, location: '/salah/lesson/fajr', view3d: fake.build);
      expect(switcher, findsOneWidget);
      expect(view, findsNothing);
      expect(fake.configs, isEmpty);

      await tester.tap(find.text('3D'));
      await tester.pump();
      expect(fake.last.step, 'takbir');
      expect(find.text('Загрузка 3D…'), findsOneWidget);
      fake.last.onReady();
      await tester.pump();
      expect(find.text('Схематичная 3D-иллюстрация'), findsOneWidget);
      expect(fake.last.running, isTrue);
      // The course picture still describes the step.
      expect(
        find.bySemanticsLabel('Стоящий мужчина поднимает руки до плеч'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Остановить движение'));
      await tester.pump();
      expect(fake.last.running, isFalse);
      await tester.tap(find.byTooltip('Воспроизвести движение'));
      await tester.pump();
      expect(fake.last.running, isTrue);
      await tester.tap(find.byKey(const ValueKey('salah-3d-speed')));
      await tester.pump();
      expect(find.text('0,75×'), findsOneWidget);
      expect(find.bySemanticsLabel('Скорость движения: 0,75×'), findsOneWidget);
      expect(fake.last.speed, .75);
      final resets = fake.last.resetCount;
      await tester.tap(find.byTooltip('Вернуть исходный ракурс'));
      await tester.pump();
      expect(fake.last.resetCount, resets + 1);

      // The choice lasts while the lesson is open. (The loading spinner never
      // settles, so the page turn is pumped for its duration.)
      await tester.tap(find.byKey(const ValueKey('salah-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Шаг 2 из 5'), findsOneWidget);
      expect(fake.last.step, 'qiyam');
      expect(view, findsOneWidget);
      expect(find.text('Загрузка 3D…'), findsOneWidget);
      fake.last.onReady();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(fake.last.running, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.last.running, isTrue);

      await tester.tap(find.text('Картинка'));
      await tester.pump();
      expect(view, findsNothing);
      semantics.dispose();
    });

    testWidgets('a failure brings the pictures back for the visit', (
      tester,
    ) async {
      final fake = _Fake3D();
      await _pump(tester, location: '/salah/lesson/fajr', view3d: fake.build);
      await tester.tap(find.text('3D'));
      await tester.pump();
      fake.last.onError('NO_WEBGL');
      await tester.pump();
      expect(view, findsNothing);
      expect(switcher, findsNothing);
      expect(
        find.text(
          '3D-иллюстрация недоступна на этом устройстве — показана картинка.',
        ),
        findsOneWidget,
      );
      await _tapNext(tester);
      expect(switcher, findsNothing);
      expect(find.byKey(const ValueKey('salah-3d-unavailable')), findsNothing);
    });

    testWidgets('reduced motion and steps without a pose keep the picture', (
      tester,
    ) async {
      final fake = _Fake3D();
      await _pump(
        tester,
        location: '/salah/lesson/fajr',
        view3d: fake.build,
        disableAnimations: true,
      );
      expect(
        find.byKey(const ValueKey('salah-image-position-takbir')),
        findsOneWidget,
      );
      expect(switcher, findsNothing);

      await _pump(
        tester,
        location: '/salah/lesson/wudu/step/wudu.face',
        view3d: fake.build,
      );
      expect(
        find.byKey(const ValueKey('salah-image-wudu-face')),
        findsOneWidget,
      );
      expect(switcher, findsNothing);
      expect(fake.configs, isEmpty);
    });

    testWidgets('the Arabic switch reads right to left in the top corner', (
      tester,
    ) async {
      await _pump(
        tester,
        location: '/salah/lesson/fajr',
        locale: 'ar',
        view3d: _Fake3D().build,
      );
      final picture = tester.getCenter(find.text('صورة'));
      final threeD = tester.getCenter(find.text('ثلاثي الأبعاد'));
      expect(threeD.dx, lessThan(picture.dx));
      final frame = tester.getRect(
        find.byKey(const ValueKey('salah-image-position-takbir')),
      );
      expect(frame.right - tester.getRect(switcher).right, lessThan(16));
    });
  });

  testWidgets('starts over when the saved step is gone', (tester) async {
    await _pump(
      tester,
      location: '/salah/lesson/fajr',
      progress: _progress('fajr', 'fajr.r1.removed-in-new-version'),
    );
    expect(find.text('Шаг 1 из 5'), findsOneWidget);
  });

  testWidgets('a step in the route wins over the saved step', (tester) async {
    await _pump(
      tester,
      location: '/salah/lesson/fajr/step/fajr.r1.ruku',
      progress: _progress('fajr', 'fajr.r2.tashahhud'),
    );
    expect(find.text('Шаг 3 из 5'), findsOneWidget);
  });

  testWidgets('a link to another step of the open lesson moves there', (
    tester,
  ) async {
    await _pump(tester, location: '/salah');
    // `go` to the same route pattern keeps the page, as a deep link does.
    final router = GoRouter.of(tester.element(find.byType(SalahHomeScreen)));
    router.go('/salah/lesson/fajr/step/fajr.r1.ruku');
    await tester.pumpAndSettle();
    expect(find.text('Шаг 3 из 5'), findsOneWidget);

    router.go('/salah/lesson/fajr/step/fajr.r1.fatiha');
    await tester.pumpAndSettle();
    expect(find.text('Шаг 2 из 5'), findsOneWidget);
  });

  testWidgets('swipes follow the reading direction', (tester) async {
    await _pump(tester, location: '/salah/lesson/fajr');
    final pager = find.byKey(const ValueKey('salah-steps'));

    // In LTR the next step comes from the right.
    await tester.drag(pager, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Шаг 1 из 5'), findsOneWidget);
    await tester.drag(pager, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Шаг 2 из 5'), findsOneWidget);

    await _pump(tester, location: '/salah/lesson/fajr', locale: 'ar');
    expect(find.text('الخطوة 1 من 5'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Начальный такбир'))),
      TextDirection.rtl,
    );
    await tester.drag(pager, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 1 من 5'), findsOneWidget);
    await tester.drag(pager, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 2 من 5'), findsOneWidget);
  });

  testWidgets('screen readers get next and previous step actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, location: '/salah/lesson/fajr');
    final node = tester.semantics.find(
      find.byKey(const ValueKey('salah-step-actions')),
    );
    expect(node.getSemanticsData().customSemanticsActionIds, hasLength(2));

    void perform(String label) => node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label)),
    );

    perform('Следующий шаг');
    await tester.pumpAndSettle();
    expect(find.text('Шаг 2 из 5'), findsOneWidget);
    perform('Предыдущий шаг');
    await tester.pumpAndSettle();
    expect(find.text('Шаг 1 из 5'), findsOneWidget);

    // The buttons are announced too, and each image has its alt text.
    expect(find.bySemanticsLabel('Далее'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Стоящий мужчина поднимает руки до плеч'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('large text fits at narrow width on every step', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, location: '/salah', textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('salah-continue')), findsOneWidget);

    for (final lesson in <String>['wudu', 'fajr']) {
      await _pump(tester, location: '/salah/lesson/$lesson', textScale: 2);
      final steps = SalahCourseDocument.fromJson(
        salahFixture(),
      ).lesson(lesson)!.steps;
      for (var step = 0; step < steps.length; step++) {
        expect(tester.takeException(), isNull, reason: steps[step].slug);
        // Every step scrolls down to its last formula without overflow.
        await tester.drag(
          find.byKey(ValueKey(steps[step].slug)),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: steps[step].slug);
        if (step < steps.length - 1) await _tapNext(tester);
      }
    }
  });

  testWidgets('practice keeps the image, the Arabic text and the audio', (
    tester,
  ) async {
    await _pump(tester, location: '/salah/lesson/fajr/step/fajr.r1.ruku');
    expect(
      find.byKey(const ValueKey('salah-instruction-fajr.r1.ruku')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('salah-translation-ruku-tasbih')),
      findsOneWidget,
    );
    expect(find.text('Столп (рукн)'), findsOneWidget);

    // Transliteration switches off on its own.
    await tester.tap(find.byKey(const ValueKey('salah-display-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Транслитерация'),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('salah-transliteration-ruku-tasbih')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('salah-translation-ruku-tasbih')),
      findsOneWidget,
    );

    await tester.tap(find.text('Практика'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('salah-instruction-fajr.r1.ruku')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('salah-translation-ruku-tasbih')),
      findsNothing,
    );
    expect(find.text('Столп (рукн)'), findsNothing);
    expect(
      find.byKey(const ValueKey('salah-arabic-ruku-tasbih')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('salah-image-position-ruku')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('salah-play-ruku-tasbih')),
      findsOneWidget,
    );
    // The tasbih counts its three repetitions.
    expect(
      find.byKey(const ValueKey('salah-counter-ruku-tasbih')),
      findsOneWidget,
    );
  });

  testWidgets('the Arabic text follows the reader font size', (tester) async {
    await _pump(
      tester,
      location: '/salah/lesson/fajr',
      preferences: <String, Object>{'reader_arabic_font_size': 36.0},
    );
    final arabic = tester.widget<Text>(
      find.byKey(const ValueKey('salah-arabic-takbir')),
    );
    expect(arabic.style?.fontSize, 36);
    expect(arabic.style?.fontFamily, IqroTheme.arabicFontFamily);
    expect(arabic.textDirection, TextDirection.rtl);
  });

  testWidgets('the next step image is loaded ahead', (tester) async {
    final harness = await _pump(tester, location: '/salah/lesson/fajr');
    expect(harness.images, contains(_mediaUrl('position-qiyam')));
    expect(harness.images, isNot(contains(_mediaUrl('position-ruku'))));

    await _tapNext(tester);
    expect(harness.images, contains(_mediaUrl('position-ruku')));
  });

  testWidgets('formula audio plays in the shared player', (tester) async {
    final harness = await _pump(tester, location: '/salah/lesson/fajr');

    final play = find.byKey(const ValueKey('salah-play-takbir'));
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pumpAndSettle();

    expect(harness.engine.setAudioSourceCalls, 1);
    final standalone = harness.audio.state.standalone!;
    expect(standalone.mediaItem.id, 'salah:takbir');
    expect(standalone.mediaItem.extras?['content_type'], 'salah');
  });

  testWidgets('course home lists sections and opens the next lesson', (
    tester,
  ) async {
    await _pump(
      tester,
      location: '/salah',
      progress: SalahCourseProgress(<String, SalahLessonProgress>{
        'what-is-salah': const SalahLessonProgress(
          status: SalahLessonStatus.completed,
          stepSlug: 'what-is-salah.intro',
          contentVersion: '2026-10-18',
        ),
      }),
    );

    expect(find.text('1 из 3 уроков'), findsOneWidget);
    expect(find.text('Основы'), findsOneWidget);
    expect(find.text('Пять молитв'), findsOneWidget);
    expect(find.textContaining('Пройден'), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
    // Without a manifest there is nothing to download.
    expect(find.byKey(const ValueKey('salah-offline')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('salah-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Шаг 1 из 2'), findsOneWidget);
    expect(find.text('Намерение'), findsOneWidget);
  });

  testWidgets('course home downloads and removes the pictures', (tester) async {
    await _pump(
      tester,
      location: '/salah',
      offline: _MemoryOfflineRepository(publishedBytes: 3640),
    );

    expect(find.text('Картинки без интернета'), findsOneWidget);
    expect(find.text('Иллюстрации курса · 3.6 KB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('salah-offline-download')));
    await tester.pumpAndSettle();
    expect(find.text('Сохранены на устройстве · 3.6 KB'), findsOneWidget);
    expect(find.byKey(const ValueKey('salah-offline-download')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('salah-offline-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Иллюстрации курса · 3.6 KB'), findsOneWidget);
  });
}

ButtonStyleButton _button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));

/// Stands in for the WebView and keeps what each build asked it to show.
class _Fake3D {
  final configs = <Salah3DViewConfig>[];

  Salah3DViewConfig get last => configs.last;

  Widget build(BuildContext context, Salah3DViewConfig config) {
    configs.add(config);
    return ColoredBox(
      key: ValueKey('fake-3d-${config.step}'),
      color: Colors.white,
    );
  }
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('salah-next')));
  await tester.pumpAndSettle();
}

String _mediaUrl(String key) =>
    ((salahFixture()['media']! as Map)[key] as Map)['url']! as String;

SalahCourseProgress _progress(String lesson, String step) =>
    SalahCourseProgress(<String, SalahLessonProgress>{
      lesson: SalahLessonProgress(
        status: SalahLessonStatus.inProgress,
        stepSlug: step,
        contentVersion: '2026-10-18',
      ),
    });

class _Harness {
  _Harness(this.store, this.images, this.engine, this.audio);

  final _MemoryProgressStore store;
  final List<String> images;
  final _SilentAudioEngine engine;
  final AudioController audio;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required String location,
  String locale = 'ru',
  double textScale = 1,
  SalahCourseProgress progress = const SalahCourseProgress(),
  Map<String, Object> preferences = const <String, Object>{},
  SalahOfflineRepository? offline,
  Salah3DViewBuilder? view3d,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final sharedPreferences = await SharedPreferences.getInstance();
  final sqlDatabase = (await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(sqlDatabase.close));
  final database = LocalDatabase.forTesting(sqlDatabase);
  final document = SalahCourseDocument.fromJson(salahFixture());
  final store = _MemoryProgressStore(progress);
  final images = <String>[];
  final engine = _SilentAudioEngine();
  final audio = AudioController(engine: engine);
  final router = GoRouter(
    initialLocation: '/salah',
    routes: <RouteBase>[
      GoRoute(
        path: '/salah',
        builder: (context, state) => const SalahHomeScreen(),
      ),
      GoRoute(
        path: '/salah/lesson/:slug',
        builder: (context, state) =>
            SalahLessonScreen(lessonSlug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/salah/lesson/:slug/step/:step',
        builder: (context, state) => SalahLessonScreen(
          lessonSlug: state.pathParameters['slug']!,
          stepSlug: state.pathParameters['step'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // A new scope per pump: the display mode resets with it.
      key: UniqueKey(),
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(database),
        appPreferencesProvider.overrideWith(
          (ref) => AppPreferencesController(
            PreferencesStore(sharedPreferences),
            PlanRepository(database),
          ),
        ),
        activeAccountScopeKeyProvider.overrideWithValue((
          userId: 'test-owner',
          epoch: 1,
        )),
        salahCourseProvider.overrideWith((ref, slug) async => document),
        salahProgressStoreProvider.overrideWithValue(store),
        salahOfflineRepositoryProvider.overrideWithValue(
          offline ?? _MemoryOfflineRepository(),
        ),
        salahImageProvider.overrideWithValue((url) {
          images.add(url);
          return MemoryImage(_transparentPng);
        }),
        audioControllerProvider.overrideWith((ref) => audio),
        if (view3d != null)
          salah3DViewBuilderProvider.overrideWithValue(view3d),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (location != '/salah') {
    router.push(location);
    await tester.pumpAndSettle();
  }
  return _Harness(store, images, engine, audio);
}

final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// The same rules as [SalahProgressStore], in memory: widget tests cannot
/// wait for the database isolate.
class _MemoryProgressStore implements SalahProgressStore {
  _MemoryProgressStore(this.progress);

  SalahCourseProgress progress;

  @override
  Future<SalahCourseProgress> read(String course) async => progress;

  @override
  Future<SalahCourseProgress> recordStep({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async {
    final completed = progress.statusOf(lesson) == SalahLessonStatus.completed;
    return _set(
      lesson,
      SalahLessonProgress(
        status: completed
            ? SalahLessonStatus.completed
            : SalahLessonStatus.inProgress,
        stepSlug: stepSlug,
        contentVersion: contentVersion,
      ),
    );
  }

  @override
  Future<SalahCourseProgress> complete({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async => _set(
    lesson,
    SalahLessonProgress(
      status: SalahLessonStatus.completed,
      stepSlug: stepSlug,
      contentVersion: contentVersion,
    ),
  );

  SalahCourseProgress _set(String lesson, SalahLessonProgress value) =>
      progress = SalahCourseProgress(<String, SalahLessonProgress>{
        ...progress.lessons,
        lesson: value,
      });
}

class _SilentAudioEngine implements IqroAudioEngine {
  var setAudioSourceCalls = 0;

  @override
  Stream<PlayerException> get errorStream => const Stream.empty();

  @override
  bool get playing => false;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  ProcessingState get processingState => ProcessingState.idle;

  @override
  Future<void> clearAudioSources() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    setAudioSourceCalls += 1;
    return Duration.zero;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> stop() async {}
}

/// The offline package in memory, like the progress store. Without
/// [publishedBytes] there is no manifest and the pictures stay online.
class _MemoryOfflineRepository implements SalahOfflineRepository {
  _MemoryOfflineRepository({this.publishedBytes});

  final int? publishedBytes;
  var _stored = const SalahOfflineSnapshot.empty();

  @override
  Future<SalahOfflineSnapshot> snapshot(String slug, String language) async =>
      _stored;

  @override
  Future<SalahOfflineSnapshot> check(String slug, String language) async {
    final bytes = publishedBytes;
    if (bytes == null) throw const SocketException('offline');
    return SalahOfflineSnapshot(
      status: _stored.status,
      totalItems: 1,
      totalBytes: bytes,
    );
  }

  @override
  Future<SalahOfflineSnapshot> install(
    String slug,
    String language, {
    void Function(SalahOfflineSnapshot progress)? onProgress,
  }) async => _stored = SalahOfflineSnapshot(
    status: SalahOfflineStatus.ready,
    completedItems: 1,
    totalItems: 1,
    downloadedBytes: publishedBytes!,
    totalBytes: publishedBytes!,
  );

  @override
  Future<void> delete(String slug, String language) async =>
      _stored = const SalahOfflineSnapshot.empty();

  @override
  Future<Map<String, String>> localImages(String slug, String language) async =>
      const <String, String>{};
}
