import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:iqro_mobile/features/tajweed_course/tajweed_practice.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_practice_screen.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_practice_store.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'tajweed_course_test_data.dart';
import 'tajweed_practice_test_data.dart';

final _start = DateTime.utc(2026, 10, 22, 12);
final _today = tajweedLocalDate(_start);

/// Izhar and idgham with ghunnah passed, ikhfa shafawi started.
final _passed = TajweedCourseProgress.fromJson(<String, Object?>{
  'lessons': <String, Object?>{
    for (final (slug, status) in [
      ('izhar', 'completed'),
      ('idgham-ghunnah', 'completed'),
      ('ikhfa-shafawi', 'in_progress'),
    ])
      slug: <String, Object?>{
        'status': status,
        'step_slug': 'find',
        'content_version': '2026-10-22',
        'updated_at': '2026-10-22T10:00:00.000Z',
      },
  },
});

/// Score 19, two days in a row up to today, one task due and one later.
TajweedPracticeLocal _practiced() => TajweedPracticeLocal(
  state: TajweedPracticeState.tryParse(<String, Object?>{
    'sessions': 3,
    'answers': 24,
    'correct': 19,
    'score': 19,
    'streak': <String, Object?>{'current': 2, 'best': 4, 'last_date': _today},
    'review': [
      <String, Object?>{
        'key': 'identify~80:13~idgham_ghunnah',
        'target': 'idgham_ghunnah',
        'type': 'identify',
        'box': 1,
        'due_at': '2026-10-22T09:00:00.000Z',
      },
      <String, Object?>{
        'key': 'find~89:2~izhar',
        'target': 'izhar',
        'type': 'find',
        'box': 2,
        'due_at': '2026-10-25T09:00:00.000Z',
      },
    ],
  })!,
);

