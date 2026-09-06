import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/mushaf_reader_controls.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    testWidgets('$locale: seven real page dots, right-to-left, no slider', (
      tester,
    ) async {
      final changes = <int>[];
      await _pump(tester, page: 3, locale: locale, changes: changes);
      expect(find.byType(Slider), findsNothing);
      for (var page = 1; page <= 7; page++) {
        expect(_dot(page), findsOneWidget);
      }
      expect(
        tester.getCenter(_dot(1)).dx,
        greaterThan(tester.getCenter(_dot(7)).dx),
      );
      await tester.tap(_dot(3));
      await tester.pump();
      expect(changes, isEmpty);
      await tester.tap(_dot(4));
      await tester.pumpAndSettle();
      expect(changes, [4]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'drag keeps its page window stable and does not repeat the same page',
    (tester) async {
      final changes = <int>[];
      await _pump(tester, page: 50, changes: changes);
      final gesture = await tester.startGesture(tester.getCenter(_dot(50)));
      await gesture.moveTo(tester.getCenter(_dot(51)));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_dot(52)));
      await tester.pump();
      expect(changes.last, 52);
      expect(_dot(47), findsOneWidget);
      final count = changes.length;
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(changes.length, count);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_dot(49), findsOneWidget);
      expect(_dot(55), findsOneWidget);
      expect(_dot(47), findsNothing);
    },
  );

  testWidgets('first and last pages never expose invalid page numbers', (
    tester,
  ) async {
    final changes = <int>[];
    await _pump(tester, page: 1, changes: changes);
    expect(_dot(0), findsNothing);
    expect(_dot(7), findsOneWidget);
    await tester.tap(_dot(1));
    expect(changes, isEmpty);
    await _pump(tester, page: 604, changes: changes);
    expect(_dot(598), findsOneWidget);
    expect(_dot(605), findsNothing);
    await tester.tap(_dot(604));
    expect(changes, isEmpty);
    await tester.tap(_dot(603));
    await tester.pumpAndSettle();
    expect(changes, [603]);
  });
}

Finder _dot(int page) => find.byKey(ValueKey('mushaf-page-dot-$page'));

Future<void> _pump(
  WidgetTester tester, {
  required int page,
  String locale = 'ru',
  required List<int> changes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('$page:$locale'),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: StatefulBuilder(
              builder: (context, setState) => MushafPageScrubber(
                page: page,
                juz: 1,
                onJump: (value) {
                  changes.add(value);
                  setState(() => page = value);
                },
                onCatalog: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
