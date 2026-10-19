/// One line of a du'a's Arabic text: the du'a itself, or an opening formula
/// (the basmala or the isti'adha) that is read before it.
class DuaArabicPart {
  const DuaArabicPart(this.text, {this.opening = false});

  final String text;
  final bool opening;

  @override
  bool operator ==(Object other) =>
      other is DuaArabicPart && other.text == text && other.opening == opening;

  @override
  int get hashCode => Object.hash(text, opening);

  @override
  String toString() => opening ? 'opening($text)' : 'text($text)';
}

// Harakat, tanwin, shadda, sukun, the dagger alif and Quranic marks may sit
// on any letter, and the sources write the formulas with and without them.
const _marks = '[ً-ٰٟۖ-ۭـ]*';
const _alif = '[اأإآٱ]';

String _letters(String word) => word
    .split('')
    .map((letter) => (letter == 'ا' ? _alif : letter) + _marks)
    .join();

String _phrase(List<String> words) => words.map(_letters).join(r'\s+');

final _openingPattern = RegExp(
  [
    _phrase(<String>['بسم', 'الله', 'الرحمن', 'الرحيم']),
    _phrase(<String>['اعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم']),
  ].join('|'),
);

/// Splits the basmala and the isti'adha off the du'a so they stand on their
/// own lines, as printed in the sources.
List<DuaArabicPart> splitDuaArabic(String text) {
  final parts = <DuaArabicPart>[];
  void addText(String value) {
    // Separators the sources leave around a formula: dots, commas, colons.
    final trimmed = value.replaceAll(RegExp(r'^[\s.,:،؛]+|[\s.,:،؛]+$'), '');
    if (trimmed.isNotEmpty) parts.add(DuaArabicPart(trimmed));
  }

  var start = 0;
  for (final match in _openingPattern.allMatches(text)) {
    addText(text.substring(start, match.start));
    parts.add(DuaArabicPart(match.group(0)!, opening: true));
    start = match.end;
  }
  addText(text.substring(start));
  // A formula with nothing after it is the du'a itself (for example a du'a
  // that is only the basmala), so it keeps the full size.
  if (parts.every((part) => part.opening)) {
    return <DuaArabicPart>[for (final part in parts) DuaArabicPart(part.text)];
  }
  return parts;
}
