import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/share/content_share.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Where `--dart-define=SCREENSHOT_DIR=…` writes the sheet as a phone shows
// it; `SCREENSHOT_FONTS` is Flutter's `material_fonts` folder.
const _screenshots = String.fromEnvironment('SCREENSHOT_DIR');
const _materialFonts = String.fromEnvironment('SCREENSHOT_FONTS');

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

  testWidgets('pictures', skip: _screenshots.isEmpty, (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      for (final (family, file) in [
        ('Amiri Quran', 'assets/fonts/AmiriQuran-Regular.ttf'),
        ('PT Serif', 'assets/fonts/PTSerif-Regular.ttf'),
        ('Roboto', '$_materialFonts/Roboto-Regular.ttf'),
        ('Roboto', '$_materialFonts/Roboto-Medium.ttf'),
        ('MaterialIcons', '$_materialFonts/MaterialIcons-Regular.otf'),
      ]) {
        final bytes = File(file).readAsBytesSync();
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const share = ContentShare(
      title: 'Аль-Бакара · 2:286',
      arabic: 'لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا وُسْعَهَا',
      arabicEnd: '۝٢٨٦',
      translation: 'Аллах не возлагает на человека сверх его возможностей',
      cardReference: 'Аль-Бакара · 2:286',
      url: 'https://iqro.forum/ru/quran/madani-hafs/surah/2/ayah/286',
      readInIqro: 'Читать в IQRO',
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: IqroTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: const Color(0xFF6B7280),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ShareCardSheet(share: share),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    Future<void> shoot(String name) async {
      // Let the buttons finish their colour transitions.
      await tester.pump(const Duration(seconds: 1));
      final bytes = await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2.625);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('$_screenshots/$name.png').writeAsBytesSync(bytes!);
    }

    await shoot('sheet-story');
    await tester.tap(find.text('Пост'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Тёмно-синий'));
    await _settle(tester);
    await shoot('sheet-post-midnight');
  });
}
