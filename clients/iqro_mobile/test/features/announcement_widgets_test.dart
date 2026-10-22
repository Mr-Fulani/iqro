import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/announcements/announcement_bubble.dart';
import 'package:iqro_mobile/features/announcements/announcement_controller.dart';
import 'package:iqro_mobile/features/announcements/announcement_logic.dart';
import 'package:iqro_mobile/features/announcements/announcement_parts.dart';
import 'package:iqro_mobile/features/announcements/news_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'announcement_test_data.dart';

final _bubble = find.byKey(const ValueKey('announcement-bubble'));
final _dialog = find.byKey(const ValueKey('announcement-dialog'));

Future<void> _pump(
  WidgetTester tester, {
  required FakeAnnouncementRepository repository,
  String location = '/',
  Locale locale = const Locale('ru'),
  bool reduced = true,
  double textScale = 1,
  AuthSession? session,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const _Home()),
      // Home kept alive under another tab.
      GoRoute(
        path: '/hidden',
        builder: (context, state) =>
            const Visibility.maintain(visible: false, child: _Home()),
      ),
      GoRoute(path: '/news', builder: (context, state) => const NewsScreen()),
      GoRoute(
        path: '/audio/reciter/:id',
        builder: (context, state) => Scaffold(
          body: Text(
            'RECITER ${state.pathParameters['id']} '
            'play=${state.uri.queryParameters['play']}',
          ),
        ),
      ),
      GoRoute(
        path: '/prayer',
        builder: (context, state) =>
            Scaffold(body: Text('PRAYER ${state.uri.query}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        announcementRepositoryProvider.overrideWithValue(repository),
        sessionProvider.overrideWith((ref) => FakeSessionController(session)),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            fallbackDownloadUrl: 'https://iqro.forum',
            environment: 'production',
          ),
        ),
        announcementImageProvider.overrideWithValue((_) => testImageProvider),
      ],
      child: MaterialApp.router(
        theme: IqroTheme.light(),
        routerConfig: router,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) await _settle(tester, reduced: reduced);
}

