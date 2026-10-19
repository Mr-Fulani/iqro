import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_arabic.dart';

void main() {
  test('each basmala before a surah gets its own line', () {
    final parts = splitDuaArabic(
      'بسم الله الرحمن الرحيم ﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾. '
      'بسم الله الرحمن الرحيم ﴿قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ﴾',
    );

    expect(parts, const <DuaArabicPart>[
      DuaArabicPart('بسم الله الرحمن الرحيم', opening: true),
      DuaArabicPart('﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾'),
      DuaArabicPart('بسم الله الرحمن الرحيم', opening: true),
      DuaArabicPart('﴿قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ﴾'),
    ]);
  });

  test('the isti\'adha is found with full vowels', () {
    final parts = splitDuaArabic(
      'أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ ﴿اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ﴾',
    );

    expect(parts.first.opening, isTrue);
    expect(parts.first.text, 'أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ');
    expect(parts.last, const DuaArabicPart('﴿اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ﴾'));
  });

  test('a du\'a without a formula stays one line', () {
    expect(splitDuaArabic('الْحَمْدُ لِلَّهِ'), const <DuaArabicPart>[
      DuaArabicPart('الْحَمْدُ لِلَّهِ'),
    ]);
  });

  test('a du\'a that is only the basmala keeps the full size', () {
    expect(
      splitDuaArabic('بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ'),
      const <DuaArabicPart>[
        DuaArabicPart('بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ'),
      ],
    );
  });

  test('the formula inside a sentence is not split off mid-word', () {
    // «باسمك» is not the basmala.
    expect(
      splitDuaArabic('بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا'),
      hasLength(1),
    );
  });
}
