import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_presentation.dart';

void main() {
  test('capitals from the source read in sentence case', () {
    expect(
      duaDisplayTitle('СЛОВА ПОМИНАНИЯ АЛЛАХА, ПРОИЗНОСИМЫЕ УТРОМ И ВЕЧЕРОМ'),
      'Слова поминания Аллаха, произносимые утром и вечером',
    );
    expect(
      duaDisplayTitle('WHAT TO SAY WHEN READING THE QURAN'),
      'What to say when reading the Quran',
    );
  });

  test('mixed case and Arabic titles stay as they are', () {
    expect(duaDisplayTitle('Слова поминания утром'), 'Слова поминания утром');
    expect(duaDisplayTitle('أذكار الصباح'), 'أذكار الصباح');
  });
}
