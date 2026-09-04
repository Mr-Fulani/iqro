import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quick_jump_sheet.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('quick jump exposes hizb and rub al-hizb on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    QuranQuickJumpSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showModalBottomSheet<QuranQuickJumpSelection>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => const QuranQuickJumpSheet(
                      surahs: <Surah>[_surah],
                      juz: <QuranDivision>[_juz],
                      hizb: <QuranDivision>[_hizb],
                      rubElHizb: <QuranDivision>[_rub],
                      initialMode: QuranQuickJumpMode.page,
                      initialSurah: 18,
                      initialAyah: 1,
                      initialPage: 293,
                    ),
                  );
                },
                child: const Text('Открыть навигацию'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть навигацию'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Хизб'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Руб аль-хизб'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Руб аль-хизб'));
    await tester.pumpAndSettle();

    expect(
      find.text('49. Хизб 13 · ¼ 1 · 18:1 · Страница 293'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Открыть'));
    await tester.pumpAndSettle();

    expect(result?.mode, QuranQuickJumpMode.rubElHizb);
    expect(result?.surah, 18);
    expect(result?.ayah, 1);
    expect(result?.page, 293);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page jump remains available when catalogs are offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: QuranQuickJumpSheet(
            surahs: <Surah>[],
            juz: <QuranDivision>[],
            hizb: <QuranDivision>[],
            rubElHizb: <QuranDivision>[],
            initialMode: QuranQuickJumpMode.ayah,
            initialPage: 255,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final page = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Page'),
    );
    final ayah = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Ayah'),
    );
    expect(page.selected, isTrue);
    expect(ayah.onSelected, isNull);
    expect(find.text('255'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _surah = Surah(
  id: 'surah-18',
  number: 18,
  nameAr: 'الكهف',
  nameEn: 'Al-Kahf',
  nameRu: 'Аль-Кахф',
  ayahCount: 110,
  revelationType: 'meccan',
  firstPage: 293,
);

const _juz = QuranDivision(
  number: 15,
  startAyah: QuranAyahReference(id: '', surah: 17, ayah: 1),
  endAyah: QuranAyahReference(id: '', surah: 18, ayah: 74),
  startPage: 282,
  endPage: 301,
);

const _hizb = QuranDivision(
  number: 13,
  startAyah: QuranAyahReference(id: '', surah: 18, ayah: 1),
  endAyah: QuranAyahReference(id: '', surah: 18, ayah: 31),
  startPage: 293,
  endPage: 296,
);

const _rub = QuranDivision(
  number: 49,
  startAyah: QuranAyahReference(id: '', surah: 18, ayah: 1),
  endAyah: QuranAyahReference(id: '', surah: 18, ayah: 16),
  startPage: 293,
  endPage: 295,
  hizbNumber: 13,
  quarterNumber: 1,
);
