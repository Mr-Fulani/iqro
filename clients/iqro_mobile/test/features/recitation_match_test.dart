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
    test('follows a phrase that grows word by word', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.expected, 0);
      expect(matcher.hear('بسم'), (reached: 0, misses: 0));
      expect(matcher.hear('بسم الله'), (reached: 1, misses: 0));
      expect(matcher.hear('بسم الله الرحمن'), (reached: 2, misses: 0));
      expect(matcher.hear('بسم الله الرحمن الرحيم'), (reached: 3, misses: 0));
      expect(matcher.expected, 4);
    });

    test(
      'the same phrase again, or its last word rewritten, moves nothing',
      () {
        final matcher = RecitationMatcher(_fatiha);
        expect(matcher.hear('بسم الله الرحمن').reached, 2);
        expect(matcher.hear('بسم الله الرحمن'), (reached: null, misses: 0));
        // The recogniser thinks again of a word it gave.
        expect(matcher.hear('بسم الله'), (reached: null, misses: 0));
        expect(matcher.hear('بسم الله الرحمن الرحيم').reached, 3);
      },
    );

    test('many words at once move on to the last of them', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(
        matcher.hear(
          'بسم الله الرحمن الرحيم الحمد لله رب العالمين الرحمن الرحيم',
        ),
        (reached: 9, misses: 0),
      );
    });

    test('after a pause a new phrase carries on from the place', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله الرحمن').reached, 2);
      expect(matcher.hear(''), (reached: null, misses: 0));
      // «ٱلرَّحِيمِ» is two letters from «ٱلرَّحْمَٰنِ», the word before it.
      expect(matcher.hear('الرحيم'), (reached: 3, misses: 0));
      expect(matcher.hear('الرحيم الحمد لله').reached, 5);
    });

    test('a word left out is not stepped over', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله').reached, 1);
      // «ٱلرَّحْمَٰنِ» left out.
      expect(matcher.hear('بسم الله الرحيم'), (reached: null, misses: 1));
      expect(matcher.hear('بسم الله الرحيم الحمد'), (reached: null, misses: 2));
      expect(matcher.expected, 2);
      // Read rightly, from the word left out: on it goes.
      expect(matcher.hear(''), (reached: null, misses: 0));
      expect(matcher.hear('الرحمن'), (reached: 2, misses: 0));
      expect(matcher.hear('الرحمن الرحيم').reached, 3);
    });

    test('words from lines ahead do not carry the place there', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله').reached, 1);
      expect(matcher.hear(''), (reached: null, misses: 0));
      expect(matcher.hear('غير المغضوب عليهم ولا الضالين'), (
        reached: null,
        misses: 5,
      ));
      expect(matcher.expected, 2);
    });

    test('another word in place of the one expected is a miss; a word '
        'too many is not', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(4);
      expect(matcher.hear('الحمد').reached, 4);
      expect(matcher.hear('الحمد كتاب'), (reached: null, misses: 1));
      // «لِلَّهِ» comes after all: the word between was one too many.
      expect(matcher.hear('الحمد كتاب لله'), (reached: 5, misses: 0));
      expect(matcher.hear('الحمد كتاب لله نور'), (reached: null, misses: 1));
      expect(matcher.hear('الحمد كتاب لله نور العالمين'), (
        reached: null,
        misses: 2,
      ));
      expect(matcher.expected, 6);
    });

    test('the isti\'adha and the basmala before the first word are no '
        'mistake; other words are', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(4);
      expect(
        matcher.hear('اعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم'),
        (reached: null, misses: 0),
      );
      expect(
        matcher
            .hear('اعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم الحمد')
            .reached,
        4,
      );
      // The recogniser missed the first word: the reader is told, not left
      // to read on unheard.
      final other = RecitationMatcher(_fatiha);
      expect(other.hear('الله الرحمن'), (reached: null, misses: 0));
      expect(other.hear('الله الرحمن الحمد'), (reached: null, misses: 1));
      expect(other.hear('الله الرحمن الحمد لله'), (reached: null, misses: 2));
      expect(other.expected, 0);
      expect(other.hear(''), (reached: null, misses: 0));
      expect(other.hear('بسم الله').reached, 1);
    });

    test('the last word may be said again', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله').reached, 1);
      expect(matcher.hear('بسم الله الله'), (reached: null, misses: 0));
      expect(matcher.hear(''), (reached: null, misses: 0));
      expect(matcher.hear('الله'), (reached: null, misses: 0));
      expect(matcher.hear('الله الرحمن'), (reached: 2, misses: 0));
    });

    test('a reader goes back with two words in a row from before', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله الرحمن الرحيم الحمد لله').reached, 5);
      expect(matcher.hear(''), (reached: null, misses: 0));
      // One word from before is not enough to go back.
      expect(matcher.hear('الرحمن'), (reached: null, misses: 1));
      expect(matcher.hear('الرحمن الرحيم'), (reached: 3, misses: 0));
      expect(matcher.hear('الرحمن الرحيم الحمد').reached, 4);
    });

    test('moveTo starts elsewhere, and the phrase heard so far is left', () {
      final matcher = RecitationMatcher(_fatiha);
      expect(matcher.hear('بسم الله').reached, 1);
      matcher.moveTo(13);
      expect(matcher.expected, 13);
      expect(matcher.hear('بسم الله'), (reached: null, misses: 0));
      expect(matcher.hear('بسم الله اياك'), (reached: 13, misses: 0));
      expect(matcher.hear('بسم الله اياك نعبد').reached, 14);
    });

    test('a misheard spelling is still the word', () {
      final matcher = RecitationMatcher(_fatiha)..moveTo(7);
      // «ٱلْعَٰلَمِينَ», «مَٰلِكِ» with the alifs a recogniser writes.
      expect(matcher.hear('العالمين الرحمن الرحيم مالك يوم الدين').reached, 12);
    });

    test('pause signs are not words, a word written as two is one', () {
      final matcher = RecitationMatcher(_kursi);
      expect(matcher.hear('الله لا اله الا هو الحي القيوم').reached, 6);
      // The sign after «ٱلْقَيُّومُ» is at 7.
      expect(matcher.expected, 8);
      expect(
        matcher.hear('الله لا اله الا هو الحي القيوم لا تاخذه').reached,
        9,
      );
      expect(matcher.hear(''), (reached: null, misses: 0));
      expect(matcher.hear('سنة ولا نوم').reached, 12);
      expect(matcher.hear(''), (reached: null, misses: 0));
      expect(matcher.hear('له ما في السماوات وما في الارض').reached, 20);
      expect(matcher.hear(''), (reached: null, misses: 0));
      // «بِإِذْنِهِۦ» heard as «ب اذنه».
      expect(matcher.hear('من ذا الذي يشفع عنده الا ب اذنه').reached, 28);
    });
  });
}
