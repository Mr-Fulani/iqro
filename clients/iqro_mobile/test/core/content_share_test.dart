import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/share/content_share.dart';
import 'package:iqro_mobile/core/share/share_card_layout.dart';
import 'package:iqro_mobile/features/quran/ayah_share.dart';

// Where `--dart-define=SCREENSHOT_DIR=…` writes the cards as JPEG, drawn in
// the app's own fonts, for a look at them without a phone.
const _screenshots = String.fromEnvironment('SCREENSHOT_DIR');

const _kursi =
    'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَىْءٍ مِّنْ عِلْمِهِۦٓ إِلَّا بِمَا شَآءَ ۚ وَسِعَ كُرْسِيُّهُ ٱلسَّمَٰوَٰتِ وَٱلْأَرْضَ ۖ وَلَا يَـُٔودُهُۥ حِفْظُهُمَا ۚ وَهُوَ ٱلْعَلِىُّ ٱلْعَظِيمُ';
const _kursiMeaning =
    'Аллах — нет божества, кроме Него, Живого, Вседержителя. Им не овладевают ни дремота, ни сон. Ему принадлежит то, что на небесах, и то, что на земле. Кто станет заступаться перед Ним без Его дозволения? Он знает их будущее и прошлое. Они постигают из Его знания только то, что Он пожелает. Его Престол объемлет небеса и землю, и не тяготит Его оберегание их. Он — Возвышенный, Великий.';

