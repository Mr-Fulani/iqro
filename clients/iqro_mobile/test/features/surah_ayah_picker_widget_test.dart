import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/surah_ayah_picker.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    testWidgets('$locale picks a surah, then opens one of its ayahs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: IqroTheme.dark(),
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuranSurahAyahPicker(
                surahs: const [_fatiha, _longSurah],
                onOpen: (surah, ayah) => opened.add((surah.number, ayah)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ayahPicker = find.byWidgetPredicate(
        (widget) => widget is DropdownButton<int> && widget.items!.isEmpty,
      );
      // No surah yet: the ayah list waits for one.
      expect(tester.widget<DropdownButton<int>>(ayahPicker).onChanged, isNull);

      await tester.tap(find.byKey(const ValueKey('quran-surah-picker')));
      await tester.pumpAndSettle();
      // Surah numbers are Arabic-Indic: 83 is ٨٣.
      expect(find.text('١ · ${_fatiha.nameFor(locale)}'), findsWidgets);
      await tester.tap(find.text('٨٣ · ${_longSurah.nameFor(locale)}').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('quran-ayah-picker-83')));
      await tester.pumpAndSettle();
      // Al-Mutaffifin has 36 ayahs, so the list ends at ٣٦.
      await tester.scrollUntilVisible(
        find.text('٣٦'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('٣٧'), findsNothing);
      await tester.tap(find.text('٣٦').last);
      await tester.pumpAndSettle();

      expect(opened, [(83, 36)]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new surah starts the ayah list over', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: QuranSurahAyahPicker(
            surahs: const [_fatiha, _longSurah],
            onOpen: (_, _) {},
          ),
        ),
      ),
    );
    for (final name in ['٨٣ · Аль-Мутаффифин', '١ · Аль-Фатиха']) {
      await tester.tap(find.byKey(const ValueKey('quran-surah-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('quran-ayah-picker-83')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quran-ayah-picker-1')));
    await tester.pumpAndSettle();
    // Al-Fatiha has seven ayahs.
    expect(find.text('٧'), findsWidgets);
    expect(find.text('٨'), findsNothing);
  });
}

const _fatiha = Surah(
  id: 'surah-1',
  number: 1,
  nameAr: 'الفاتحة',
  nameEn: 'Al-Fatihah',
  nameRu: 'Аль-Фатиха',
  ayahCount: 7,
  revelationType: 'meccan',
  firstPage: 1,
);

const _longSurah = Surah(
  id: 'surah-83',
  number: 83,
  nameAr: 'المطففين',
  nameEn: 'Al-Mutaffifin',
  nameRu: 'Аль-Мутаффифин',
  ayahCount: 36,
  revelationType: 'meccan',
  firstPage: 587,
);
