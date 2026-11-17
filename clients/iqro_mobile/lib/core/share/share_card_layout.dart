import 'dart:convert';
import 'dart:ui';

/// The share card's measures, read from `assets/share_card/layout.json`: a
/// copy of `docs/share-card/layout.json`, which the site reads too. Sizes are
/// pixels of a canvas 1080 wide.
class ShareCardLayout {
  ShareCardLayout._(this._json);

  factory ShareCardLayout.parse(String source) =>
      ShareCardLayout._(jsonDecode(source) as Map<String, Object?>);

  final Map<String, Object?> _json;

  Map<String, Object?> _map(String key) => _json[key]! as Map<String, Object?>;
  double _number(String key) => (_json[key]! as num).toDouble();

  List<String> get colours => (_json['colours']! as List).cast<String>();
  double get inset => _number('inset');
  double get gap => _number('gap');
  int get steps => (_json['steps']! as num).toInt();
  int get seriesStep => (_json['seriesStep']! as num).toInt();
  int get maxCards => (_json['maxCards']! as num).toInt();
  Color get ink => _colour(_json['ink']! as String, 1);

  ShareCardTextMeasures get arabic => ShareCardTextMeasures(_map('arabic'));
  ShareCardTextMeasures get translation =>
      ShareCardTextMeasures(_map('translation'));

  double reference(String key) => (_map('reference')[key]! as num).toDouble();
  double signature(String key) => (_map('signature')[key]! as num).toDouble();
  String get signatureText => _map('signature')['text']! as String;
  double divider(String key) => (_map('divider')[key]! as num).toDouble();

  Shadow get shadow {
    final shadow = _map('shadow');
    double value(String key) => (shadow[key]! as num).toDouble();
    return Shadow(
      color: _colour(shadow['color']! as String, value('opacity')),
      offset: Offset(value('dx'), value('dy')),
      blurRadius: value('blur'),
    );
  }

  /// The canvas of a format, in pixels.
  Size size(ShareCardFormat format) {
    final entry = _map('formats')[format.name]! as Map<String, Object?>;
    return Size(
      (entry['width']! as num).toDouble(),
      (entry['height']! as num).toDouble(),
    );
  }

  /// The text area of a format, inside the frame and its inset.
  Rect field(ShareCardFormat format) {
    final entry = _map('formats')[format.name]! as Map<String, Object?>;
    final field = entry['field']! as Map<String, Object?>;
    double edge(String key) => (field[key]! as num).toDouble();
    final canvas = size(format);
    return Rect.fromLTRB(
      edge('left') * canvas.width,
      edge('top') * canvas.height,
      edge('right') * canvas.width,
      edge('bottom') * canvas.height,
    ).deflate(inset);
  }

  /// The reference and the signature under the text, with the gap above.
  double get tailHeight =>
      gap +
      reference('size') * reference('lineHeight') +
      signature('gap') +
      signature('size') * signature('lineHeight');

  static Color _colour(String hex, double opacity) => Color(
    int.parse(hex.substring(1), radix: 16) | 0xFF000000,
  ).withValues(alpha: opacity);
}

class ShareCardTextMeasures {
  ShareCardTextMeasures(Map<String, Object?> json)
    : max = (json['max']! as num).toDouble(),
      min = (json['min']! as num).toDouble(),
      seriesMax = (json['seriesMax']! as num).toDouble(),
      lineHeight = (json['lineHeight']! as num).toDouble();

  final double max;
  final double min;
  final double seriesMax;
  final double lineHeight;
}

/// The picture's shape: a story (9:16) or a post (4:5).
enum ShareCardFormat { story, post }

/// A line: the words from [start] up to, not including, [end].
typedef ShareCardLine = ({int start, int end});

/// One card of a text. A card of a series has the Arabic or the meaning;
/// the other's size is 0 and its lines are empty.
class ShareCardPage {
  const ShareCardPage({
    this.arabicSize = 0,
    this.arabicLines = const [],
    this.translationSize = 0,
    this.translationLines = const [],
  });

  final double arabicSize;
  final List<ShareCardLine> arabicLines;
  final double translationSize;
  final List<ShareCardLine> translationLines;
}

/// The widths of a text's words and of the space between them, in em.
typedef ShareCardWords = ({List<double> widths, double space});

