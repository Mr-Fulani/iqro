import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_match.dart';

/// Al-Fatiha as the Mushaf writes it.
final _fatiha =
    'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ '
            'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ '
            'ٱلرَّحْمَٰنِ ٱلرَّحِيمِ '
            'مَٰلِكِ يَوْمِ ٱلدِّينِ '
            'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ '
            'ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ '
            'صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ'
        .split(' ');

/// The start of 2:255.
final _kursi =
    'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌۭ وَلَا نَوْمٌۭ ۚ '
            'لَّهُۥ مَا فِى ٱلسَّمَٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ'
        .split(' ');

void main() {
  group('normalizeArabic', () {
    test('drops the marks and joins the forms of a letter', () {
      expect(normalizeArabic('ٱلرَّحْمَٰنِ'), 'الرحمن');
      expect(normalizeArabic('إِيَّاكَ'), 'اياك');
      expect(normalizeArabic('ٱلصَّلَوٰةَ'), 'الصلوه');
      expect(normalizeArabic('شَىْءٍ'), 'شي');
      expect(normalizeArabic('ٱلضَّآلِّينَ'), 'الضالين');
      expect(normalizeArabic('ۚ'), '');
    });

    test('a recogniser\'s spelling is close to the Mushaf\'s', () {
      expect(
        similarArabic('العالمين', normalizeArabic('ٱلْعَٰلَمِينَ')),
        isTrue,
      );
      expect(similarArabic('مالك', normalizeArabic('مَٰلِكِ')), isTrue);
      expect(similarArabic('الصراط', normalizeArabic('ٱلصِّرَٰطَ')), isTrue);
      expect(similarArabic('من', 'ما'), isFalse);
      expect(similarArabic('نعبد', 'نستعين'), isFalse);
    });
  });

  group('RecitationMatcher', () {
    test('follows a transcript that grows word by word', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم'), 0);
      expect(matcher.hear('بسم الله'), 1);
      expect(matcher.hear('بسم الله الرحمن'), 2);
      expect(matcher.hear('بسم الله الرحمن الرحيم'), 3);
      expect(matcher.hear('بسم الله الرحمن الرحيم الحمد'), 4);
    });

    test('the same transcript again stays where it is', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله الرحمن الرحيم'), 3);
      // The same two words stand five words on, in the third ayah.
      expect(matcher.hear('بسم الله الرحمن الرحيم'), isNull);
      expect(matcher.hear('الله الرحمن الرحيم'), isNull);
    });

    test('after a pause a word like the one before it still moves on', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله الرحمن'), 2);
      // «ٱلرَّحِيمِ» is two letters from «ٱلرَّحْمَٰنِ».
      expect(matcher.hear('الرحيم'), 3);
      expect(matcher.hear('الحمد لله رب العالمين'), 7);
      expect(matcher.hear('الرحمن'), 8);
      expect(matcher.hear('الرحمن الرحيم'), 9);
    });

    test('several words at once move on to the last of them', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله الرحمن الرحيم الحمد لله رب العالمين'), 7);
    });

    test('a misheard word is passed over', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(10);
      // «مَٰلِكِ» heard as something else.
      expect(matcher.hear('ملاك يوم'), 11);
      expect(matcher.hear('ملاك يوم الدين'), 12);
    });

    test('a new listen carries on from the place', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(13);
      expect(matcher.hear('اياك'), 13);
      expect(matcher.hear('اياك نعبد'), 14);
      expect(matcher.hear('اياك نعبد واياك'), 15);
      expect(matcher.hear('اياك نعبد واياك نستعين'), 16);
    });

    test('words that are not on the page move nothing', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(4);
      expect(matcher.hear('اعوذ بالله من الشيطان الرجيم'), isNull);
      expect(matcher.hear('اعوذ بالله من الشيطان الرجيم الحمد'), 4);
    });

    test('a reader who jumps is found again by three words in a row', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله'), 1);
      // Too far for the window.
      expect(matcher.hear('غير المغضوب'), isNull);
      expect(matcher.hear('غير المغضوب عليهم'), 26);
      // And back to an earlier ayah.
      expect(matcher.hear('الحمد لله رب'), 6);
    });

    test('pause signs are not words, a word written as two is one', () {
      final matcher = RecitationMatcher(_kursi);
      expect(matcher.hear('الله لا اله الا هو الحي القيوم'), 6);
      // The sign after «ٱلْقَيُّومُ» is at 7.
      expect(matcher.hear('القيوم لا تاخذه'), 9);
      expect(matcher.hear('لا تاخذه سنة ولا نوم'), 12);
      expect(matcher.hear('له ما في السماوات وما في الارض'), 20);
      // «بِإِذْنِهِۦ» heard as «ب اذنه».
      expect(matcher.hear('من ذا الذي يشفع عنده الا ب اذنه'), 28);
    });
  });
}
