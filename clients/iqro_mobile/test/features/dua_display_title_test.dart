import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_presentation.dart';

void main() {
  test('capitals from the source read in sentence case', () {
    expect(
      duaDisplayTitle(
        'СЛОВА ПОМИНАНИЯ АЛЛАХА, ПРОИЗНОСИМЫЕ УТРОМ И ВЕЧЕРОМ',
        'ru',
      ),
      'Слова поминания Аллаха, произносимые утром и вечером',
    );
    expect(
      duaDisplayTitle('WHAT TO SAY WHEN READING THE QURAN', 'en'),
      'What to say when reading the Quran',
    );
    expect(
      duaDisplayTitle(
        "СЛОВА МОЛЬБЫ В НАЧАЛЕ МОЛИТВЫ (ду'ау-ль-истифтах)",
        'ru',
      ),
      "Слова мольбы в начале молитвы (ду'ау-ль-истифтах)",
    );
  });

  test('Turkish capitals keep their dotless and dotted i', () {
    expect(
      duaDisplayTitle('ELBİSE GİYERKEN YAPILAN DUÂ', 'tr'),
      'Elbise giyerken yapılan duâ',
    );
    expect(
      duaDisplayTitle('İSTİHÂRE NAMAZININ DUÂSI', 'tr'),
      'İstihâre namazının duâsı',
    );
  });

  test('mixed case and Arabic titles stay as they are', () {
    expect(
      duaDisplayTitle('Слова поминания утром', 'ru'),
      'Слова поминания утром',
    );
    expect(duaDisplayTitle('أذكار الصباح', 'ar'), 'أذكار الصباح');
  });
}
