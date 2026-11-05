import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Arabic lines filled to both edges as a printed Mushaf fills them: by
/// drawing out the joins between letters (kashida, «ـ»), not by widening
/// the spaces between words.

final _mark = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]');
final _letter = RegExp('[ؠ-يٱ-ۓ]');
final _notLetters = RegExp('[^ؠ-يٱ-ۓ]');
final _allah = RegExp(r'^(ٱ|ا|و|ب|ف)?(ٱ|ا)?لله$');

/// Letters that join only the letter before them.
const _rightJoining = 'اأإآٱدذرزوؤةى';
const _alefs = 'اأإآٱ';
const tatweel = 'ـ';

bool _joinsNext(String letter) =>
    _letter.hasMatch(letter) &&
    !_rightJoining.contains(letter) &&
    letter != 'ء';

bool _joinsPrevious(String letter) => _letter.hasMatch(letter) && letter != 'ء';

/// Where a kashida may go in [word], as offsets into it: between two joined
/// letters, after the first one's marks. Never inside lam-alef, which is one
/// shape, nor in the name of Allah.
List<int> kashidaSpots(String word) {
  if (_allah.hasMatch(word.replaceAll(_notLetters, ''))) return const [];
  final bases = <int>[
    for (var i = 0; i < word.length; i++)
      if (!_mark.hasMatch(word[i])) i,
  ];
  final spots = <int>[];
  for (var b = 0; b < bases.length - 1; b++) {
    final letter = word[bases[b]];
    final next = word[bases[b + 1]];
    if (!_joinsNext(letter) || !_joinsPrevious(next)) continue;
    if (letter == 'ل' && _alefs.contains(next)) continue;
    spots.add(bases[b + 1]);
  }
  return spots;
}

String stretchWord(String word, int spot, int count) =>
    word.substring(0, spot) + tatweel * count + word.substring(spot);

/// One paragraph laid out by [kashidaLayout]: its words, drawn out, and the
/// words a line ends after.
class KashidaLayout {
  const KashidaLayout(this.words, this.breaks);

  final List<String> words;
  final Set<int> breaks;
}

final _widths = <(String, double, double, String?), double>{};

double _measure(String text, TextStyle? style, TextScaler scaler) {
  final key = (text, style?.fontSize ?? 14, scaler.scale(1), style?.fontFamily);
  final known = _widths[key];
  if (known != null) return known;
  if (_widths.length > 6000) _widths.clear();
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.rtl,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return _widths[key] = width;
}

/// Breaks [words] into lines no wider than [width] and draws out the joins
/// of each line but the last until it reaches the edge. [marker] follows the
/// last word: it is measured with it, and not drawn out.
KashidaLayout kashidaLayout({
  required List<String> words,
  required TextStyle? style,
  required double width,
  TextScaler scaler = TextScaler.noScaling,
  String marker = '',
}) {
  if (words.isEmpty || width <= 0) return KashidaLayout(words, const {});
  double measure(String text) => _measure(text, style, scaler);
  final space = measure('ب ب') - 2 * measure('ب');
  double wordWidth(int index, String text) =>
      measure(index == words.length - 1 ? text + marker : text);

  final lines = <List<int>>[];
  var line = <int>[];
  var used = 0.0;
  for (var i = 0; i < words.length; i++) {
    final w = wordWidth(i, words[i]);
    if (line.isNotEmpty && used + space + w > width) {
      lines.add(line);
      line = <int>[];
      used = 0;
    }
    used += line.isEmpty ? w : space + w;
    line.add(i);
  }
  lines.add(line);

  final out = List<String>.of(words);
  final breaks = <int>{};
  final cap = math.max(3, ((style?.fontSize ?? 14) / 8).round());
  for (final (n, line) in lines.indexed) {
    if (n == lines.length - 1) break;
    breaks.add(line.last);
    if (line.length < 2) continue;
    final spots = <int, int>{
      for (final i in line)
        if (kashidaSpots(words[i]) case final found when found.isNotEmpty)
          i: found.last,
    };
    final counts = <int, int>{for (final i in spots.keys) i: 0};
    var total =
        line.fold(0.0, (sum, i) => sum + wordWidth(i, words[i])) +
        space * (line.length - 1);
    var grew = true;
    while (grew) {
      grew = false;
      // Longer words first, one stroke each, round after round.
      final order = spots.keys.where((i) => counts[i]! < cap).toList()
        ..sort((a, b) => words[b].length.compareTo(words[a].length));
      for (final i in order) {
        final before = wordWidth(i, out[i]);
        final longer = stretchWord(words[i], spots[i]!, counts[i]! + 1);
        final after = wordWidth(i, longer);
        if (total + after - before > width - 1) continue;
        counts[i] = counts[i]! + 1;
        out[i] = longer;
        total += after - before;
        grew = true;
      }
    }
  }
  return KashidaLayout(out, breaks);
}
