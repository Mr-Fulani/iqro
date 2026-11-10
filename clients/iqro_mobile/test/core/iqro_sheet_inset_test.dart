import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/features/quran/quick_jump_sheet.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

// A phone with three-button navigation: the system bar takes 48 dp at the
// bottom. The quick jump sheet's «Открыть» button ended under it (Samsung, in
// the owner's report).
void main() {
  Future<void> open(
    WidgetTester tester,
    WidgetBuilder builder, {
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    // As on Android: the keyboard covers the bar, which then leaves the
    // padding and stays only in the view padding.
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : 48);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showIqroSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: builder,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Widget quickJump(BuildContext context) => const QuranQuickJumpSheet(
    surahs: <Surah>[_surah],
    juz: <QuranDivision>[],
    hizb: <QuranDivision>[],
    rubElHizb: <QuranDivision>[],
    initialSurah: 2,
    initialAyah: 49,
  );

  Rect openButton(WidgetTester tester) => tester.getRect(
    find.ancestor(
      of: find.text('Открыть'),
      matching: find.bySubtype<ButtonStyleButton>(),
    ),
  );

  testWidgets('the quick jump button ends above the system navigation bar', (
    tester,
  ) async {
    await open(tester, quickJump);
    // The sheet's own 20 dp under the button, then the 48 dp bar.
    expect(openButton(tester).bottom, 800 - 48 - 20);
    // The sheet's colour still runs under the bar.
    expect(tester.getRect(find.byType(BottomSheet)).bottom, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet with its own SafeArea is not padded twice', (
    tester,
  ) async {
    await open(
      tester,
      (context) => const SafeArea(
        child: SizedBox(key: ValueKey('content'), height: 100),
      ),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('content'))).bottom,
      800 - 48,
    );
  });

  testWidgets('with the keyboard open only the keyboard is padded for', (
    tester,
  ) async {
    await open(tester, quickJump, keyboard: 300);
    expect(openButton(tester).bottom, 800 - 300 - 20);
  });
}

const _surah = Surah(
  id: 'surah-2',
  number: 2,
  nameAr: 'البقرة',
  nameEn: 'Al-Baqarah',
  nameRu: 'Аль-Бакара',
  ayahCount: 286,
  revelationType: 'medinan',
  firstPage: 2,
);
