import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/quran_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite/sqflite.dart';

const installed = MushafDownloadSnapshot(
  status: MushafDownloadStatus.ready,
  packageId: 'edition-old',
  completedPages: 604,
  totalPages: 604,
  downloadedBytes: 1024,
  totalBytes: 1024,
);

void main() {
  testWidgets(
    'ready package exposes on-demand updates without network on open',
    (tester) async {
      final repository = _Repository('edition-old');
      final controller = await _pumpCard(tester, repository);
      expect(repository.checks, 0);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(repository.checks, 1);
      expect(find.text('Скачанный Мусхаф уже обновлён'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.downloads, 0);
      expect(find.byIcon(Icons.offline_pin_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new package requires confirmation and never removes the old package',
    (tester) async {
      final repository = _Repository('edition-new');
      final controller = await _pumpCard(tester, repository);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('Текущий Мусхаф останется доступен'),
        findsOneWidget,
      );
      expect(controller.downloads, 0);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(controller.downloads, 0);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.widgetWithText(FilledButton, 'Обновить Мусхаф'));
      await tester.pumpAndSettle();
      expect(controller.downloads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline check failure leaves existing download and retry button available',
    (tester) async {
      final repository = _Repository('edition-new')..fail = true;
      final controller = await _pumpCard(tester, repository);
      await tester.tap(find.text('Проверить обновления'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Проверить обновления'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.downloads, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Controller> _pumpCard(
  WidgetTester tester,
  _Repository repository,
) async {
  final controller = _Controller(repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mushafDownloadProvider.overrideWith((ref) => installed),
        selectedMushafIdentityProvider.overrideWith(
          (ref) => MushafIdentity.fromPreference('native:qcf-v2-hafs'),
        ),
        selectedMushafOfflineRepositoryProvider.overrideWithValue(repository),
        selectedMushafDownloadControllerProvider.overrideWithValue(controller),
        localDatabaseProvider.overrideWithValue(
          LocalDatabase.forTesting(_Sql()),
        ),
      ],
      child: MaterialApp(
        theme: IqroTheme.light(),
        locale: Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: OfflineMushafCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _Repository implements MushafOfflineRepository {
  _Repository(this.packageId);
  final String packageId;
  var checks = 0;
  var fail = false;
  @override
  Future<MushafDownloadSnapshot> snapshot() async => installed;
  @override
  Future<MushafDownloadSnapshot> estimate({
    int? width,
    int expectedPageCount = 604,
  }) async {
    checks += 1;
    if (fail) throw StateError('offline');
    return MushafDownloadSnapshot(
      status: MushafDownloadStatus.notDownloaded,
      packageId: packageId,
      totalPages: 604,
      totalBytes: 2048,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends MushafDownloadController {
  _Controller(super.repository);
  var downloads = 0;
  @override
  Future<void> download({int? width}) async {
    downloads += 1;
  }
}

class _Sql implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [
    {'reserved_bytes': installed.totalBytes},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