ContentShare _ayah(String arabic, String meaning, int ayah) => ayahContentShare(
  locale: 'ru',
  surahName: 'Аль-Бакара',
  surah: 2,
  ayah: ayah,
  arabic: arabic,
  translation: meaning,
  readInIqro: 'Читать в IQRO',
);

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (built) {
          context = built;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

Future<void> _loadFonts() async {
  for (final (family, file) in [
    ('Amiri Quran', 'AmiriQuran-Regular.ttf'),
    ('PT Serif', 'PTSerif-Regular.ttf'),
  ]) {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  const share = ContentShare(
    title: 'Аль-Бакара · 2:255',
    arabic: 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ',
    translation: 'Аллах — нет божества, кроме Него',
    reference: 'Перевод: Кулиев',
    url: 'https://iqro.forum/ru/quran/madani-hafs/surah/2/ayah/255',
    readInIqro: 'Читать в IQRO',
  );

  test('the message reads top to bottom and ends with the link', () {
    expect(
      contentShareText(share),
      'Аль-Бакара · 2:255\n\n'
      'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ\n\n'
      '«Аллах — нет божества, кроме Него»\n\n'
      'Перевод: Кулиев\n\n'
      'Читать в IQRO: '
      'https://iqro.forum/ru/quran/madani-hafs/surah/2/ayah/255',
    );
  });

  test('links point at the public site whatever API the build uses', () {
    expect(
      ayahShareUrl('ar', 1, 7),
      'https://iqro.forum/ar/quran/madani-hafs/surah/1/ayah/7',
    );
    expect(
      duaShareUrl('tr', 'hisn-al-muslim', 76),
      'https://iqro.forum/tr/dua/hisn-al-muslim/76',
    );
  });

  test('the card draws the words of the source, unchanged', () {
    final text = ShareCardText(_ayah(_kursi, _kursiMeaning, 255));
    final words = text.arabicWords.map((word) => word.toPlainText()).toList();
    // The end sign rides on the last word; the rest is the ayah byte for byte.
    expect(words.last, endsWith(' ۝٢٥٥'));
    words.last = words.last.replaceFirst(' ۝٢٥٥', '');
    expect(words.join(' '), _kursi);
    expect(text.translationWords.join(' '), '«$_kursiMeaning»');
  });

  testWidgets('a short ayah is one story card, or one post card', (
    tester,
  ) async {
    final context = await _context(tester);
    for (final (format, height) in [
      (ShareCardFormat.story, 1920),
      (ShareCardFormat.post, 1350),
    ]) {
      final pictures = await tester.runAsync(
        () => renderShareCards(
          context,
          _ayah(share.arabic, share.translation, 255),
          format: format,
          colour: 'emerald',
        ),
      );
      expect(pictures, hasLength(1));
      expect(pictures!.single.width, 1080);
      expect(pictures.single.height, height);
    }
  });

  testWidgets('a long text is a series, never cut; too long gives no card', (
    tester,
  ) async {
    final context = await _context(tester);
    await tester.runAsync(_loadFonts);
    final long = _ayah(
      List.filled(3, _kursi).join(' '),
      List.filled(3, _kursiMeaning).join(' '),
      282,
    );
    final layout = ShareCardLayout.parse(
      File('assets/share_card/layout.json').readAsStringSync(),
    );
    final text = ShareCardText(long);
    final pages = composeShareCard(
      layout,
      ShareCardFormat.story,
      text.arabic,
      text.translation,
    )!;
    expect(pages.length, greaterThan(1));
    // Every word is on exactly one card, in order.
    expect([
      for (final page in pages)
        for (final line in page.arabicLines)
          for (var word = line.start; word < line.end; word++) word,
    ], List.generate(text.arabicWords.length, (index) => index));
    expect([
      for (final page in pages)
        for (final line in page.translationLines)
          for (var word = line.start; word < line.end; word++) word,
    ], List.generate(text.translationWords.length, (index) => index));

    final endless = _ayah(List.filled(40, _kursi).join(' '), '', 1);
    expect(
      await tester.runAsync(
        () => renderShareCards(
          context,
          endless,
          format: ShareCardFormat.story,
          colour: 'emerald',
        ),
      ),
      isNull,
    );
  });

  testWidgets('a card is sent as a JPEG', (tester) async {
    final context = await _context(tester);
    final bytes = await tester.runAsync(() async {
      final pictures = await renderShareCards(
        context,
        share,
        format: ShareCardFormat.post,
        colour: 'midnight',
      );
      return encodeShareCard(pictures!.single);
    });
    expect(bytes!.sublist(0, 3), <int>[0xFF, 0xD8, 0xFF]);
    expect(bytes.length, lessThan(700 * 1024));
  });

  testWidgets(
    'an ayah card has the glyphs of the Mushaf; neither it nor the message names the translator',
    (tester) async {
      final ayah = ayahContentShare(
        locale: 'ru',
        surahName: 'Аль-Анам',
        surah: 6,
        ayah: 2,
        arabic: 'هُوَ ٱلَّذِى خَلَقَكُم',
        translation: 'Он — Тот, Кто сотворил вас',
        glyphs: const [
          TextSpan(
            text: 'ﱃ',
            style: TextStyle(fontFamily: 'qf-page-128'),
          ),
          TextSpan(
            text: 'ﱅ',
            style: TextStyle(fontFamily: 'qf-page-129'),
          ),
        ],
        readInIqro: 'Читать в IQRO',
      );
      expect(
        contentShareText(ayah),
        'Аль-Анам · 6:2\n\n'
        'هُوَ ٱلَّذِى خَلَقَكُم\n\n'
        '«Он — Тот, Кто сотворил вас»\n\n'
        'Читать в IQRO: '
        'https://iqro.forum/ru/quran/madani-hafs/surah/6/ayah/2',
      );

      final layout = ShareCardLayout.parse(
        File('assets/share_card/layout.json').readAsStringSync(),
      );
      final text = ShareCardText(ayah);
      final background = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint());
        return recorder.endRecording().toImage(4, 4);
      });
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ShareCard(
            share: ayah,
            text: text,
            page: composeShareCard(
              layout,
              ShareCardFormat.story,
              text.arabic,
              text.translation,
            )!.single,
            part: 1,
            parts: 1,
            layout: layout,
            format: ShareCardFormat.story,
            background: background!,
          ),
        ),
      );
      final lines = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((line) => line.text.toPlainText())
          .toList();
      expect(lines, contains('ﱃ ﱅ'));
      expect(lines.join(' '), contains('«Он — Тот, Кто сотворил вас»'));
      expect(lines, contains('Аль-Анам · 6:2'));
      expect(lines, contains('iqro.forum'));
      expect(lines.any((line) => line.contains('خَلَقَكُم')), isFalse);
    },
  );

  testWidgets('pictures', skip: _screenshots.isEmpty, (tester) async {
    final context = await _context(tester);
    await tester.runAsync(_loadFonts);
    final cases = <(String, ContentShare, ShareCardFormat, String)>[
      (
        'short-story-emerald',
        _ayah(
          'لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا وُسْعَهَا',
          'Аллах не возлагает на человека сверх его возможностей',
          286,
        ),
        ShareCardFormat.story,
        'emerald',
      ),
      (
        'short-post-turquoise',
        _ayah(share.arabic, share.translation, 255),
        ShareCardFormat.post,
        'turquoise',
      ),
      (
        'kursi-story-midnight',
        _ayah(_kursi, _kursiMeaning, 255),
        ShareCardFormat.story,
        'midnight',
      ),
      (
        'kursi-post-emerald',
        _ayah(_kursi, _kursiMeaning, 255),
        ShareCardFormat.post,
        'emerald',
      ),
      (
        'dua-story-emerald',
        const ContentShare(
          title: 'Слова поминания Аллаха · #16',
          arabic:
              'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ',
          translation:
              'Allah’ım, Senin sayende sabaha çıktık, Senin sayende akşama erdik; Senin sayende yaşar, Senin sayende ölürüz. Dönüş yalnız Sanadır.',
          cardReference: 'Hısnu’l-Müslim, № 16',
          url: 'https://iqro.forum/tr/dua/hisn-al-muslim/16',
          readInIqro: 'IQRO’da oku',
        ),
        ShareCardFormat.story,
        'emerald',
      ),
    ];
    for (final (name, content, format, colour) in cases) {
      final files = await tester.runAsync(() async {
        final pictures = await renderShareCards(
          context,
          content,
          format: format,
          colour: colour,
        );
        return [
          for (final picture in pictures!) await encodeShareCard(picture),
        ];
      });
      for (final (index, bytes) in files!.indexed) {
        File('$_screenshots/$name-${index + 1}.jpg').writeAsBytesSync(bytes);
      }
    }
  });
}