void main() {
  testWidgets('without a passed lesson the practice sends to the course', (
    tester,
  ) async {
    final harness = await _pump(tester, location: '/tajweed');
    expect(
      find.text('Закрепите пройденные правила на аятах всего Корана.'),
      findsOne,
    );
    await tester.tap(find.byKey(const ValueKey('tajweed-practice-open')));
    await _settle(tester);
    expect(find.byType(TajweedPracticeScreen), findsOneWidget);
    expect(find.text('Практика таджвида'), findsOneWidget);
    expect(
      _text(tester, 'tajweed-practice-no-lessons'),
      'Пройдите хотя бы один урок курса: практика строится по пройденным '
      'правилам.',
    );
    expect(_text(tester, 'tajweed-practice-score'), '0');
    expect(_text(tester, 'tajweed-practice-streak'), '0 дн. подряд');
    expect(_text(tester, 'tajweed-practice-review-count'), 'На повторение: 0');
    expect(find.byKey(const ValueKey('tajweed-practice-start')), findsNothing);
    expect(harness.sync.calls, 1);

    await tester.tap(find.byKey(const ValueKey('tajweed-practice-to-course')));
    await _settle(tester);
    expect(find.byType(TajweedPracticeScreen), findsNothing);
    expect(find.byType(TajweedCourseHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the start shows the stats and the passed rules', (tester) async {
    final harness = await _pump(
      tester,
      progress: _passed,
      practice: _practiced(),
      failures: 1,
    );
    expect(_text(tester, 'tajweed-practice-score'), '19');
    expect(_text(tester, 'tajweed-practice-streak'), '2 дн. подряд');
    expect(_text(tester, 'tajweed-practice-review-count'), 'На повторение: 1');
    expect(find.text('Пройденные правила'), findsOneWidget);
    expect(find.byKey(const ValueKey('tajweed-practice-rule-izhar')), findsOne);
    expect(
      find.byKey(const ValueKey('tajweed-practice-rule-idgham-ghunnah')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('tajweed-practice-rule-ikhfa-shafawi')),
      findsNothing,
    );
    expect(find.text('Начать практику'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tajweed-practice-start')));
    await _settle(tester);
    expect(
      _text(tester, 'tajweed-practice-error'),
      'Не удалось собрать задания.',
    );
    await tester.tap(find.byKey(const ValueKey('tajweed-practice-start')));
    await _settle(tester);
    // The passed lessons, eight tasks, a seed, and the task due for review.
    expect(harness.repository.requests, hasLength(2));
    final request = harness.repository.requests.last;
    expect(request.lessons, ['izhar', 'idgham-ghunnah']);
    expect(request.review, ['identify~80:13~idgham_ghunnah']);
    expect(request.seed, inInclusiveRange(0, (1 << 31) - 1));
    expect(_text(tester, 'tajweed-practice-counter'), 'Задание 1 из 3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session: find, identify, listen without timings, summary', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pump(
      tester,
      progress: _passed,
      practice: _practiced(),
      timed: {80},
    );
    await _begin(tester);

    // «Find», back for review: no word is lit before the answer.
    expect(_text(tester, 'tajweed-practice-counter'), 'Задание 1 из 3');
    expect(
      find.byKey(const ValueKey('tajweed-practice-review-badge')),
      findsOne,
    );
    expect(_prompt(tester), 'Найдите в аяте: «Изхар»');
    expect(_lit(tester, 4, prefix: 'tajweed-course-find'), isEmpty);
    expect(_text(tester, 'tajweed-practice-feedback'), '');
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsNothing);
    await _tapWord(tester, 4);
    expect(_text(tester, 'tajweed-practice-feedback'), 'Верно!');
    expect(_lit(tester, 4, prefix: 'tajweed-course-find'), [3, 4]);
    expect(_litColor(tester, 'tajweed-course-find-4'), const Color(0xff7b5ea7));
    // Only the first answer counts.
    await _tapWord(tester, 1);
    expect(_text(tester, 'tajweed-practice-feedback'), 'Верно!');
    expect(_lit(tester, 4, prefix: 'tajweed-course-find'), [3, 4]);
    // The place found plays, without the whole ayah.
    expect(
      find.byKey(const ValueKey('tajweed-course-play-ayah')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('tajweed-course-listen')));
    await _settle(tester);
    final source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 3000));
    expect(source.end, const Duration(milliseconds: 4900));
    expect(harness.audio.state.standalone, isNotNull);

    // «Identify»: the place is in the accent colour, not the rule's.
    await _next(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(_text(tester, 'tajweed-practice-counter'), 'Задание 2 из 3');
    expect(
      find.byKey(const ValueKey('tajweed-practice-review-badge')),
      findsNothing,
    );
    expect(_prompt(tester), 'Какое правило в выделенном месте?');
    expect(_lit(tester, 3), [2, 3]);
    final accent = Theme.of(
      tester.element(find.byKey(const ValueKey('tajweed-course-word-2'))),
    ).colorScheme.primary;
    expect(_litColor(tester, 'tajweed-course-word-2'), accent);
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsNothing);
    expect(
      tester.getSemantics(_option('izhar')),
      isSemantics(
        label: 'Изхар',
        isButton: true,
        isEnabled: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    await tester.tap(_option('izhar'));
    await _settle(tester);
    expect(
      _text(tester, 'tajweed-practice-feedback'),
      'Неверно. Здесь «Идгам с гунной».',
    );
    expect(
      tester.getSemantics(_option('izhar')),
      isSemantics(label: 'Изхар', isButton: true, isSelected: true),
    );
    expect(_litColor(tester, 'tajweed-course-word-2'), const Color(0xff09b000));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    // After the answer the place can be heard.
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsOne);

    // «Listen» without the reciter's timings is asked as «identify».
    await _next(tester);
    expect(_text(tester, 'tajweed-practice-counter'), 'Задание 3 из 3');
    expect(_prompt(tester), 'Какое правило в выделенном месте?');
    expect(_lit(tester, 5), [2, 3]);
    expect(find.text('Завершить'), findsOneWidget);
    await tester.tap(_option('ikhafa_shafawi'));
    await _settle(tester);
    expect(_text(tester, 'tajweed-practice-feedback'), 'Верно!');

    // «Back» shows a past task with its answer.
    await tester.tap(find.byKey(const ValueKey('tajweed-practice-back')));
    await _settle(tester);
    expect(
      _text(tester, 'tajweed-practice-feedback'),
      'Неверно. Здесь «Идгам с гунной».',
    );
    await _next(tester);
    await _next(tester);

    expect(_text(tester, 'tajweed-practice-result'), 'Верно 2 из 3');
    final session = harness.practice.local.pending.single;
    expect(
      session.id,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-')),
    );
    expect(session.course, 'tajweed');
    expect(session.localDate, _today);
    expect(DateTime.parse(session.finishedAt).isAfter(_start), isTrue);
    expect(
      [
        for (final answer in session.answers)
          '${answer.key} ${answer.type.name} ${answer.correct}',
      ],
      [
        'find~80:18~izhar find true',
        'identify~80:13~idgham_ghunnah identify false',
        'identify~96:14~ikhafa_shafawi identify true',
      ],
    );
    expect(session.answers.first.at, endsWith('Z'));
    expect(_text(tester, 'tajweed-practice-score'), '21');
    expect(_text(tester, 'tajweed-practice-streak'), '2 дн. подряд');
    // The mistake is due again at once.
    expect(_text(tester, 'tajweed-practice-review-count'), 'На повторение: 1');
    expect(find.text('Ещё раз'), findsOneWidget);
    // On opening and after the session.
    expect(harness.sync.calls, 2);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('listen: the fragment plays and the ayah waits for the answer', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      progress: _passed,
      tasks: <String, Object?>{
        'tasks': (tajweedPracticeTasksJson()['tasks']! as List).sublist(2),
      },
    );
    await _begin(tester);
    expect(_prompt(tester), 'Послушайте и определите правило');
    expect(find.byKey(const ValueKey('tajweed-course-ayah')), findsNothing);
    expect(
      find.byKey(const ValueKey('tajweed-course-play-ayah')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('tajweed-course-slow')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tajweed-course-listen')));
    await _settle(tester);
    final source = harness.engine.sources.last as ClippingAudioSource;
    expect(source.start, const Duration(milliseconds: 2000));
    expect(source.end, const Duration(milliseconds: 3900));
    expect(harness.engine.speed, .75);

    await tester.tap(_option('izhar'));
    await _settle(tester);
    expect(_prompt(tester), 'Послушайте и определите правило');
    expect(_lit(tester, 5), [2, 3]);
    expect(
      _text(tester, 'tajweed-practice-feedback'),
      'Неверно. Здесь «Ихфа шафави».',
    );
    expect(find.byKey(const ValueKey('tajweed-course-listen')), findsOne);
    await _next(tester);
    expect(harness.audio.state.standalone, isNull);
    expect(
      harness.practice.local.pending.single.answers.single.key,
      'listen~96:14~ikhafa_shafawi',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Lesson completed» opens the practice', (tester) async {
    await _pump(tester, location: '/tajweed/lesson/izhar/step/find');
    await _tapWord(tester, 2);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-next')));
    await _settle(tester);
    expect(find.text('Урок пройден'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tajweed-course-practice')));
    await _settle(tester);
    expect(find.byType(TajweedPracticeScreen), findsOneWidget);
    expect(find.byType(TajweedLessonScreen), findsNothing);
    // The lesson just passed is there to practise.
    expect(find.byKey(const ValueKey('tajweed-practice-rule-izhar')), findsOne);
    await tester.tap(find.byKey(const ValueKey('tajweed-practice-to-course')));
    await _settle(tester);
    expect(find.byType(TajweedCourseHomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic reads right to left; the arrow keys follow it', (
    tester,
  ) async {
    await _pump(tester, locale: 'ar', progress: _passed);
    expect(find.text('ابدأ التدريب'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('ابدأ التدريب'))),
      TextDirection.rtl,
    );
    await _begin(tester);
    expect(_text(tester, 'tajweed-practice-counter'), 'المهمة 1 من 3');
    expect(find.text('مراجعة'), findsOneWidget);
    await _tapWord(tester, 1);
    expect(_text(tester, 'tajweed-practice-feedback'), 'صحيح!');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(_text(tester, 'tajweed-practice-counter'), 'المهمة 2 من 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(_text(tester, 'tajweed-practice-counter'), 'المهمة 1 من 3');
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['ru', 'ar']) {
    testWidgets('$locale: the start, every task and the summary fit 360×740', (
      tester,
    ) async {
      await _pump(
        tester,
        locale: locale,
        size: const Size(360, 740),
        progress: _passed,
        practice: _practiced(),
      );
      expect(tester.takeException(), isNull);
      await _begin(tester);
      final next = find.byKey(const ValueKey('tajweed-practice-next'));
      for (var task = 0; task < 3; task++) {
        if (task == 0) {
          await _tapWord(tester, 2);
        } else {
          await tester.tap(_option('izhar'));
          await _settle(tester);
        }
        expect(tester.takeException(), isNull);
        expect(tester.getRect(next).right, lessThanOrEqualTo(360));
        expect(tester.getRect(next).bottom, lessThanOrEqualTo(740));
        await _next(tester);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const ValueKey('tajweed-practice-result')), findsOne);
      expect(tester.takeException(), isNull);
    });
  }
}

typedef _Harness = ({
  _FakeRepository repository,
  _MemoryPractice practice,
  _CountingSync sync,
  _Engine engine,
  AudioController audio,
});

Future<_Harness> _pump(
  WidgetTester tester, {
  String location = tajweedPracticePath,
  String locale = 'ru',
  Size size = const Size(400, 900),
  TajweedCourseProgress progress = const TajweedCourseProgress(),
  TajweedPracticeLocal practice = const TajweedPracticeLocal(),
  Map<String, Object?>? tasks,
  Set<int>? timed,
  int failures = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final document = TajweedCourseDocument.fromJson(
    locale == 'ar'
        ? _arabic(tajweedCourseDocumentJson())
        : tajweedCourseDocumentJson(),
  );
  final repository = _FakeRepository(
    tasks ?? tajweedPracticeTasksJson(),
    failures: failures,
  );
  final memory = _MemoryPractice(practice);
  final sync = _CountingSync();
  final engine = _Engine();
  final audio = AudioController(engine: engine);
  addTearDown(audio.dispose);
  var minute = 0;
  final router = GoRouter(
    initialLocation: '/tajweed',
    routes: <RouteBase>[
      GoRoute(
        path: '/tajweed',
        builder: (context, state) => const TajweedCourseHomeScreen(),
      ),
      GoRoute(
        path: tajweedPracticePath,
        builder: (context, state) => const TajweedPracticeScreen(),
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
        tajweedCourseProgressStoreProvider.overrideWithValue(
          _MemoryProgress(progress),
        ),
        tajweedProgressSyncProvider.overrideWithValue(_NoProgressSync()),
        tajweedPracticeStoreProvider.overrideWithValue(memory),
        tajweedPracticeSyncProvider.overrideWithValue(sync),
        tajweedPracticeClockProvider.overrideWithValue(
          () => _start.add(Duration(minutes: minute++)),
        ),
        tajweedCourseRecitationProvider.overrideWithValue(
          () async => 'recitation-1',
        ),
        audioRepositoryProvider.overrideWithValue(_AudioRepository(timed)),
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
    repository: repository,
    practice: memory,
    sync: sync,
    engine: engine,
    audio: audio,
  );
}

/// The fixture with the names the Arabic course has.
Map<String, Object?> _arabic(Map<String, Object?> json) {
  for (final target in (json['targets']! as Map).values) {
    (target as Map)['name'] = target['arabic_name'];
  }
  return json;
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _begin(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tajweed-practice-start')));
  await _settle(tester);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('tajweed-practice-next')));
  await _settle(tester);
}

Future<void> _tapWord(WidgetTester tester, int position) async {
  await tester.tap(find.byKey(ValueKey('tajweed-course-find-$position')));
  await _settle(tester);
}

Finder _option(String target) =>
    find.byKey(ValueKey('tajweed-practice-option-$target'));

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

String? _prompt(WidgetTester tester) =>
    _text(tester, 'tajweed-practice-prompt');

BoxDecoration _box(WidgetTester tester, String key) =>
    tester.widget<Container>(find.byKey(ValueKey(key))).decoration!
        as BoxDecoration;

/// The colour of a lit word's underline.
Color _litColor(WidgetTester tester, String key) =>
    (_box(tester, key).border! as Border).bottom.color;

/// Positions of the words lit with an underline.
List<int> _lit(
  WidgetTester tester,
  int words, {
  String prefix = 'tajweed-course-word',
}) {
  bool lit(int position) {
    final border = _box(tester, '$prefix-$position').border;
    return border is Border &&
        border.bottom.width == 2 &&
        border.top == BorderSide.none;
  }

  return [
    for (var position = 1; position <= words; position++)
      if (lit(position)) position,
  ];
}

typedef _Request = ({List<String> lessons, int seed, List<String> review});

class _FakeRepository implements TajweedCourseRepository {
  _FakeRepository(this.tasks, {this.failures = 0});

  final Map<String, Object?> tasks;
  int failures;
  final requests = <_Request>[];

  @override
  Future<List<TajweedPracticeTask>> practice(
    String slug, {
    required List<String> lessons,
    required int seed,
    List<String> review = const [],
    int count = tajweedPracticeTasks,
  }) async {
    expect(count, 8);
    requests.add((lessons: lessons, seed: seed, review: review));
    if (failures > 0) {
      failures -= 1;
      throw StateError('offline');
    }
    return parseTajweedPracticeTasks(tasks);
  }

  @override
  Future<TajweedExamplesPage> examples(
    String slug,
    String lesson, {
    required int offset,
    required int limit,
  }) async => TajweedExamplesPage.fromJson(
    tajweedCourseExamplesPage(lesson, offset: offset, limit: limit),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPractice implements TajweedPracticeStore {
  _MemoryPractice(this.local);

  TajweedPracticeLocal local;

  @override
  Future<TajweedPracticeLocal> read(String course, {accountScope}) async =>
      local;

  @override
  Future<TajweedPracticeLocal> record(
    String course,
    TajweedPracticeSession session,
  ) async => local = local.record(session);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingSync implements TajweedPracticeSync {
  var calls = 0;

  @override
  Future<TajweedPracticeLocal?> sync(String course) async {
    calls += 1;
    return null;
  }
}

class _MemoryProgress implements TajweedCourseProgressStore {
  _MemoryProgress(this.progress);

  TajweedCourseProgress progress;

  @override
  Future<TajweedCourseProgress> read(String course, {accountScope}) async =>
      progress;

  @override
  Future<TajweedCourseProgress> recordStep({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async => progress;

  @override
  Future<TajweedCourseProgress> complete({
    required String course,
    required String lesson,
    required String stepSlug,
    required String contentVersion,
  }) async => progress = TajweedCourseProgress({
    ...progress.lessons,
    lesson: TajweedLessonProgress(
      status: TajweedLessonStatus.completed,
      stepSlug: stepSlug,
      contentVersion: contentVersion,
      updatedAt: '2026-10-22T12:00:00.000Z',
    ),
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoProgressSync implements TajweedProgressSync {
  @override
  Future<TajweedCourseProgress?> sync(String course) async => null;
}

/// Word N of a timed surah plays from N s for 0.9 s; other surahs have the
/// track without timings.
class _AudioRepository implements AudioRepository {
  _AudioRepository(this.timed);

  /// Null times every surah.
  final Set<int>? timed;

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
      if (timed?.contains(surah) ?? true)
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
  final sources = <AudioSource>[];
  var speed = 1.0;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
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
  Future<void> dispose() => _states.close();
}