/// Lets the post-frame loads finish; a moving bubble never settles.
Future<void> _settle(WidgetTester tester, {bool reduced = true}) async {
  if (reduced) {
    await tester.pumpAndSettle();
    return;
  }
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('no bubble when there is nothing new', (tester) async {
    final repository = FakeAnnouncementRepository();
    await _pump(tester, repository: repository);
    expect(repository.activeRequests, 1);
    expect(_bubble, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one bubble carries several announcements as pages', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = FakeAnnouncementRepository(
      active: [testAnnouncement(), featureAnnouncement()],
    );
    await _pump(tester, repository: repository);

    expect(_bubble, findsOneWidget);
    // Large enough to catch the eye; the counter is a badge, not a dot.
    expect(tester.getSize(_bubble), const Size(68, 68));
    expect(find.text('2'), findsOneWidget);
    final badge = tester.getSize(
      find.ancestor(of: find.text('2'), matching: find.byType(Container)),
    );
    expect(badge.height, 22);
    expect(badge.width, greaterThanOrEqualTo(22));
    // It starts at the top end of the page, below the top bar.
    final bubble = tester.getRect(_bubble);
    expect(bubble.top, greaterThan(tester.getRect(find.byType(AppBar)).bottom));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Новое: 2. Открыть')),
      isSemantics(
        label: 'Новое: 2. Открыть',
        isButton: true,
        hasTapAction: true,
      ),
    );
    // Top end of the home screen.
    expect(tester.getCenter(_bubble).dx, greaterThan(300));
    expect(repository.events, [
      '$announcementIdA:bubble:impression:1',
      '$announcementIdB:bubble:impression:1',
    ]);

    await tester.tap(_bubble);
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(find.text('Что нового · 1 из 2'), findsOneWidget);
    expect(find.text('Новый чтец: Ясир ад-Даусари'), findsOneWidget);
    // The bubble hides while its window is open.
    expect(find.text('2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('announcement-next')));
    await tester.pumpAndSettle();
    expect(find.text('Что нового · 2 из 2'), findsOneWidget);
    expect(find.text('Компас Киблы'), findsOneWidget);
    expect(find.text('Откройте раздел'), findsOneWidget);

    // Back by a swipe toward the end of the line.
    await tester.fling(_dialog, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Что нового · 1 из 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('announcement-close')));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    // Both pages were seen: read, so the bubble is gone; a guest sends no
    // receipts, only anonymous counters.
    expect(_bubble, findsNothing);
    expect(repository.sentReceipts, isEmpty);
    expect(
      repository.events,
      containsAll(<String>[
        '$announcementIdA:bubble:open:1',
        '$announcementIdB:bubble:open:1',
      ]),
    );
    expect(repository.stored.read.keys, [announcementIdA, announcementIdB]);
    semantics.dispose();
  });

  testWidgets('a page not seen keeps the bubble for later', (tester) async {
    final repository = FakeAnnouncementRepository(
      active: [testAnnouncement(), featureAnnouncement()],
    );
    await _pump(tester, repository: repository, session: testSession());
    await tester.tap(_bubble);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('announcement-close')));
    await tester.pumpAndSettle();
    expect(_bubble, findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(repository.sentReceipts, [
      <String, Object?>{'id': announcementIdA, 'read': true, 'wave': 1},
    ]);
  });

  testWidgets('«Listen» opens the reciter in the app player', (tester) async {
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: repository);
    await tester.tap(_bubble);
    await tester.pumpAndSettle();
    expect(find.text('Послушать'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('announcement-action')));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(find.text('RECITER r1 play=1'), findsOneWidget);
    expect(repository.events, contains('$announcementIdA:bubble:click:1'));
  });

  testWidgets('the bubble floats and pops; reduce motion keeps it still', (
    tester,
  ) async {
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: repository, reduced: false);
    expect(tester.hasRunningAnimations, isTrue);
    // The first sight of a visit rises in, then bobs.
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: _bubble, matching: find.byType(Opacity)).first,
        )
        .opacity;
    await tester.pumpWidget(const SizedBox());
    final rising = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: rising, reduced: false, settle: false);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), lessThan(1));
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(), 1);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.tap(_bubble);
    // The pop plays first, then the window grows out of the bubble.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_dialog, findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_dialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('announcement-close')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_bubble, findsNothing);
    // Let the button's ripple fade: only the bubble's motion may run forever.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(const SizedBox());
    final still = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: still);
    expect(_bubble, findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(_bubble);
    await tester.pump();
    expect(_dialog, findsOneWidget);
  });

  testWidgets('Arabic reads right to left, with large text', (tester) async {
    final repository = FakeAnnouncementRepository(
      active: [
        testAnnouncement(<String, Object?>{
          'title': 'قارئ جديد',
          'summary': 'جميع السور الـ114.',
        }),
        featureAnnouncement(),
      ],
    );
    await _pump(
      tester,
      repository: repository,
      locale: const Locale('ar'),
      textScale: 2,
    );
    expect(tester.getCenter(_bubble).dx, lessThan(100));
    await tester.tap(_bubble);
    await tester.pumpAndSettle();
    expect(find.text('ما الجديد · 1 من 2'), findsOneWidget);
    // Swiping toward the start of an Arabic line (to the right) turns on.
    await tester.fling(_dialog, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('ما الجديد · 2 من 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('announcement-action')),
      200,
      scrollable: find.descendant(
        of: _dialog,
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bubble drifts over home, never under the bars', (
    tester,
  ) async {
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: repository, reduced: false);
    // Past the rise and the two bobs.
    await tester.pump(const Duration(seconds: 2));
    final screen = Offset.zero & tester.view.physicalSize / 2.75;
    final bar = tester.getRect(find.byType(AppBar));
    final navigation = tester.getRect(find.byType(NavigationBar));
    final centres = <Offset>{};
    var elapsed = 0;
    for (final seconds in <int>[0, 3, 5, 8, 13, 21, 34, 55, 89, 144]) {
      // In half-second frames, as the screen would draw it.
      for (; elapsed < seconds * 2; elapsed++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final rect = tester.getRect(_bubble);
      expect(rect.overlaps(bar), isFalse, reason: 'over the top bar at $rect');
      expect(
        rect.overlaps(navigation),
        isFalse,
        reason: 'over the navigation at $rect',
      );
      expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
      expect(screen.contains(rect.bottomRight), isTrue, reason: '$rect');
      // Kept to the upper half, clear of the player and bottom buttons.
      expect(rect.center.dy, lessThan(screen.height * .6));
      centres.add(rect.center);
    }
    expect(centres.length, greaterThan(5), reason: 'it should move');
    final xs = centres.map((centre) => centre.dx);
    expect(
      xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
      greaterThan(screen.width * .3),
    );
  });

  testWidgets('reduce motion keeps the bubble in place', (tester) async {
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: repository);
    final before = tester.getRect(_bubble);
    await tester.pump(const Duration(seconds: 20));
    expect(tester.getRect(_bubble), before);
  });

  testWidgets('focus from the keyboard or a screen reader stops the drift', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(tester, repository: repository, reduced: false);
    Future<void> advance(int seconds) async {
      for (var frame = 0; frame < seconds * 2; frame++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    await advance(5);
    final node = find.semantics.byLabel('Новое: 1. Открыть');
    tester.semantics.didGainAccessibilityFocus(node);
    await tester.pump();
    final held = tester.getRect(_bubble);
    await advance(6);
    expect(tester.getRect(_bubble), held);
    tester.semantics.didLoseAccessibilityFocus(node);
    await advance(3);
    expect(tester.getRect(_bubble), isNot(held));

    // The bubble's own focus, as Tab from a keyboard would give it.
    Focus.of(
      tester.element(
        find.descendant(of: _bubble, matching: find.byType(RotationTransition)),
      ),
    ).requestFocus();
    await tester.pump();
    final focused = tester.getRect(_bubble);
    await advance(6);
    expect(tester.getRect(_bubble), focused);
    semantics.dispose();
  });

  testWidgets('a bubble under another tab is neither counted nor moving', (
    tester,
  ) async {
    final repository = FakeAnnouncementRepository(active: [testAnnouncement()]);
    await _pump(
      tester,
      repository: repository,
      location: '/hidden',
      reduced: false,
    );
    expect(repository.activeRequests, 1);
    expect(repository.events, isEmpty);
    expect(repository.stored.bubble, isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a fundraising announcement never rides the bubble', (
    tester,
  ) async {
    final repository = FakeAnnouncementRepository(
      active: [
        testAnnouncement(<String, Object?>{'kind': 'fundraising'}),
      ],
    );
    await _pump(tester, repository: repository);
    expect(_bubble, findsNothing);
  });

  testWidgets('the feed keeps read news, marks unread and pages on', (
    tester,
  ) async {
    final read = featureAnnouncement();
    final repository = FakeAnnouncementRepository(
      pages: <String?, AnnouncementFeedPage>{
        null: AnnouncementFeedPage(
          nextCursor: 'next',
          results: [testAnnouncement(), read],
        ),
      },
    );
    repository.stored = markRead(
      const AnnouncementLocalState(),
      read.id,
      DateTime.utc(2026, 10, 21),
    );
    repository.nextPage = AnnouncementFeedPage(
      nextCursor: null,
      results: [
        testAnnouncement(<String, Object?>{
          'id': announcementIdC,
          'kind': 'general',
          'title': 'Обновили приложение',
          'action': <String, Object?>{
            'type': 'none',
            'label': '',
            'web_path': null,
            'app_route': null,
            'external_url': null,
          },
        }),
      ],
    );
    await _pump(tester, repository: repository, location: '/news');

    for (final label in <String>[
      'Все',
      'Чтецы',
      'Функции',
      'Содержание',
      'Приложение',
      'Общее',
    ]) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    // Fundraising is a site-only kind.
    expect(find.text('Проект'), findsNothing);
    expect(find.text('Компас Киблы'), findsOneWidget);
    expect(find.byKey(const ValueKey('news-unread')), findsOneWidget);
    expect(find.text('21 октября 2026 г.'), findsNWidgets(2));

    await tester.tap(find.text('Как пользоваться'));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(find.text('Что нового'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('announcement-close')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Показать ещё'), 200);
    await tester.ensureVisible(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Обновили приложение'), findsOneWidget);
    expect(repository.feedRequests, ['all:', 'all:next']);

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Чтецы'));
    await tester.pumpAndSettle();
    expect(repository.feedRequests.last, 'reciter:');
    expect(find.text('Пока новостей нет.'), findsOneWidget);
  });

  testWidgets('the feed opens the reciter and works offline', (tester) async {
    final repository = FakeAnnouncementRepository(
      pages: <String?, AnnouncementFeedPage>{
        null: AnnouncementFeedPage(
          nextCursor: null,
          results: [testAnnouncement()],
        ),
      },
    )..fromCache = true;
    await _pump(tester, repository: repository, location: '/news');
    expect(
      find.text('Нет сети — показываем сохранённые данные'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Послушать'));
    await tester.pumpAndSettle();
    expect(find.text('RECITER r1 play=1'), findsOneWidget);
    expect(repository.events, contains('$announcementIdA:feed:click:1'));
    expect(repository.stored.read.keys, [announcementIdA]);
  });

  testWidgets('the feed reports a failure without a saved copy', (
    tester,
  ) async {
    final repository = FakeAnnouncementRepository()..offline = true;
    await _pump(tester, repository: repository, location: '/news');
    expect(
      find.text('Не удалось загрузить новости. Попробуйте позже.'),
      findsOneWidget,
    );
    repository
      ..offline = false
      ..pages = <String?, AnnouncementFeedPage>{
        null: AnnouncementFeedPage(
          nextCursor: null,
          results: [testAnnouncement()],
        ),
      };
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Новый чтец: Ясир ад-Даусари'), findsOneWidget);
  });
}

/// Home as the app shows it: its top bar inside, the bottom navigation of the
/// shell outside, with the page extending under it.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: AnnouncementBubbleLayer(
      child: Scaffold(
        appBar: IqroTopBar(
          title: 'IQRO',
          actions: <Widget>[
            IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
            const SizedBox(width: 6),
          ],
        ),
        body: const SizedBox.expand(),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      destinations: const <Widget>[
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.grid_view), label: 'More'),
      ],
    ),
  );
}
