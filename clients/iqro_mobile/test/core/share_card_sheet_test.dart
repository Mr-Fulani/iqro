import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/share/content_share.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _share = ContentShare(
  title: 'Аль-Ихлас · 112:1',
  arabic: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
  translation: 'Скажи: «Он — Аллах Единый»',
  cardReference: 'Аль-Ихлас · 112:1',
  url: 'https://iqro.forum/ru/quran/madani-hafs/surah/112/ayah/1',
  readInIqro: 'Читать в IQRO',
);

Future<void> _open(WidgetTester tester, ContentShare share) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ShareCardSheet(share: share)),
    ),
  );
  await _settle(tester);
}

// The cards are drawn with real asynchronous work: assets and pictures.
Future<void> _settle(WidgetTester tester) async {
  for (var turn = 0; turn < 20; turn += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  testWidgets('the sheet shows the card and remembers its shape and colour', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _open(tester, _share);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 1920);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.text('Поделиться'), findsOneWidget);

    await tester.tap(find.text('Пост'));
    await _settle(tester);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 1350);
    await tester.tap(find.bySemanticsLabel('Тёмно-синий'));
    await _settle(tester);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'iqro_share_card_style_v1',
      ),
      'post:midnight',
    );

    // Opened again, the sheet starts from the remembered style.
    await tester.pumpWidget(const SizedBox());
    await _open(tester, _share);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 1350);
  });

  testWidgets('a text too long for a series is offered as text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _open(
      tester,
      ContentShare(
        title: _share.title,
        arabic: List.filled(900, 'ٱللَّهُ').join(' '),
        url: _share.url,
        readInIqro: _share.readInIqro,
      ),
    );
    expect(find.byType(RawImage), findsNothing);
    expect(find.textContaining('слишком длинный'), findsOneWidget);
    expect(find.text('Отправить текстом'), findsOneWidget);
  });
}
