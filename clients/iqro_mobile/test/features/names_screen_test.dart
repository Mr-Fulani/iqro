import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/courses/account_progress_sync.dart';
import 'package:iqro_mobile/features/courses/course_progress_store.dart';
import 'package:iqro_mobile/features/names/names_models.dart';
import 'package:iqro_mobile/features/names/names_repository.dart';
import 'package:iqro_mobile/features/names/names_screen.dart';
import 'package:iqro_mobile/features/names/names_sound.dart';
import 'package:iqro_mobile/features/tajweed_course/tajweed_course_progress.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

import 'names_test_data.dart';

void main() {
  testWidgets(
    'a tap on the centre moves to the next name with a click and the reciter',
    (tester) async {
      final harness = await _pump(tester);

      expect(_readout('Ар-Рахман'), findsOneWidget);
      expect(_seen(tester), '0 из 4');

      await tester.tapAt(tester.getCenter(_dial));
      await tester.pumpAndSettle();

      expect(_readout('Ар-Рахим'), findsOneWidget);
      expect(find.byKey(const ValueKey('names-card')), findsNothing);
      expect(harness.click.count, 1);
      // The needle stopped on the name: it is seen, and the reciter says it.
      expect(harness.voice.played, <String>['ar-rahim@ar']);
      expect(_seen(tester), '1 из 4');
      expect(harness.store.progress.lessons['ar-rahim']!.completed, isFalse);

      await tester.tapAt(tester.getCenter(_dial));
      await tester.pumpAndSettle();
      // One click player and one voice serve the whole screen.
      expect(harness.click.count, 2);
      expect((harness.click.made, harness.voice.made), (1, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a finger turns the wheel and it comes to rest on a name', (
    tester,
  ) async {
    final harness = await _pump(tester, disableAnimations: false);
    final centre = tester.getCenter(_dial);
    final radius = tester.getSize(_dial).width * .35;

    // From twelve o'clock to three: a quarter of four names is one name.
    final gesture = await tester.startGesture(centre + Offset(0, -radius));
    for (var step = 1; step <= 9; step++) {
      final angle = -1.5708 + 1.5708 * step / 9;
      await gesture.moveTo(
        centre + Offset.fromDirection(angle, radius),
        timeStamp: Duration(milliseconds: 30 * step),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(_readout('Ар-Рахим'), findsOneWidget);
    expect(harness.voice.played, <String>['ar-rahim@ar']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the name under the wheel opens the card', (tester) async {
    final harness = await _pump(tester);
    await tester.tapAt(tester.getCenter(_dial));
    await tester.tapAt(tester.getCenter(_dial));
    await tester.pumpAndSettle();
    expect(_readout('Малик аль-Мульк'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('names-readout')));
    await tester.tap(find.byKey(const ValueKey('names-readout')));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('names-card'));
    expect(card, findsOneWidget);
    expect(_title(tester), 'Малик аль-Мульк');
    expect(
      find.descendant(of: card, matching: find.text('Имя 3 из 4')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Источник: Пример: книга толкований'),
      ),
      findsOneWidget,
    );
    // Two words of the ayah: a link to the reader, no «Слушать».
    expect(find.byKey(const ValueKey('names-listen')), findsNothing);
    expect(find.text('Сура 3, аят 26'), findsOneWidget);

    // «Выучено» is its own mark and can be taken back.
    await tester.tap(find.text('Отметить выученным'));
    await tester.pumpAndSettle();
    expect(harness.store.progress.isDone('malik-al-mulk'), isTrue);
    expect(find.text('Выучено'), findsOneWidget);
    // Once when the screen opened, once for the mark.
    expect(harness.sync.synced, <String>[
      'names:asma-al-husna',
      'names:asma-al-husna',
    ]);
    await tester.tap(find.text('Выучено'));
    await tester.pumpAndSettle();
    expect(harness.store.progress.isDone('malik-al-mulk'), isFalse);
    expect(harness.store.progress.lessons.containsKey('malik-al-mulk'), isTrue);

    // The card walks to the neighbours and the wheel follows.
    await tester.ensureVisible(find.byKey(const ValueKey('names-card-next')));
    await tester.tap(find.byKey(const ValueKey('names-card-next')));
    await tester.pumpAndSettle();
    expect(_title(tester), 'Аль-Джамиль');
    expect(find.byKey(const ValueKey('names-ayah')), findsNothing);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('другая книга для этого имени'),
      ),
      findsOneWidget,
    );
    expect(_number(tester), '4');

    await tester.ensureVisible(find.byKey(const ValueKey('names-card-next')));
    await tester.tap(find.byKey(const ValueKey('names-card-next')));
    await tester.pumpAndSettle();
    expect(_title(tester), 'Ар-Рахман');
    final listen = find.byKey(const ValueKey('names-listen'));
    await tester.ensureVisible(listen);
    harness.voice.played.clear();
    await tester.tap(listen);
    await tester.pump();
    expect(harness.voice.played, <String>['ar-rahman@ru']);

    // «В Коране» opens the ayah in the reader.
    await tester.ensureVisible(find.byKey(const ValueKey('names-ayah')));
    await tester.tap(find.byKey(const ValueKey('names-ayah')));
    await tester.pumpAndSettle();
    expect(find.text('reader 55 ayah 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the sound off the wheel is silent', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('names-sound')));
    await tester.pump();

    await tester.tapAt(tester.getCenter(_dial));
    await tester.pumpAndSettle();

    expect(_readout('Ар-Рахим'), findsOneWidget);
    expect(harness.click.count, 0);
    expect(harness.voice.played, isEmpty);
    expect(_seen(tester), '1 из 4');
  });

  testWidgets('labels switch to Arabic; the Arabic interface has one script', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('names-labels')), findsOneWidget);
    await tester.tap(find.text('عربي'));
    await tester.pumpAndSettle();
    // With Arabic labels the wheel runs the other way; the centre still
    // moves to the next name.
    await tester.tapAt(tester.getCenter(_dial));
    await tester.pumpAndSettle();
    expect(_readout('Ар-Рахим'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final json = namesFixture();
    for (final name in json['names']! as List) {
      (name as Map)['transliteration'] = '';
    }
    await _pump(tester, locale: 'ar', document: NamesDocument.fromJson(json));
    expect(find.byKey(const ValueKey('names-labels')), findsNothing);
    expect(find.text('Ар-Рахман'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the screen fits a small phone with large text, light and dark', (
    tester,
  ) async {
    for (final dark in <bool>[false, true]) {
      for (final locale in <String>['ru', 'en', 'tr', 'ar']) {
        await _pump(
          tester,
          locale: locale,
          dark: dark,
          textScale: 1.8,
          size: const Size(360, 640),
        );
        await tester.tapAt(tester.getCenter(_dial));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale dark=$dark');
      }
    }
  });

  testWidgets('says the section is being prepared until a list is published', (
    tester,
  ) async {
    await _pump(tester, unavailable: true);

    expect(find.byKey(const ValueKey('names-soon')), findsOneWidget);
    expect(find.text('Раздел готовится'), findsOneWidget);
    expect(_dial, findsNothing);
  });
}

final _dial = find.byKey(const ValueKey('names-dial'));

Finder _readout(String name) => find.descendant(
  of: find.byKey(const ValueKey('names-readout')),
  matching: find.text(name),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

String _seen(WidgetTester tester) => _text(tester, 'names-seen');

String _number(WidgetTester tester) => _text(tester, 'names-number');

String _title(WidgetTester tester) => _text(tester, 'names-card-title');

typedef _Harness = ({_Store store, _Click click, _Voice voice, _Sync sync});

Future<_Harness> _pump(
  WidgetTester tester, {
  String locale = 'ru',
  bool dark = false,
  bool disableAnimations = true,
  bool unavailable = false,
  double textScale = 1,
  Size size = const Size(390, 844),
  NamesDocument? document,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store();
  final click = _Click();
  final voice = _Voice();
  final sync = _Sync();
  final audio = AudioController(engine: _SilentAudioEngine());
  final router = GoRouter(
    initialLocation: '/names',
    routes: <RouteBase>[
      GoRoute(path: '/names', builder: (_, _) => const NamesScreen()),
      GoRoute(
        path: '/reader/:surah',
        builder: (_, state) => Scaffold(
          body: Text(
            'reader ${state.pathParameters['surah']} '
            'ayah ${state.uri.queryParameters['ayah']}',
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        namesProvider.overrideWith((ref, slug) async {
          if (unavailable) throw NamesUnavailable(slug);
          return document ?? namesDocument();
        }),
        namesProgressStoreProvider.overrideWithValue(store),
        activeAccountScopeKeyProvider.overrideWithValue((
          userId: 'test-owner',
          epoch: 1,
        )),
        accountProgressSyncProvider.overrideWithValue(sync),
        namesClickProvider.overrideWith((ref) {
          click.made += 1;
          return click;
        }),
        namesVoiceProvider.overrideWith((ref) {
          voice.made += 1;
          return voice;
        }),
        audioControllerProvider.overrideWith((ref) => audio),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: dark ? IqroTheme.dark() : IqroTheme.light(),
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
  return (store: store, click: click, voice: voice, sync: sync);
}

/// Widget tests cannot wait for the database isolate.
class _Store implements CourseProgressStore {
  var progress = const CourseProgress();

  @override
  Future<CourseProgress> read(String course) async => progress;

  Future<CourseProgress> _set(String lesson, String version, bool done) async {
    return progress = CourseProgress({
      ...progress.lessons,
      lesson: TajweedLessonProgress(
        status: done
            ? TajweedLessonStatus.completed
            : TajweedLessonStatus.inProgress,
        stepSlug: '',
        contentVersion: version,
        updatedAt: '2026-11-12T10:00:00.000Z',
      ),
    });
  }

  @override
  Future<CourseProgress> recordOpen({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _set(lesson, contentVersion, progress.isDone(lesson));

  @override
  Future<CourseProgress> markDone({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _set(lesson, contentVersion, true);

  @override
  Future<CourseProgress> unmark({
    required String course,
    required String lesson,
    required String contentVersion,
  }) => _set(lesson, contentVersion, false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements AccountProgressSync {
  final synced = <String>[];

  @override
  Future<bool> sync(String kind, String course) async {
    synced.add('$kind:$course');
    return true;
  }
}

class _Click implements NamesClick {
  var count = 0;

  /// How many times the screen asked for a new one.
  var made = 0;

  @override
  void play() => count += 1;

  @override
  Future<void> dispose() async {}
}

class _Voice extends ChangeNotifier implements NamesVoice {
  final played = <String>[];
  var made = 0;

  @override
  final owner = Object();

  @override
  String? get missing => null;

  @override
  String? get playing => null;

  @override
  bool canSay(DivineName name) => name.hasVoice || name.slug == 'al-jamil';

  @override
  Future<void> play(
    DivineName name, {
    required String album,
    required String language,
  }) async {
    if (canSay(name)) played.add('${name.slug}@$language');
  }

  @override
  Future<void> stop() async {}
}

class _SilentAudioEngine implements IqroAudioEngine {
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
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
