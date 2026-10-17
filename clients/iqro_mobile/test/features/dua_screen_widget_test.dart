import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/dua/dua_presentation.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/dua/dua_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('Dua catalog', () {
    testWidgets('shows the localized empty state at narrow large-text layout', (
      tester,
    ) async {
      await _useNarrowLargeTextView(tester);
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[],
      );

      expect(find.text('Категории ду’а пока недоступны'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out long category data at narrow width and 2x text', (
      tester,
    ) async {
      await _useNarrowLargeTextView(tester);
      const longTitle =
          'Очень длинное название категории молитв для проверки '
          'корректного переноса текста';
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[
          DuaCategory(
            id: 'category-1',
            slug: 'long-category',
            title: longTitle,
            entryCount: 24,
            collection: 'hisn-al-muslim',
            collectionVersion: '2026-09',
            sourceNumber: 1,
          ),
        ],
        entries: (identity) async => [
          _entry(
            categoryTitle: longTitle,
            arabicText: 'دعاء',
            meaning: longTitle,
          ),
        ],
      );

      expect(find.text('Сон и пробуждение'), findsOneWidget);
      await tester.tap(find.text('Сон и пробуждение'));
      await tester.pumpAndSettle();
      expect(find.text(longTitle), findsWidgets);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders Arabic catalog and entry content right-to-left', (
      tester,
    ) async {
      const category = DuaCategory(
        id: 'category-ar',
        slug: 'morning',
        title: 'أذكار الصباح',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        collectionVersion: '2026-09',
        sourceNumber: 1,
      );
      final entry = _entry(
        categoryTitle: category.title,
        arabicText: 'اللهم بك أصبحنا وبك أمسينا',
        meaning: 'دعاء الصباح',
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('ar'),
        categories: () async => const <DuaCategory>[category],
        entries: (identity) async {
          expect(identity, category.identity);
          return <DuaEntry>[entry];
        },
      );

      await tester.tap(find.text('النوم والاستيقاظ'));
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.text(category.title))),
        TextDirection.rtl,
      );

      final arabic = tester.widget<Text>(find.text(entry.arabicText));
      expect(arabic.textDirection, TextDirection.rtl);
      expect(
        Directionality.of(tester.element(find.text(entry.arabicText))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('daily cards open source-based subsets and return to topics', (
      tester,
    ) async {
      const category = DuaCategory(
        id: 'daily',
        slug: '027-words-of-remembrance-for-morning-and-evening',
        title: 'Утром и вечером',
        entryCount: 24,
        collection: 'hisn-al-muslim',
        sourceNumber: 27,
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => [category],
        entries: (identity) async {
          expect(identity, category.identity);
          return [
            for (var number = 75; number <= 98; number++)
              _entry(
                id: 'entry-$number',
                sourceNumber: number,
                categoryTitle: category.title,
                meaning: 'Meaning $number',
                arabicText: 'نص $number',
              ),
          ];
        },
      );
      await tester.tap(find.byKey(const ValueKey('dua-topic-morning')));
      await tester.pumpAndSettle();
      expect(find.text('Утренние азкары'), findsWidgets);
      expect(find.text('Meaning 75'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Вечерние азкары'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('dua-topic-evening')));
      await tester.pumpAndSettle();
      expect(find.text('Вечерние азкары'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('debounces root search and renders server results', (
      tester,
    ) async {
      final requests = <DuaSearchQuery>[];
      final result = _entry(
        categoryTitle: 'Server category',
        arabicText: 'الرحمة',
        meaning: 'Server-only result',
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('en'),
        categories: () async => const <DuaCategory>[],
        search: (request) async {
          requests.add(request);
          return <DuaEntry>[result];
        },
      );

      await tester.enterText(find.byType(EditableText), 'm');
      await tester.pump();
      expect(
        find.text('Enter at least 2 characters to search'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, isEmpty);

      await tester.enterText(find.byType(EditableText), '  mercy  ');
      await tester.pump();
      expect(requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 349));
      expect(requests, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(requests, hasLength(1));
      expect(requests.single.query, 'mercy');
      expect(requests.single.collection, isNull);
      expect(requests.single.category, isNull);

      await tester.pumpAndSettle();
      expect(find.text('Server-only result'), findsOneWidget);
      expect(find.text('Server category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('topics are cards only, without a chapter drop-down', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[_sleepCategory],
      );

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byKey(const ValueKey('dua-topic-sleep')), findsOneWidget);
      expect(find.byType(SearchBar), findsOneWidget);
      expect(find.byKey(const ValueKey('dua-favorites')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a favourites card lists the saved du\'a and comes back', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[_sleepCategory],
        favorites: <DuaEntry>[
          _entry(
            categoryTitle: 'Перед сном',
            arabicText: 'باسمك اللهم',
            meaning: 'Saved before sleep',
          ),
        ],
      );

      final card = find.byKey(const ValueKey('dua-favorites'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Ду’а: 1')),
        findsOneWidget,
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Saved before sleep'), findsOneWidget);
      expect(find.text('Сохранённые ду’а'), findsOneWidget);

      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dua-topic-sleep')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search also offers the topics whose name matches', (
      tester,
    ) async {
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[_sleepCategory],
        entries: (identity) async => <DuaEntry>[
          _entry(
            categoryTitle: 'Перед сном',
            arabicText: 'باسمك اللهم',
            meaning: 'Chapter entry',
          ),
        ],
      );

      await tester.enterText(find.byType(EditableText), 'сон');
      await tester.pumpAndSettle();
      final match = find.byKey(const ValueKey('dua-topic-match-sleep'));
      expect(match, findsOneWidget);
      // The server found nothing, but the topic answers the search.
      expect(find.text('Подходящие ду’а не найдены'), findsNothing);

      await tester.tap(match);
      await tester.pumpAndSettle();
      expect(find.text('Сон и пробуждение'), findsWidgets);
      expect(find.text('Chapter entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a du\'a reads as one card: centred Arabic, then meaning', (
      tester,
    ) async {
      final entry = _entry(
        categoryTitle: 'Слова поминания при пробуждении',
        arabicText: 'الحمد لله الذي أحيانا',
        meaning: 'Хвала Аллаху, Который оживил нас',
      );
      await _pumpDetail(tester, load: (_) async => entry);

      expect(find.text('Слова поминания при пробуждении'), findsOneWidget);
      final arabic = tester.widget<Text>(
        find.byKey(const ValueKey('dua-arabic')),
      );
      expect(arabic.textAlign, TextAlign.center);
      expect(arabic.textDirection, TextDirection.rtl);
      final meaning = tester.widget<Text>(
        find.byKey(const ValueKey('dua-meaning')),
      );
      final context = tester.element(find.byKey(const ValueKey('dua-meaning')));
      expect(meaning.style?.color, Theme.of(context).colorScheme.primary);

      // Favourite and share sit at the foot of the card, not in the bar.
      final card = find.ancestor(
        of: find.byKey(const ValueKey('dua-arabic')),
        matching: find.byType(IqroCard),
      );
      for (final tooltip in <String>['Избранное', 'Поделиться ду’а']) {
        expect(
          find.descendant(of: card, matching: find.byTooltip(tooltip)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a topic of several chapters lists them, each opens a feed', (
      tester,
    ) async {
      const wakingCategory = DuaCategory(
        id: 'waking',
        slug: '001-upon-waking',
        title: 'СЛОВА ПОМИНАНИЯ ПРИ ПРОБУЖДЕНИИ ОТО СНА',
        entryCount: 2,
        collection: 'hisn-al-muslim',
        sourceNumber: 1,
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[
          wakingCategory,
          _sleepCategory,
        ],
        entries: (identity) async => <DuaEntry>[
          _entry(
            id: 'entry-1',
            categoryTitle: wakingCategory.title,
            arabicText:
                'بسم الله الرحمن الرحيم ﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾ (ثلاثَ مرَّاتٍ)',
            meaning: 'First',
            repetitions: 3,
          ),
          _entry(
            id: 'entry-2',
            sourceNumber: 2,
            categoryTitle: wakingCategory.title,
            arabicText: 'الحمد لله',
            meaning: 'Second',
          ),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('dua-topic-sleep')));
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey('dua-chapter-hisn-al-muslim-001-upon-waking'),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Глава 1')),
        findsOneWidget,
      );
      // Capitals from the source read in sentence case, Allah keeps His.
      expect(
        find.text('Слова поминания при пробуждении ото сна'),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Глава 1'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      final basmala = tester.widget<Text>(
        find.byKey(const ValueKey('dua-arabic')).first,
      );
      expect(basmala.data, 'بسم الله الرحمن الرحيم');

      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a repeated du\'a counts down and vibrates at the end', (
      tester,
    ) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments?.toString() ?? 'vibrate');
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
      final entry = _entry(
        categoryTitle: 'Утром',
        arabicText: 'سبحان الله',
        meaning: 'Thrice',
        repetitions: 3,
      );
      await _pumpDetail(tester, load: (_) async => entry);
      final counter = find.byKey(const ValueKey('dua-counter'));
      await tester.ensureVisible(counter);

      for (final remaining in <String>['3', '2', '1']) {
        expect(
          find.descendant(of: counter, matching: find.text(remaining)),
          findsOneWidget,
        );
        await tester.tap(counter);
        await tester.pump();
      }
      expect(
        find.descendant(
          of: counter,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      // A light tap per repetition, then a strong one and a vibration.
      expect(haptics, <String>[
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.heavyImpact',
        'vibrate',
      ]);

      await tester.tap(counter);
      await tester.pump();
      expect(
        find.descendant(of: counter, matching: find.text('3')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('searching «истихара» offers its chapter', (tester) async {
      const istikhara = DuaCategory(
        id: 'istikhara',
        slug: '026-istikharah-seeking-allah-s-counsel',
        title:
            'СЛОВА МОЛЬБЫ, ПРОИЗНОСИМЫЕ ВО ВРЕМЯ МОЛИТВЫ ИСПРАШИВАНИЯ ПОМОЩИ',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        sourceNumber: 26,
      );
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => const <DuaCategory>[istikhara],
        entries: (identity) async => <DuaEntry>[
          _entry(
            categoryTitle: istikhara.title,
            arabicText: 'اللَّهُمَّ إِنِّي أَسْتَخِيرُكَ بِعِلْمِكَ',
            meaning: 'О Аллах, я прошу Тебя помочь мне выбрать',
          ),
        ],
      );

      await tester.enterText(find.byType(EditableText), 'истихара');
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('dua-chapter-match-26'));
      expect(row, findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Глава 26'), findsOneWidget);
      expect(
        find.text('О Аллах, я прошу Тебя помочь мне выбрать'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('many matched chapters scroll with the du\'a, no overflow', (
      tester,
    ) async {
      // A short window, as with the keyboard open.
      tester.view
        ..physicalSize = const Size(360, 420)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chapters = <DuaCategory>[
        for (final number in <int>[16, 26, 63, 129])
          DuaCategory(
            id: 'chapter-$number',
            slug: 'chapter-$number',
            title: 'ИСТИНА СЛОВ ГЛАВЫ $number',
            entryCount: 1,
            collection: 'hisn-al-muslim',
            sourceNumber: number,
          ),
      ];
      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        categories: () async => chapters,
        search: (request) async => <DuaEntry>[
          _entry(
            categoryTitle: 'Мольбы',
            arabicText: 'رَبِّ اغْفِرْ لِي',
            meaning: 'Найденная мольба',
          ),
        ],
      );

      await tester.enterText(find.byType(EditableText), 'исти');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('dua-chapter-match-16')),
        findsOneWidget,
      );

      await tester.dragUntilVisible(
        find.text('Найденная мольба'),
        find.byType(Scrollable).last,
        const Offset(0, -200),
      );
      expect(find.text('Найденная мольба'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resolves a unique legacy category link across collections', (
      tester,
    ) async {
      const category = DuaCategory(
        id: 'category-legacy',
        slug: 'waking-up',
        title: 'Слова поминания при пробуждении ото сна',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        collectionVersion: '2026-09',
        sourceNumber: 1,
      );
      final entry = _entry(
        categoryTitle: category.title,
        arabicText: 'الْحَمْدُ للَّهِ',
        meaning: 'Хвала Аллаху',
      );
      DuaCategoryIdentity? requestedIdentity;

      await _pumpCatalog(
        tester,
        locale: const Locale('ru'),
        home: const DuaScreen(initialCategory: 'waking-up'),
        categories: () async => const <DuaCategory>[category],
        entries: (identity) async {
          requestedIdentity = identity;
          return <DuaEntry>[entry];
        },
      );

      expect(requestedIdentity, category.identity);
      expect(find.text(category.title), findsWidgets);
      expect(find.text(entry.meaning), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dua cold detail route', () {
    testWidgets('shows loading then a recoverable unavailable state', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      await _pumpDetail(tester, load: (id) => result.future);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      result.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Это ду’а недоступно'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses a saved fallback but keeps unverified audio disabled', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      var loadCalls = 0;
      final cached = _entry(
        categoryTitle: 'Сохранённая категория',
        arabicText: 'سبحان الله',
        meaning: 'Пречист Аллах',
        audio: const <DuaAudioAsset>[
          DuaAudioAsset(
            id: 'audio-1',
            languageCode: 'ar',
            provider: 'source',
            readerName: 'Reader',
            readerNameAr: 'القارئ',
            url: 'https://media.example.test/dua/1.mp3',
            sourceUrl: 'https://source.example.test/1',
            rightsUrl: '',
            sourceVersion: '2026-09',
          ),
        ],
      );
      await _pumpDetail(
        tester,
        load: (id) {
          loadCalls += 1;
          return result.future;
        },
        initialEntry: cached,
      );

      expect(find.text(cached.arabicText), findsOneWidget);
      expect(
        find.text(
          'Показана сохранённая копия. Аудио станет доступно после проверки '
          'актуальной версии.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);

      result.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Повторить'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(loadCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not mask an authoritative withdrawal with initial data', (
      tester,
    ) async {
      final result = Completer<DuaEntry>();
      final withdrawn = _entry(
        categoryTitle: 'Withdrawn category',
        arabicText: 'سبحان الله',
        meaning: 'Withdrawn entry',
      );
      await _pumpDetail(
        tester,
        load: (id) => result.future,
        initialEntry: withdrawn,
      );

      expect(find.text(withdrawn.arabicText), findsOneWidget);

      result.completeError(
        const ApiException(
          message: 'Not found',
          code: 'not_found',
          statusCode: 404,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(withdrawn.arabicText), findsNothing);
      expect(find.text('Это ду’а недоступно'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'clears favorite state and ignores account A completion after handoff',
    (tester) async {
      final accountScope = AccountScope.forTesting('account-a');
      final database = await _openTestDatabase(
        tester,
        accountScope: accountScope,
      );
      final repository = _DelayedFavoriteDuaRepository(database);
      final controller = AudioController(engine: _SilentAudioEngine());
      final rebuild = ValueNotifier<int>(0);
      addTearDown(controller.dispose);
      addTearDown(rebuild.dispose);
      final entry = _entry(
        categoryTitle: 'Morning',
        arabicText: 'سبحان الله',
        meaning: 'Glory be to Allah',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localDatabaseProvider.overrideWithValue(database),
            duaRepositoryProvider.overrideWithValue(repository),
            audioControllerProvider.overrideWith((ref) => controller),
          ],
          child: _TestApp(
            locale: const Locale('ru'),
            home: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, value, child) => DuaEntryScreen(entry: entry),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(repository.favoriteReads, hasLength(1));

      repository.favoriteReads.single.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pump();
      expect(repository.favoriteToggles, hasLength(1));

      accountScope.activate('account-b');
      rebuild.value += 1;
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(repository.favoriteReads, hasLength(2));

      repository.favoriteToggles.single.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      repository.favoriteReads.last.complete(false);
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same audio opened by another screen transfers ownership', (
    tester,
  ) async {
    final database = await _openTestDatabase(tester);
    final engine = _SilentAudioEngine();
    final controller = AudioController(engine: engine);
    addTearDown(controller.dispose);
    final entry = _entry(
      categoryTitle: 'Morning',
      arabicText: 'سبحان الله',
      meaning: 'Glory be to Allah',
      audio: const <DuaAudioAsset>[
        DuaAudioAsset(
          id: 'audio-owner-transfer',
          languageCode: 'ar',
          provider: 'source',
          readerName: 'Reader',
          readerNameAr: 'القارئ',
          url: 'https://media.example.test/dua/owner.mp3',
          sourceUrl: 'https://source.example.test/owner',
          rightsUrl: '',
          sourceVersion: '2026-09',
        ),
      ],
    );
    final playbackId = duaAudioPlaybackId(entry, entry.audio.single, 0);
    await controller.loadStandalone(
      id: playbackId,
      url: entry.audio.single.url,
      title: 'Existing screen',
      owner: Object(),
    );
    expect(engine.setAudioSourceCalls, 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(database),
          audioControllerProvider.overrideWith((ref) => controller),
        ],
        child: _TestApp(
          locale: const Locale('ru'),
          home: DuaEntryScreen(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    expect(engine.setAudioSourceCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _useNarrowLargeTextView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required Locale locale,
  required Future<List<DuaCategory>> Function() categories,
  Widget home = const DuaScreen(),
  Future<List<DuaEntry>> Function(DuaCategoryIdentity identity)? entries,
  Future<List<DuaEntry>> Function(DuaSearchQuery request)? search,
  List<DuaEntry> favorites = const <DuaEntry>[],
}) async {
  // Du'a cards read the account and the shared player.
  final database = await _openTestDatabase(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(database),
        audioControllerProvider.overrideWith(
          (ref) => AudioController(engine: _SilentAudioEngine()),
        ),
        activeAccountScopeKeyProvider.overrideWithValue(_reader),
        duaFavoritesProvider.overrideWith((ref, key) async => favorites),
        duaCategoriesProvider.overrideWith((ref) => categories()),
        duaEntriesByCategoryProvider.overrideWith(
          (ref, identity) =>
              entries?.call(identity) ?? Future.value(const <DuaEntry>[]),
        ),
        duaSearchProvider.overrideWith(
          (ref, request) =>
              search?.call(request) ?? Future.value(const <DuaEntry>[]),
        ),
      ],
      child: _TestApp(
        locale: locale,
        textScaler: tester.view.physicalSize.width == 320
            ? const TextScaler.linear(2)
            : TextScaler.noScaling,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required Future<DuaEntry> Function(String id) load,
  DuaEntry? initialEntry,
}) async {
  final database = await _openTestDatabase(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(database),
        duaEntryProvider.overrideWith((ref, id) => load(id)),
        audioControllerProvider.overrideWith(
          (ref) => AudioController(engine: _SilentAudioEngine()),
        ),
      ],
      child: _TestApp(
        locale: const Locale('ru'),
        home: DuaEntryRouteScreen(
          entryId: '0194f11e-972b-7b07-a772-5b7651ab78ea',
          initialEntry: initialEntry,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.locale,
    required this.home,
    this.textScaler = TextScaler.noScaling,
  });

  final Locale locale;
  final Widget home;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: IqroTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: home,
    );
  }
}

const AccountScopeKey _reader = (userId: 'reader', epoch: 1);

const _sleepCategory = DuaCategory(
  id: 'sleep',
  slug: '028-what-to-say-before-sleeping',
  title: 'Перед сном',
  entryCount: 14,
  collection: 'hisn-al-muslim',
  sourceNumber: 28,
);

DuaEntry _entry({
  String id = '0194f11e-972b-7b07-a772-5b7651ab78ea',
  int sourceNumber = 1,
  required String categoryTitle,
  required String arabicText,
  required String meaning,
  List<DuaAudioAsset> audio = const <DuaAudioAsset>[],
  int repetitions = 1,
}) => DuaEntry(
  id: id,
  sourceNumber: sourceNumber,
  collection: 'hisn-al-muslim',
  collectionVersion: '2026-09',
  categoryTitle: categoryTitle,
  categorySlug: 'morning',
  arabicText: arabicText,
  meaning: meaning,
  transliteration: '',
  repetitions: repetitions,
  sourceLabel: 'Hisn al-Muslim',
  audio: audio,
);

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

Future<LocalDatabase> _openTestDatabase(
  WidgetTester tester, {
  AccountScope? accountScope,
}) async {
  final database = (await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(database.close));
  return LocalDatabase.forTesting(database, accountScope: accountScope);
}

class _DelayedFavoriteDuaRepository extends DuaRepository {
  _DelayedFavoriteDuaRepository(LocalDatabase database)
    : super(database: database, remote: _UnusedDuaRemote());

  final List<Completer<bool>> favoriteReads = <Completer<bool>>[];
  final List<Completer<bool>> favoriteToggles = <Completer<bool>>[];

  @override
  Future<bool> isFavorite(
    DuaEntry entry, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = Completer<bool>();
    favoriteReads.add(result);
    return result.future;
  }

  @override
  Future<bool> toggleFavorite(
    DuaEntry entry, {
    AccountScopeSnapshot? accountScope,
  }) {
    final result = Completer<bool>();
    favoriteToggles.add(result);
    return result.future;
  }
}

class _UnusedDuaRemote implements DuaRemoteGateway {
  @override
  Uri get apiBaseUri => Uri.parse('https://iqro.forum/api/v1');

  Never _unused() => throw UnsupportedError('Not used by this widget test');

  @override
  Future<Object?> categories(String locale) => _unused();

  @override
  Future<Object?> collections(String locale) => _unused();

  @override
  Future<Object?> entries(
    String locale, {
    String? collection,
    String? category,
    String? query,
    String? cursor,
    required int pageSize,
  }) => _unused();

  @override
  Future<Object?> entry(String locale, String id) => _unused();

  @override
  Future<Object?> favorites(
    String locale, {
    AccountScopeSnapshot? accountScope,
  }) => _unused();

  @override
  Future<Object?> resolveEntry(
    String locale, {
    required String collection,
    required int sourceNumber,
  }) => _unused();

  @override
  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite, {
    AccountScopeSnapshot? accountScope,
  }) => _unused();
}
