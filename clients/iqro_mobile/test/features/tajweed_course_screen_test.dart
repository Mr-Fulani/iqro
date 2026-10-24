import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_home_screen.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_models.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_progress.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_repository.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_lesson_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'tajweed_course_test_data.dart';

void main() {
  testWidgets('home shows progress and continues the right lesson', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      progress: _progress({
        'izhar': ('completed', 'find', '2026-10-22T10:00:00.000Z'),
        'ikhfa-shafawi': (
          'in_progress',
          'example-2',
          '2026-10-22T11:00:00.000Z',
        ),
      }),
    );
    expect(find.text('Таджвид'), findsWidgets);
    expect(_text(tester, 'tajweed-course-progress'), '1 из 3 уроков');
    expect(
      find.byKey(const ValueKey('tajweed-course-review-note')),
      findsOneWidget,
    );
    expect(find.text('Нун с сукуном и танвин'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-lesson-iqlab')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tajweed-lesson-status-izhar')),
        matching: find.text('Пройден'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tajweed-lesson-status-ikhfa-shafawi')),
        matching: find.text('Начат'),
      ),
      findsOneWidget,
    );
    expect(find.text('4 мин'), findsWidgets);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(harness.sync.calls, 1);

    await tester.tap(find.byKey(const ValueKey('tajweed-course-continue')));
    await _settle(tester);
    expect(find.byType(TajweedLessonScreen), findsOneWidget);
    expect(find.text('Ихфа шафави — мим перед ب'), findsOneWidget);
    // The unfinished lesson opens on its saved step.
    expect(_label(tester), 'Шаг 4 из 6');
    expect(harness.sync.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new learner starts the course from the first lesson', (
    tester,
  ) async {
    await _pump(tester);
    expect(_text(tester, 'tajweed-course-progress'), '0 из 3 уроков');
    expect(find.text('Начать курс'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-continue')));
    await _settle(tester);
    expect(find.text('Изхар — нун звучит ясно'), findsOneWidget);
    expect(_label(tester), 'Шаг 1 из 6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps through the rule, how to read and the examples', (
    tester,
  ) async {
    final harness = await _pump(tester, location: '/tajweed/lesson/izhar');
    expect(harness.repository.requests, ['izhar 0 4']);
    expect(_label(tester), 'Шаг 1 из 6');
    expect(find.text('Правило'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-course-target')), findsOne);
    expect(find.text('الإظهار الحلقي'), findsOneWidget);
    expect(_text(tester, 'tajweed-course-letters'), 'ء ه ع ح غ خ');
    expect(harness.store.progress.lessons['izhar']?.stepSlug, 'intro');
    expect(_button(tester, 'tajweed-course-back').onPressed, isNull);

    await _next(tester);
    expect(_label(tester), 'Шаг 2 из 6');
    expect(find.text('Как читать'), findsOneWidget);

    await _next(tester);
    expect(_label(tester), 'Шаг 3 из 6');
    expect(find.text('Пример 1 из 3'), findsOneWidget);
    expect(find.text('Сура 89, аят 2'), findsOneWidget);
    // Both words of the izhar «وَلَيَالٍ عَشْرٍ» are lit.
    expect(_lit(tester, 2), [1, 2]);
    expect(_occurrence(tester), 'وَلَيَالٍ عَشْرٍ');
    expect(harness.store.progress.lessons['izhar']?.stepSlug, 'example-1');

    await tester.tap(find.byKey(const ValueKey('tajweed-course-slow')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tajweed-course-listen')));
    await _settle(tester);
    var source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.child.uri, Uri.parse('https://cdn.example/89.mp3'));
    // From the first word's start to the second word's end.
    expect(source.start, const Duration(milliseconds: 1000));
    expect(source.end, const Duration(milliseconds: 2900));
    expect(harness.engine.speed, .75);
    expect(find.text('Остановить'), findsOneWidget);

    // A step change stops the fragment.
    await _next(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(find.text('Пример 2 из 3'), findsOneWidget);
    expect(harness.store.progress.lessons['izhar']?.stepSlug, 'example-2');

    await tester.tap(find.byKey(const ValueKey('tajweed-course-play-ayah')));
    await _settle(tester);
    source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 500));
    expect(source.end, const Duration(milliseconds: 3000));
    expect(
      harness.audio.state.standalone?.mediaItem.id,
      'tajweed-course:recitation-1:101:11:ayah',
    );
    await tester.tap(find.byKey(const ValueKey('tajweed-course-back')));
    await _settle(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('find the rule: misses, the answer, another ayah, finish', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(tester, location: '/tajweed/lesson/izhar');
    for (var step = 0; step < 5; step++) {
      await _next(tester);
    }
    expect(_label(tester), 'Шаг 6 из 6');
    expect(find.text('Найдите правило в аяте'), findsOneWidget);
    expect(find.text('Нажмите на слово, в котором есть «Изхар».'), findsOne);
    expect(find.text('Завершить урок'), findsOneWidget);
    // No word is lit before the learner answers.
    expect(_lit(tester, 4, prefix: 'tajweed-course-find'), isEmpty);
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsNothing);

    // «Another ayah» continues after the first four examples.
    await tester.tap(find.byKey(const ValueKey('tajweed-course-another')));
    await _settle(tester);
    expect(harness.repository.requests.last, 'izhar 4 1');
    expect(find.text('Сура 88, аят 5'), findsOneWidget);

    await _tapWord(tester, 1);
    expect(
      _text(tester, 'tajweed-course-feedback'),
      'Здесь этого правила нет — попробуйте другое слово.',
    );
    expect(
      _word(tester, 1),
      isSemantics(
        label: 'تُسْقَىٰ',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(_word(tester, 2), isSemantics(isSelected: false));
    expect(
      find.byKey(const ValueKey('tajweed-course-show-answer')),
      findsNothing,
    );
    await _tapWord(tester, 1);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-show-answer')));
    await _settle(tester);
    expect(_text(tester, 'tajweed-course-feedback'), 'Вот где здесь «Изхар».');
    expect(find.textContaining('Верно!'), findsNothing);
    expect(_lit(tester, 4, prefix: 'tajweed-course-find'), [2, 3]);
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tajweed-course-another')));
    await _settle(tester);
    expect(harness.repository.requests.last, 'izhar 5 1');
    expect(find.text('Сура 88, аят 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-course-feedback')), findsNothing);
    await _tapWord(tester, 3);
    expect(_text(tester, 'tajweed-course-feedback'), 'Верно! Здесь «Изхар».');
    expect(_lit(tester, 3, prefix: 'tajweed-course-find'), [2, 3]);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-listen')));
    await _settle(tester);
    final source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 2000));
    expect(source.end, const Duration(milliseconds: 3900));

    await _next(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(
      harness.store.progress.statusOf('izhar'),
      TajweedLessonStatus.completed,
    );
    expect(find.text('Урок пройден'), findsOneWidget);
    expect(
      find.text('Следующий урок: Идгам с гунной — слияние с носовым звуком'),
      findsOneWidget,
    );
    // On the course, on the lesson and after it.
    expect(harness.sync.calls, 3);

    await tester.tap(find.byKey(const ValueKey('tajweed-course-all-lessons')));
    await _settle(tester);
    expect(find.byType(TajweedCourseHomeScreen), findsOneWidget);
    expect(_text(tester, 'tajweed-course-progress'), '1 из 3 уроков');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('more examples come before «find» and open the first new one', (
    tester,
  ) async {
    final harness = await _pump(tester, location: '/tajweed/lesson/izhar');
    for (var step = 0; step < 4; step++) {
      await _next(tester);
    }
    expect(find.text('Пример 3 из 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-more')));
    await _settle(tester);
    expect(harness.repository.requests.last, 'izhar 4 3');
    expect(_label(tester), 'Шаг 6 из 9');
    expect(find.text('Пример 4 из 6'), findsOneWidget);
    expect(find.text('Сура 88, аят 5'), findsOneWidget);
    expect(harness.store.progress.lessons['izhar']?.stepSlug, 'example-4');

    await _next(tester);
    await _next(tester);
    expect(find.text('Пример 6 из 6'), findsOneWidget);
    // The examples ran out: no more to add and no other ayah to find in.
    expect(find.byKey(const ValueKey('tajweed-course-more')), findsNothing);
    await _next(tester);
    expect(find.text('Найдите правило в аяте'), findsOneWidget);
    expect(find.text('Сура 80, аят 18'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-course-another')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('examples load in place of the first example, with a retry', (
    tester,
  ) async {
    final gate = Completer<void>();
    final harness = await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      gate: gate,
      failures: 1,
    );
    expect(_label(tester), 'Шаг 1 из 3');
    await _next(tester);
    await _next(tester);
    expect(
      find.byKey(const ValueKey('tajweed-course-examples-loading')),
      findsOneWidget,
    );
    expect(find.text('Подбираем примеры из Корана…'), findsOneWidget);

    gate.complete();
    await _settle(tester);
    expect(find.text('Не удалось загрузить примеры.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('tajweed-course-examples-retry')),
    );
    await _settle(tester);
    expect(harness.repository.requests, ['izhar 0 4', 'izhar 0 4']);
    expect(find.text('Пример 1 из 3'), findsOneWidget);
    expect(_label(tester), 'Шаг 3 из 6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('resumes a saved step once the examples have it', (tester) async {
    final harness = await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      progress: _progress({
        'izhar': ('in_progress', 'find', '2026-10-22T10:00:00.000Z'),
      }),
    );
    expect(_label(tester), 'Шаг 6 из 6');
    expect(find.text('Найдите правило в аяте'), findsOneWidget);
    expect(harness.store.progress.lessons['izhar']?.stepSlug, 'find');

    // A step the lesson no longer has starts it over.
    await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      progress: _progress({
        'izhar': ('in_progress', 'example-6', '2026-10-22T10:00:00.000Z'),
      }),
    );
    expect(_label(tester), 'Шаг 1 из 6');

    // A passed lesson opens from the start.
    await _pump(
      tester,
      location: '/tajweed/lesson/izhar',
      progress: _progress({
        'izhar': ('completed', 'find', '2026-10-22T10:00:00.000Z'),
      }),
    );
    expect(_label(tester), 'Шаг 1 из 6');

    // A link to a step wins over the saved one.
    await _pump(
      tester,
      location: '/tajweed/lesson/izhar/step/example-2',
      progress: _progress({
        'izhar': ('in_progress', 'find', '2026-10-22T10:00:00.000Z'),
      }),
    );
    expect(find.text('Пример 2 из 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['ru', 'ar']) {
    testWidgets('$locale: every step fits a 360×740 phone', (tester) async {
      await _pump(tester, locale: locale, size: const Size(360, 740));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tajweed-course-continue')));
      await _settle(tester);
      final next = find.byKey(const ValueKey('tajweed-course-next'));
      for (var step = 0; step < 5; step++) {
        expect(tester.getRect(next).right, lessThanOrEqualTo(360));
        expect(tester.getRect(next).bottom, lessThanOrEqualTo(740));
        await _next(tester);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('tajweed-course-another')));
      await _settle(tester);
      await _tapWord(tester, 2);
      expect(find.byKey(const ValueKey('tajweed-course-listen')), findsOne);
      expect(tester.takeException(), isNull);
      await _next(tester);
      expect(find.byKey(const ValueKey('tajweed-course-completed')), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Arabic reads right to left; the arrow keys follow it', (
    tester,
  ) async {
    await _pump(tester, locale: 'ar', location: '/tajweed/lesson/izhar');
    expect(_label(tester), 'الخطوة 1 من 6');
    expect(
      Directionality.of(tester.element(find.text('الحكم'))),
      TextDirection.rtl,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(_label(tester), 'الخطوة 2 من 6');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(_label(tester), 'الخطوة 1 من 6');
    expect(tester.takeException(), isNull);
  });
}

typedef _Harness = ({
  _MemoryStore store,
  _FakeRepository repository,
  _CountingSync sync,
  _Engine engine,
  AudioController audio,
});

TajweedCourseProgress _progress(
  Map<String, (String status, String step, String at)> lessons,
) => TajweedCourseProgress.fromJson(<String, Object?>{
  'lessons': <String, Object?>{
    for (final MapEntry(:key, :value) in lessons.entries)
      key: <String, Object?>{
        'status': value.$1,
        'step_slug': value.$2,
        'content_version': '2026-10-22',
        'updated_at': value.$3,
      },
  },
});

Future<_Harness> _pump(
  WidgetTester tester, {
  String location = '/tajweed',
  String locale = 'ru',
  Size size = const Size(400, 900),
  TajweedCourseProgress progress = const TajweedCourseProgress(),
  Completer<void>? gate,
  int failures = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final document = TajweedCourseDocument.fromJson(tajweedCourseDocumentJson());
  final store = _MemoryStore(progress);
  final repository = _FakeRepository(gate: gate, failures: failures);
  final sync = _CountingSync();
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  final router = GoRouter(
    initialLocation: '/tajweed',
    routes: <RouteBase>[
      GoRoute(
        path: '/tajweed',
        builder: (context, state) => const TajweedCourseHomeScreen(),
      ),
      GoRoute(
        path: '/tajweed/lesson/:slug',
        builder: (context, state) =>
            TajweedLessonScreen(lessonSlug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/tajweed/lesson/:slug/step/:step',
        builder: (context, state) => TajweedLessonScreen(
          lessonSlug: state.pathParameters['slug']!,
          stepSlug: state.pathParameters['step'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        activeAccountScopeKeyProvider.overrideWithValue((
          userId: 'test-owner',
          epoch: 1,
        )),
        tajweedCourseProvider.overrideWith((ref, slug) async => document),
        tajweedCourseRepositoryProvider.overrideWithValue(repository),
        tajweedCourseProgressStoreProvider.overrideWithValue(store),
        tajweedProgressSyncProvider.overrideWithValue(sync),
        tajweedCourseRecitationProvider.overrideWithValue(
          () async => 'recitation-1',
        ),
        audioRepositoryProvider.overrideWithValue(_AudioRepository()),
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
  if (location != '/tajweed') {
    unawaited(router.push(location));
    await _settle(tester);
  }
  return (
    store: store,
    repository: repository,
    sync: sync,
    engine: engine,
    audio: audio,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tajweed-course-next')));
  await _settle(tester);
}

Future<void> _tapWord(WidgetTester tester, int position) async {
  await tester.tap(find.byKey(ValueKey('tajweed-course-find-$position')));
  await _settle(tester);
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

String? _label(WidgetTester tester) =>
    _text(tester, 'tajweed-course-step-label');

String _occurrence(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('tajweed-course-occurrence')))
    .textSpan!
    .toPlainText();

ButtonStyleButton _button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));

/// Positions of the words lit with the target's underline.
List<int> _lit(
  WidgetTester tester,
  int words, {
  String prefix = 'tajweed-course-word',
}) {
  bool lit(int position) {
    final box = tester.widget<Container>(
      find.byKey(ValueKey('$prefix-$position')),
    );
    final border = (box.decoration! as BoxDecoration).border;
    return border is Border &&
        border.bottom.width == 2 &&
        border.top == BorderSide.none;
  }

  return [
    for (var position = 1; position <= words; position++)
      if (lit(position)) position,
  ];
}

SemanticsNode _word(WidgetTester tester, int position) =>
    tester.getSemantics(find.byKey(ValueKey('tajweed-course-find-$position')));

/// The same rules as [TajweedCourseProgressStore], in memory.
class _MemoryStore implements TajweedCourseProgressStore {
  _MemoryStore(this.progress);

  TajweedCourseProgress progress;
  var _minute = 0;

  String _now() =>
      tajweedProgressTime(DateTime.utc(2026, 10, 23, 8, _minute++));

  @override
  Future<TajweedCourseProgress> read(String course, {accountScope}) async =>
      progress;

  @override
  Future<TajweedCourseProgress> recordStep({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async => _set(
    lesson,
    progress.lessons[lesson]?.completed ?? false,
    stepSlug,
    contentVersion,
  );

  @override
  Future<TajweedCourseProgress> complete({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async => _set(lesson, true, stepSlug, contentVersion);

  @override
  Future<TajweedCourseProgress> merge(
    String course,
    TajweedCourseProgress remote, {
    accountScope,
  }) async => progress = progress.merge(remote);

  TajweedCourseProgress _set(
    String lesson,
    bool completed,
    String step,
    String version,
  ) => progress = TajweedCourseProgress({
    ...progress.lessons,
    lesson: TajweedLessonProgress(
      status: completed
          ? TajweedLessonStatus.completed
          : TajweedLessonStatus.inProgress,
      stepSlug: step,
      contentVersion: version,
      updatedAt: _now(),
    ),
  });
}

class _CountingSync implements TajweedProgressSync {
  var calls = 0;

  @override
  Future<TajweedCourseProgress?> sync(String course) async {
    calls += 1;
    return null;
  }
}

class _FakeRepository implements TajweedCourseRepository {
  _FakeRepository({this.gate, this.failures = 0});

  final Completer<void>? gate;
  int failures;
  final requests = <String>[];

  @override
  Future<TajweedExamplesPage> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) async {
    requests.add('$lesson $offset $limit');
    await gate?.future;
    if (failures > 0) {
      failures -= 1;
      throw StateError('offline');
    }
    return TajweedExamplesPage.fromJson(
      tajweedCourseExamplesPage(lesson, offset: offset, limit: limit),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every word of an ayah is timed: word N plays from N s for 0.9 s.
class _AudioRepository implements AudioRepository {
  @override
  Future<AyahPlayback> ayahPlayback({
    required String recitationId,
    required int surah,
    required int ayah,
  }) async => AyahPlayback(
    track: AudioTrack(
      id: 'track-$surah',
      recitationId: recitationId,
      surah: surah,
      url: 'https://cdn.example/$surah.mp3',
      duration: const Duration(minutes: 1),
      offlineDownloadAllowed: false,
    ),
    words: {
      for (var position = 1; position <= 12; position++)
        position: (
          start: Duration(milliseconds: position * 1000),
          end: Duration(milliseconds: position * 1000 + 900),
        ),
    },
    start: const Duration(milliseconds: 500),
    end: const Duration(milliseconds: 3000),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Engine implements IqroAudioEngine {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final sources = <AudioSource>[];
  var speed = 1.0;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;

  @override
  Future<Duration?> setAudioSource(AudioSource source) async {
    sources.add(source);
    processingState = ProcessingState.ready;
    return null;
  }

  @override
  Future<void> clearAudioSources() async =>
      processingState = ProcessingState.idle;
  @override
  Future<void> setSpeed(double value) async => speed = value;
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> play() async {
    playing = true;
    _states.add(PlayerState(true, processingState));
  }

  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {
    playing = false;
    processingState = ProcessingState.idle;
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await _states.close();
  }
}
