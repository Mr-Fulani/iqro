// The memorization list: the repository's list calls, the Mushaf "Learn"
// sheet and the list card above the practice.
//
// Screenshots for the pull request, on the Redmi Note 7 size:
//
//   flutter test test/features/memorization_list_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Without SCREENSHOT_DIR the screenshot tests are skipped.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/memorization/memorization_list_card.dart';
import 'package:iqro_mobile/features/memorization/memorization_repository.dart';
import 'package:iqro_mobile/features/memorization/memorize_ayah_sheet.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _size = Size(1080, 2340); // Redmi Note 7
const _pixelRatio = 2.75;
final _boundary = GlobalKey();

void main() {
  setUpAll(() async {
    if (_directory.isNotEmpty) await _loadFonts();
  });

  group('repository', () {
    test('reads the list and the memorized count from the dashboard', () async {
      final remote = _Remote();
      final dashboard = await _repository(remote).load();

      expect(dashboard.revision, 3);
      expect(dashboard.activeItem?.startAyah.ayah, 1);
      expect(dashboard.queuedItems.single.endAyah.ayah, 12);
      expect(dashboard.memorizedAyahCount, 4);
    });

    test('adds a selection with mode, revision and timezone', () async {
      final remote = _Remote();
      final repository = _repository(remote);
      await repository.load();

      final added = await repository.addSelection(
        const MemorizationSelection(
          startSurah: 2,
          startAyah: 6,
          endSurah: 2,
          endAyah: 8,
        ),
        mode: MemorizationAddMode.extend,
        baseRevision: 3,
        recitationId: 'recitation-1',
      );

      expect(remote.added?['mode'], 'extend');
      expect(remote.added?['start_surah'], 2);
      expect(remote.added?['end_ayah'], 8);
      expect(remote.added?['base_revision'], 3);
      expect(remote.added?['source'], 'mushaf');
      expect(remote.added?['recitation_id'], 'recitation-1');
      expect(remote.added?['timezone_name'], 'Europe/Istanbul');
      expect(added.result, 'extended');
      expect(added.dashboard.activeItem?.endAyah.ayah, 8);
      expect(added.dashboard.plan?.endAyah.ayah, 8);
      expect(added.dashboard.revision, 4);
    });

    test('marking memorized and removing send the list revision', () async {
      final remote = _Remote();
      final repository = _repository(remote);
      final dashboard = await repository.load();

      await repository.updateItem(
        dashboard.activeItem!.id,
        MemorizationItemStatus.memorized,
        baseRevision: dashboard.revision,
      );
      await repository.removeItem(
        dashboard.queuedItems.single.id,
        baseRevision: 4,
      );

      expect(remote.updated, ('item-active', 'memorized', 3));
      expect(remote.removed, ('item-queued', 4));
    });

    test('preview tells the menu which choice to offer', () async {
      final remote = _Remote()..previewPayload = _preview('extendable');
      final preview = await _repository(remote).preview(
        const MemorizationSelection(
          startSurah: 2,
          startAyah: 6,
          endSurah: 2,
          endAyah: 6,
        ),
      );

      expect(preview.state, MemorizationPreviewState.extendable);
      expect(preview.extendEndAyah, 6);
      expect(remote.previewQuery?['start_ayah'], 6);
    });
  });

  group('Mushaf learn sheet', () {
    testWidgets('an empty list starts the ayah and opens memorization', (
      tester,
    ) async {
      final remote = _Remote()..previewPayload = _preview('empty');
      await _pumpSheet(tester, remote);

      expect(remote.added?['mode'], 'now');
      expect(remote.added?['start_ayah'], 6);
      expect(remote.added?['end_ayah'], 6);
      expect(find.text('MEMORIZATION'), findsOneWidget);
    });

    testWidgets('an ayah already in the list offers to open it', (
      tester,
    ) async {
      final remote = _Remote()..previewPayload = _preview('duplicate');
      await _pumpSheet(tester, remote);

      expect(find.text('Уже в списке: 2:1–5.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('memorize-open')));
      await tester.pumpAndSettle();

      expect(remote.added, isNull);
      expect(find.text('MEMORIZATION'), findsOneWidget);
    });

    testWidgets('ayahs right after the range offer extend or queue', (
      tester,
    ) async {
      final remote = _Remote()..previewPayload = _preview('extendable');
      await _pumpSheet(tester, remote);

      expect(find.text('Расширить до 2:1–6'), findsOneWidget);
      expect(find.text('Отдельно в очередь'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('memorize-extend')));
      await tester.pumpAndSettle();

      expect(remote.added?['mode'], 'extend');
      expect(find.text('MEMORIZATION'), findsOneWidget);
    });

    testWidgets('otherwise queueing is the default and stays in the Mushaf', (
      tester,
    ) async {
      final remote = _Remote()
        ..previewPayload = _preview('choose')
        ..addResult = 'queued';
      await _pumpSheet(tester, remote);

      expect(find.text('Учить сейчас'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('memorize-queue')));
      await tester.pumpAndSettle();

      expect(remote.added?['mode'], 'queue');
      expect(find.text('Добавлено в очередь заучивания.'), findsOneWidget);
      expect(find.text('MEMORIZATION'), findsNothing);
    });
  });

  group('list card', () {
    testWidgets('shows the current range, the queue and memorized ayahs', (
      tester,
    ) async {
      MemorizationItem? memorized;
      await _pumpCard(
        tester,
        _dashboard(),
        onMemorized: (item) {
          memorized = item;
        },
      );

      expect(find.text('Аль-Бакара, 1–5'), findsOneWidget);
      expect(find.text('Аль-Бакара, 10–12'), findsOneWidget);
      expect(find.text('Выучено аятов: 4'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('memorization-list-memorized')),
      );
      expect(memorized?.id, 'item-active');
    });

    testWidgets('after the current range is memorized the next is offered', (
      tester,
    ) async {
      MemorizationItem? started;
      await _pumpCard(
        tester,
        _dashboard(activeMemorized: true),
        onStart: (item) => started = item,
      );

      expect(
        find.text('Следующий: Аль-Бакара, 10–12 — начать?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('memorization-list-begin')));
      expect(started?.id, 'item-queued');
    });
  });

  group('screenshots', () {
    for (final state in ['choose', 'extendable', 'duplicate']) {
      testWidgets('sheet $state', (tester) async {
        await _pumpSheet(
          tester,
          _Remote()..previewPayload = _preview(state),
          screenshot: true,
        );
        await _capture(tester, 'app-memorize-sheet-$state-ru');
      }, skip: _directory.isEmpty);
    }

    testWidgets('list card', (tester) async {
      await _pumpCard(tester, _dashboard(), screenshot: true);
      await _capture(tester, 'app-memorization-list-ru');
    }, skip: _directory.isEmpty);

    testWidgets('list card next', (tester) async {
      await _pumpCard(
        tester,
        _dashboard(activeMemorized: true),
        screenshot: true,
      );
      await _capture(tester, 'app-memorization-list-next-ru');
    }, skip: _directory.isEmpty);
  });
}

MemorizationRepository _repository(_Remote remote) => MemorizationRepository(
  database: _MemoryDatabase(),
  remote: remote,
  timezoneLoader: () async => 'Europe/Istanbul',
);

List<Override> _overrides(_Remote remote) {
  final repository = _repository(remote);
  return <Override>[
    memorizationRepositoryProvider.overrideWithValue(repository),
    memorizationProvider.overrideWith(
      (ref) => MemorizationController(
        repository,
        database: _MemoryDatabase(),
        accountScope: _MemoryDatabase.scope,
      ),
    ),
    appPreferencesProvider.overrideWith((ref) => _Preferences()),
    quranCatalogProvider.overrideWith(
      (ref) async => const QuranCatalog(
        surahs: <Surah>[
          Surah(
            id: 'surah-2',
            number: 2,
            nameAr: 'البقرة',
            nameEn: 'Al-Baqarah',
            nameRu: 'Аль-Бакара',
            ayahCount: 286,
            revelationType: 'medinan',
          ),
        ],
        fromCache: false,
      ),
    ),
  ];
}

Widget _app(List<Override> overrides, GoRouter router) => ProviderScope(
  overrides: overrides,
  child: RepaintBoundary(
    key: _boundary,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: IqroTheme.light(),
      routerConfig: router,
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ),
);

Future<void> _pumpSheet(
  WidgetTester tester,
  _Remote remote, {
  bool screenshot = false,
}) async {
  if (screenshot) _useRedmiSize(tester);
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Мусхаф · страница 2')),
          body: Center(
            child: FilledButton(
              key: const ValueKey('open-sheet'),
              onPressed: () =>
                  showMemorizeAyahSheet(context, surah: 2, ayah: 6),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/memorization',
        builder: (context, state) => const Scaffold(body: Text('MEMORIZATION')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(_app(_overrides(remote), router));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-sheet')));
  await tester.pumpAndSettle();
}

Future<void> _pumpCard(
  WidgetTester tester,
  MemorizationDashboard dashboard, {
  ValueChanged<MemorizationItem>? onStart,
  ValueChanged<MemorizationItem>? onMemorized,
  bool screenshot = false,
}) async {
  if (screenshot) _useRedmiSize(tester);
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: IqroTopBar(title: context.l10n.memorizationTitle),
          body: IqroPage(
            child: MemorizationListCard(
              dashboard: dashboard,
              busy: false,
              onStart: onStart ?? (_) {},
              onMemorized: onMemorized ?? (_) {},
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(_app(_overrides(_Remote()), router));
  await tester.pumpAndSettle();
}

void _useRedmiSize(WidgetTester tester) {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = _pixelRatio;
  addTearDown(tester.view.reset);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
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
}

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
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
}

Map<String, Object?> _ayah(int ayah) => <String, Object?>{
  'id': 'ayah-2-$ayah',
  'surah_number': 2,
  'ayah_number': ayah,
  'text_uthmani': 'text',
};

Map<String, Object?> _item(
  String id,
  String status,
  int start,
  int end, {
  int position = 0,
}) => <String, Object?>{
  'id': id,
  'status': status,
  'position': position,
  'source': 'mushaf',
  'start_ayah': _ayah(start),
  'end_ayah': _ayah(end),
  'ayah_count': end - start + 1,
};

Map<String, Object?> _plan(int end, int revision) => <String, Object?>{
  'id': 'plan-1',
  'edition_code': 'madani-hafs',
  'content_version': '2026.1',
  'start_ayah': _ayah(1),
  'end_ayah': _ayah(end),
  'recitation_id': null,
  'reciter': null,
  'daily_repetitions': 5,
  'pause_seconds': 2,
  'timezone_name': 'Europe/Istanbul',
  'revision': revision,
};

Map<String, Object?> _dashboardJson({
  bool activeMemorized = false,
  int activeEnd = 5,
  int revision = 3,
}) => <String, Object?>{
  'timezone_name': 'Europe/Istanbul',
  'plan': _plan(activeEnd, revision),
  'today': <String, Object?>{
    'local_date': '2026-10-27',
    'completed_repetitions': 0,
    'target_repetitions': 5,
    'remaining_repetitions': 5,
    'is_completed': false,
    'last_assessment': null,
    'sessions': const <Object?>[],
  },
  'recent_days': const <Object?>[],
  'revision': revision,
  'items': <Object?>[
    if (!activeMemorized) _item('item-active', 'active', 1, activeEnd),
    _item('item-queued', 'queued', 10, 12),
    _item('item-old', 'memorized', 20, 23),
    if (activeMemorized) _item('item-active', 'memorized', 1, activeEnd),
  ],
  'memorized_ayah_count': activeMemorized ? 9 : 4,
};

MemorizationDashboard _dashboard({bool activeMemorized = false}) =>
    MemorizationDashboard.fromJson(
      _dashboardJson(activeMemorized: activeMemorized),
    );

Map<String, Object?> _preview(String state) => <String, Object?>{
  'state': state,
  'revision': 3,
  'item': state == 'empty' ? null : _item('item-active', 'active', 1, 5),
  'extend_to': state == 'extendable'
      ? <String, Object?>{
          'surah_number': 2,
          'start_ayah_number': 1,
          'end_ayah_number': 6,
        }
      : null,
};

class _Remote implements MemorizationRemoteGateway {
  var dashboardPayload = _dashboardJson();
  var previewPayload = _preview('choose');
  var addResult = 'extended';
  Map<String, Object?>? previewQuery;
  Map<String, Object?>? added;
  (String, String, int)? updated;
  (String, int)? removed;

  @override
  Future<Object?> dashboard(
    String timezoneName, {
    AccountScopeSnapshot? accountScope,
  }) async => dashboardPayload;

  @override
  Future<Object?> previewSelection(
    Map<String, Object?> query, {
    AccountScopeSnapshot? accountScope,
  }) async {
    previewQuery = query;
    return previewPayload;
  }

  @override
  Future<Object?> addSelection(
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    added = payload;
    final end = payload['end_ayah']! as int;
    dashboardPayload = _dashboardJson(activeEnd: end, revision: 4);
    return <String, Object?>{
      ...dashboardPayload,
      'result': addResult,
      'item': _item('item-active', 'active', 1, end),
      'next': null,
    };
  }

  @override
  Future<Object?> updateItem(
    String itemId,
    Map<String, Object?> payload, {
    AccountScopeSnapshot? accountScope,
  }) async {
    updated = (
      itemId,
      payload['status']! as String,
      payload['base_revision']! as int,
    );
    dashboardPayload = _dashboardJson(activeMemorized: true, revision: 4);
    return <String, Object?>{...dashboardPayload, 'result': 'memorized'};
  }

  @override
  Future<Object?> removeItem(
    String itemId,
    int baseRevision, {
    AccountScopeSnapshot? accountScope,
  }) async {
    removed = (itemId, baseRevision);
    return <String, Object?>{...dashboardPayload, 'result': 'removed'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences extends StateNotifier<AppPreferences>
    implements AppPreferencesController {
  _Preferences() : super(const AppPreferences.defaults());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryDatabase implements LocalDatabase {
  static const scope = AccountScopeSnapshot(userId: 'test-owner', epoch: 1);
  CachedValue? cached;

  @override
  Future<AccountScopeSnapshot> captureAccount() async => scope;

  @override
  void ensureCurrent(AccountScopeSnapshot accountScope) {}

  @override
  Future<CachedValue?> readAccountCache(
    String key, {
    AccountScopeSnapshot? accountScope,
  }) async => cached;

  @override
  Future<void> writeAccountCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
    AccountScopeSnapshot? accountScope,
  }) async {
    final now = DateTime.now().toUtc();
    cached = CachedValue(value: value, updatedAt: now, expiresAt: now);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