/// Greedy wrap of whole words; a word wider than the line gets a line of its
/// own.
List<ShareCardLine> wrapShareCardWords(ShareCardWords words, double limit) {
  final lines = <ShareCardLine>[];
  var start = 0;
  var lineWidth = 0.0;
  for (final (index, width) in words.widths.indexed) {
    if (index > start && lineWidth + words.space + width > limit) {
      lines.add((start: start, end: index));
      start = index;
      lineWidth = 0;
    }
    lineWidth += (index > start ? words.space : 0) + width;
  }
  if (words.widths.length > start) {
    lines.add((start: start, end: words.widths.length));
  }
  return lines;
}

/// The same number of lines at the narrowest width that keeps it: lines of
/// like length.
List<ShareCardLine> _balancedLines(ShareCardWords words, double limit) {
  final lines = wrapShareCardWords(words, limit);
  if (lines.length < 2) return lines;
  var low = words.widths.reduce((a, b) => a > b ? a : b);
  var high = limit;
  var best = lines;
  for (var step = 0; step < 14 && low < high; step += 1) {
    final middle = (low + high) / 2;
    final candidate = wrapShareCardWords(words, middle);
    if (candidate.length == lines.length) {
      best = candidate;
      high = middle;
    } else {
      low = middle;
    }
  }
  return best;
}

// The largest size that needs the fewest cards, and its lines card by card,
// as evenly as they divide.
({double size, List<List<ShareCardLine>> cards}) _paginate(
  ShareCardWords words,
  double fieldWidth,
  double available,
  ShareCardTextMeasures measures,
  int step,
) {
  var size = measures.min;
  var lines = const <ShareCardLine>[];
  int? count;
  for (var next = measures.min; next <= measures.seriesMax; next += step) {
    final wrapped = wrapShareCardWords(words, fieldWidth / next);
    final perCard = (available / (next * measures.lineHeight)).floor();
    final cards = (wrapped.length / (perCard < 1 ? 1 : perCard)).ceil();
    if (count == null || cards <= count) {
      size = next;
      lines = wrapped;
      count = cards;
    }
  }
  final base = lines.length ~/ count!;
  final extra = lines.length % count;
  final cards = <List<ShareCardLine>>[];
  var from = 0;
  for (var card = 0; card < count; card += 1) {
    final length = base + (card < extra ? 1 : 0);
    cards.add(lines.sublist(from, from + length));
    from += length;
  }
  return (size: size, cards: cards);
}

/// The cards of a text: one where the Arabic and the meaning fit together,
/// shrinking both in step; else the Arabic on its cards and the meaning on
/// its own. Null when it takes more cards than a series may have. The site
/// runs the same steps (lib/share-card-compose.ts); both pass
/// docs/share-card/fixtures.json.
List<ShareCardPage>? composeShareCard(
  ShareCardLayout layout,
  ShareCardFormat format,
  ShareCardWords arabic,
  ShareCardWords translation,
) {
  final field = layout.field(format);
  final tail = layout.tailHeight;
  final hasTranslation = translation.widths.isNotEmpty;
  final middle = hasTranslation
      ? layout.gap * 2 + layout.divider('height')
      : 0.0;
  for (var step = 0; step <= layout.steps; step += 1) {
    final shrink = step / layout.steps;
    double size(ShareCardTextMeasures measures) =>
        (measures.max - (measures.max - measures.min) * shrink).roundToDouble();
    final arabicSize = size(layout.arabic);
    final translationSize = size(layout.translation);
    final arabicLines = wrapShareCardWords(arabic, field.width / arabicSize);
    final translationLines = wrapShareCardWords(
      translation,
      field.width / translationSize,
    );
    final height =
        arabicLines.length * arabicSize * layout.arabic.lineHeight +
        middle +
        translationLines.length *
            translationSize *
            layout.translation.lineHeight +
        tail;
    if (height <= field.height) {
      return [
        ShareCardPage(
          arabicSize: arabicSize,
          arabicLines: _balancedLines(arabic, field.width / arabicSize),
          translationSize: translationSize,
          translationLines: _balancedLines(
            translation,
            field.width / translationSize,
          ),
        ),
      ];
    }
  }
  final available = field.height - tail;
  final arabicCards = _paginate(
    arabic,
    field.width,
    available,
    layout.arabic,
    layout.seriesStep,
  );
  final pages = <ShareCardPage>[
    for (final lines in arabicCards.cards)
      ShareCardPage(arabicSize: arabicCards.size, arabicLines: lines),
  ];
  if (hasTranslation) {
    final cards = _paginate(
      translation,
      field.width,
      available,
      layout.translation,
      layout.seriesStep,
    );
    pages.addAll([
      for (final lines in cards.cards)
        ShareCardPage(translationSize: cards.size, translationLines: lines),
    ]);
  }
  return pages.length > layout.maxCards ? null : pages;
}
