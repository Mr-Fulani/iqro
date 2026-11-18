/// A trial, off unless the app is built with
/// `--dart-define=RECITATION_FOLLOW=true`: the plain text follows the reader's
/// voice, word by word, with the phone's own speech recognition.
const recitationFollowEnabled = bool.fromEnvironment('RECITATION_FOLLOW');

final _notLetters = RegExp('[^ء-ي]');

/// [text] as bare letters, so the Mushaf's spelling and a recogniser's meet:
/// no vowel or pause marks, one alif, no hamza seats, ta marbuta as ha.
String normalizeArabic(String text) => text
    .replaceAll(RegExp('[آأإٱ]'), 'ا')
    .replaceAll('ؤ', 'و')
    .replaceAll(RegExp('[ئى]'), 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp('[ءـ]'), '')
    .replaceAll(_notLetters, '');

/// Whether a heard word may be the written one: the Mushaf drops alifs a
/// recogniser writes, and a recogniser mishears a letter.
bool similarArabic(String heard, String written) {
  if (heard == written) return true;
  final longest = heard.length > written.length ? heard.length : written.length;
  final allowed = longest <= 2
      ? 0
      : longest <= 6
      ? 1
      : 2;
  if (allowed == 0 || (heard.length - written.length).abs() > allowed) {
    return false;
  }
  return _distance(heard, written) <= allowed;
}

int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current.add(
        [
          previous[j] + cost,
          previous[j + 1] + 1,
          current[j] + 1,
        ].reduce((x, y) => x < y ? x : y),
      );
    }
    previous = current;
  }
  return previous.last;
}

/// What a transcript did to the place: the index of the last word read
/// rightly, when the place moved on to it, and how many words heard since
/// are not the one expected.
typedef RecitationHearing = ({int? reached, int misses});

/// Checks a recitation against [words], word by word, for a reader who
/// tests himself: the place moves on only to the word expected next. A word
/// left out or said as another is not stepped over: the place waits at it,
/// and [RecitationHearing.misses] counts the words heard instead. A reader
/// may say the last word again, or go back and read from two words in a row
/// that came before; to start elsewhere he is put there with [moveTo].
///
/// A recogniser reports a phrase as it grows and may rewrite its last
/// words, so each transcript is read again from where its phrase began.
class RecitationMatcher {
  RecitationMatcher(List<String> words) {
    for (final (index, word) in words.indexed) {
      final letters = normalizeArabic(word);
      // A sign that stands alone is not read aloud.
      if (letters.isEmpty) continue;
      _words.add(letters);
      _indexes.add(index);
    }
  }

  final _words = <String>[];
  final _indexes = <int>[];

  /// The word expected next, among the words that have letters.
  var _next = 0;

  /// Where the place was when the phrase now heard began, and how many of
  /// its first words were heard before the place was put elsewhere.
  var _phraseStart = 0;
  var _phraseSkip = 0;
  var _phrase = const <String>[];

  /// Nothing has been read rightly since the start or [moveTo]: the
  /// isti'adha and the basmala a reader says before the first word are no
  /// mistake then.
  var _fresh = true;

  static final _opening = <String>{
    for (final word
        in 'أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم'.split(' '))
      normalizeArabic(word),
  };

  /// The index of the word expected next; null past the last one.
  int? get expected => _next < _indexes.length ? _indexes[_next] : null;

  /// Puts the place at the word at [index] of the list given: it is the
  /// one expected next.
  void moveTo(int index) {
    final at = _indexes.indexWhere((item) => item >= index);
    _next = at < 0 ? _words.length : at;
    _phraseStart = _next;
    _phraseSkip = _phrase.length;
    _fresh = true;
  }

  RecitationHearing hear(String transcript) {
    final heard = transcript
        .split(RegExp(r'\s+'))
        .map(normalizeArabic)
        .where((word) => word.isNotEmpty)
        .toList();
    // A new phrase: after a pause the recogniser starts its text again.
    if (heard.isEmpty ||
        _phrase.isEmpty ||
        heard.first != _phrase.first ||
        heard.length < _phrase.length - 1) {
      _phraseStart = _next;
      _phraseSkip = 0;
    }
    _phrase = heard;
    if (heard.length <= _phraseSkip) return (reached: null, misses: 0);
    final words = heard.sublist(_phraseSkip);

    var walk = _walk(words, _phraseStart, opening: _fresh);
    // Nothing of the phrase is the word expected, and it begins with two
    // words in a row from before: the reader went back to read again.
    if (walk.at == _phraseStart && words.length >= 2) {
      for (var back = _phraseStart - 1; back >= 0; back--) {
        if (back + 1 < _words.length &&
            similarArabic(words[0], _words[back]) &&
            similarArabic(words[1], _words[back + 1])) {
          _phraseStart = back;
          _next = back;
          walk = _walk(words, back, opening: false);
          break;
        }
      }
    }
    if (walk.at > _phraseStart) _fresh = false;
    if (walk.at > _next) {
      _next = walk.at;
      return (reached: _indexes[_next - 1], misses: walk.misses);
    }
    // A text rewritten shorter says nothing new of the word waited for.
    return (reached: null, misses: walk.at < _next ? 0 : walk.misses);
  }

  /// Reads [heard] from the word at [from]: where the place comes to, and
  /// how many of the last heard words are not the word waited for there.
  /// The last word read rightly may be said again. A recogniser may write
  /// one word as two.
  ({int at, int misses}) _walk(
    List<String> heard,
    int from, {
    required bool opening,
  }) {
    var at = from;
    var misses = 0;
    for (var index = 0; index < heard.length; index++) {
      if (at >= _words.length) break;
      if (similarArabic(heard[index], _words[at])) {
        at += 1;
        misses = 0;
      } else if (index + 1 < heard.length &&
          similarArabic(heard[index] + heard[index + 1], _words[at])) {
        at += 1;
        index += 1;
        misses = 0;
      } else if (at > 0 && similarArabic(heard[index], _words[at - 1])) {
        // Said again.
      } else if (opening &&
          at == from &&
          _opening.any(
            (word) =>
                heard[index].length >= word.length &&
                similarArabic(heard[index], word),
          )) {
        // The isti'adha or the basmala, before the first word.
      } else {
        misses += 1;
      }
    }
    return (at: at, misses: misses);
  }
}
