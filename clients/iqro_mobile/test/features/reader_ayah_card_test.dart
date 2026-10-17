import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/reader_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  Rect? sharedFrom;
  var shared = 0;

  Future<void> pump(
    WidgetTester tester, {
    required int surah,
    required String text,
    bool active = false,
    ThemeData? theme,
  }) async {
    shared = 0;
    sharedFrom = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? IqroTheme.light(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderAyahCard(
              ayah: QuranAyah(
                id: '$surah:1',
                surahNumber: surah,
                number: 1,
                textUthmani: text,
                pages: const <int>[2],
              ),
              selected: false,
              highlightColorKey: null,
              audioActive: active,
              audioPlaying: active,
              audioLoading: false,
              bookmarked: false,
              showTranslation: true,
              showTafsir: false,
              translation: const QuranAyahTranslation(
                verseKey: '2:1',
                surah: 2,
                ayah: 1,
                text: 'Алиф. Лям. Мим.',
                footnotes: <String>[],
              ),
              tafsir: null,
              contentLoading: false,
              arabicFontSize: 28,
              arabicLineHeight: 2,
              ayahCount: 286,
              repeatEnabled: false,
              speed: 1.25,
              onSelected: () {},
              onBookmark: () {},
              onPlay: () {},
              onToggleRepeat: active ? () {} : null,
              onCycleSpeed: active ? () {} : null,
              onShare: (origin) {
                shared++;
                sharedFrom = origin;
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the basmala before a surah stands on its own line', (
    tester,
  ) async {
    await pump(
      tester,
      surah: 2,
      text: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ',
    );

    expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
    expect(find.text('الٓمٓ  ﴿١﴾'), findsOneWidget);
    expect(find.text('Алиф. Лям. Мим.'), findsOneWidget);
  });

  testWidgets('al-Fatiha keeps the basmala as its first ayah', (tester) async {
    await pump(
      tester,
      surah: 1,
      text: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    );

    expect(
      find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ  ﴿١﴾'),
      findsOneWidget,
    );
  });

  testWidgets('the bar holds the actions and the place in the surah', (
    tester,
  ) async {
    await pump(tester, surah: 2, text: 'الٓمٓ');

    for (final tooltip in <String>['Слушать', 'Повтор', 'Избранное']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    expect(find.text('1/286'), findsOneWidget);
    // Repeat and speed act on this ayah only while it plays.
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.repeat))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '1.25×'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Поделиться аятом'));
    expect(shared, 1);
    expect(sharedFrom, isNotNull);

    await pump(tester, surah: 2, text: 'الٓمٓ', active: true);
    expect(find.byTooltip('Пауза'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '1.25×'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('dark theme writes the Arabic in warm ivory', (tester) async {
    await pump(tester, surah: 2, text: 'الٓمٓ', theme: IqroTheme.dark());

    final arabic = tester.widget<Text>(
      find.byKey(const ValueKey('reader-ayah-1')),
    );
    expect(arabic.style?.color, const Color(0xFFEFE6CF));
  });
}
