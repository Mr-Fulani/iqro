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

/// Follows a recitation through [words]: each transcript the recogniser
/// reports moves the place on to the word its last words end at.
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

  /// How far ahead of the place a heard word is looked for.
  static const window = 7;

  /// How many of the last heard words are compared.
  static const _tail = 5;

  final _words = <String>[];
  final _indexes = <int>[];

  /// The word expected next, among the words that have letters.
  var _next = 0;

  /// Starts over from the word at [index] of the list given.
  void moveTo(int index) {
    final at = _indexes.indexWhere((item) => item >= index);
    _next = at < 0 ? _words.length : at;
  }

  /// The index of the word the reader has reached, once [transcript] moves
  /// the place; null while it does not.
  int? hear(String transcript) {
    final all = transcript
        .split(RegExp(r'\s+'))
        .map(normalizeArabic)
        .where((word) => word.isNotEmpty)
        .toList();
    if (all.isEmpty) return null;
    final heard = all.length > _tail ? all.sublist(all.length - _tail) : all;

    // The best run of heard words that ends near the place; of equal runs
    // the nearest. It starts at the word read last, so a transcript heard
    // already stays where it is.
    var best = -1;
    var bestRun = (count: 0, score: 0);
    final from = _next > 0 ? _next - 1 : 0;
    for (var at = from; at < _words.length && at <= _next + window; at++) {
      final run = _run(heard, at);
      if (run.score > bestRun.score) {
        best = at;
        bestRun = run;
      }
    }
    final accepted =
        best >= _next &&
        (best == _next ||
            bestRun.count >= 2 ||
            // One word skipped or misheard, and not a particle met everywhere.
            (best == _next + 1 && _words[best].length >= 3));
    if (accepted) return _reach(best);
    if (best >= 0 && best == _next - 1) return null;

    // Lost: three words in a row anywhere, the nearest ahead first.
    if (heard.length < 3) return null;
    int? found;
    for (var at = 0; at < _words.length; at++) {
      if (_run(heard, at).count < 3) continue;
      if (at >= _next) return _reach(at);
      found = at;
    }
    return found == null || found == _next - 1 ? null : _reach(found);
  }

  int _reach(int at) {
    _next = at + 1;
    return _indexes[at];
  }

  /// How many written words, back from the one at [at], the last heard
  /// words match, and how well: a word heard as written counts twice a
  /// word that is only like it. A recogniser may write one of them as two.
  ({int count, int score}) _run(List<String> heard, int at) {
    var index = heard.length - 1;
    var count = 0;
    var score = 0;
    while (index >= 0 && at - count >= 0) {
      final written = _words[at - count];
      if (similarArabic(heard[index], written)) {
        score += heard[index] == written ? 2 : 1;
        index -= 1;
      } else if (index > 0 &&
          similarArabic(heard[index - 1] + heard[index], written)) {
        score += 1;
        index -= 2;
      } else {
        break;
      }
      count += 1;
    }
    return (count: count, score: score);
  }
}
