import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/share/content_share.dart';

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

  testWidgets('the preview card renders to a PNG', (tester) async {
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
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()..color = const Color(0xFFD5A34C),
      );
      final logo = await recorder.endRecording().toImage(4, 4);
      return renderShareCard(context, share, logo: logo);
    });
    // PNG signature, at twice the card's logical size.
    expect(bytes!.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    final codec = await tester.runAsync(() => ui.instantiateImageCodec(bytes));
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, (shareCardSize.width * 2).round());
    expect(frame.image.height, (shareCardSize.height * 2).round());
  });
}
