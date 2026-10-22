import 'package:flutter/painting.dart';

import '../../core/utils/json_helpers.dart';

/// QF Mushaf 19 (QCF V4 tajweed): the markup follows its words and pages.
const tajweedMushafId = 19;

/// Texts of a rule in the interface languages (ru, en, ar, tr).
typedef TajweedTexts = Map<String, String>;

String tajweedText(TajweedTexts texts, String locale) =>
    texts[locale] ?? texts['en'] ?? texts['ru'] ?? '';

TajweedTexts _texts(Object? value) => {
  for (final MapEntry(:key, :value) in jsonMap(value).entries)
    if (value is String) key: value,
};

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Tajweed $key is missing');
  }
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Tajweed $key is missing');
  return value;
}

List<Map<String, Object?>> _list(Object? value) =>
    (value as List? ?? const []).map(jsonMap).toList(growable: false);

class TajweedVariant {
  const TajweedVariant({
    required this.code,
    required this.name,
    required this.why,
    required this.how,
  });

  factory TajweedVariant.fromJson(Map<String, Object?> json) => TajweedVariant(
    code: _string(json, 'code'),
    name: _texts(json['name']),
    why: _texts(json['why']),
    how: _texts(json['how']),
  );

  final String code;
  final TajweedTexts name;
  final TajweedTexts why;
  final TajweedTexts how;
}

class TajweedRule extends TajweedVariant {
  const TajweedRule({
    required super.code,
    required super.name,
    required super.why,
    required super.how,
    required this.arabicName,
    required this.color,
    this.variants = const [],
  });

  factory TajweedRule.fromJson(Map<String, Object?> json) {
    final color = _string(json, 'color');
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      throw const FormatException('Tajweed rule colour is invalid');
    }
    final base = TajweedVariant.fromJson(json);
    return TajweedRule(
      code: base.code,
      name: base.name,
      why: base.why,
      how: base.how,
      arabicName: _string(json, 'arabic_name'),
      color: Color(0xff000000 | int.parse(color.substring(1), radix: 16)),
      variants: _list(json['variants']).map(TajweedVariant.fromJson).toList(),
    );
  }

  final String arabicName;

  /// The rule's colour in the QCF V4 tajweed Mushaf palette.
  final Color color;
  final List<TajweedVariant> variants;

  TajweedVariant? variant(String? code) =>
      variants.where((item) => item.code == code).firstOrNull;
}

/// The rule reference. Its order is the order of every legend.
class TajweedReference {
  const TajweedReference({required this.reviewStatus, required this.rules});

  factory TajweedReference.fromJson(Map<String, Object?> json) =>
      TajweedReference(
        reviewStatus: json['review_status']?.toString() ?? '',
        rules: _list(json['rules']).map(TajweedRule.fromJson).toList(),
      );

  final String reviewStatus;
  final List<TajweedRule> rules;

  bool get pendingReview => reviewStatus == 'pending_teacher_review';

  TajweedRule? rule(String code) =>
      rules.where((item) => item.code == code).firstOrNull;

  /// Rules in legend order, limited to [codes].
  List<TajweedRule> present(Iterable<String> codes) {
    final wanted = codes.toSet();
    return rules.where((rule) => wanted.contains(rule.code)).toList();
  }
}

/// A rule inside one word: [start] and [end] are offsets into the word text.
class TajweedFragment {
  const TajweedFragment({
    required this.code,
    required this.start,
    required this.end,
    this.joinsPrevious = false,
    this.joinsNext = false,
    this.variant,
  });

  factory TajweedFragment.fromJson(Map<String, Object?> json) {
    final start = _int(json, 'start');
    final end = _int(json, 'end');
    if (start < 0 || end <= start) {
      throw const FormatException('Tajweed fragment bounds are invalid');
    }
    return TajweedFragment(
      code: _string(json, 'code'),
      start: start,
      end: end,
      joinsPrevious: json['joins_previous'] == true,
      joinsNext: json['joins_next'] == true,
      variant: json['variant'] is String ? json['variant'] as String : null,
    );
  }

  final String code;
  final int start;
  final int end;

  /// The rule continues from the end of the previous word.
  final bool joinsPrevious;

  /// The rule continues into the start of the next word.
  final bool joinsNext;
  final String? variant;
}

class TajweedWord {
  const TajweedWord({
    required this.position,
    required this.text,
    required this.rules,
  });

  factory TajweedWord.fromJson(Map<String, Object?> json) {
    final position = _int(json, 'position');
    if (position < 1) throw const FormatException('Tajweed word position');
    return TajweedWord(
      position: position,
      text: _string(json, 'text'),
      rules: _list(json['rules']).map(TajweedFragment.fromJson).toList(),
    );
  }

  /// Quran.Foundation `position_in_verse`: the same word as its V4 glyph.
  final int position;
  final String text;
  final List<TajweedFragment> rules;
}

class TajweedAyah {
  const TajweedAyah({
    required this.surah,
    required this.ayah,
    required this.page,
    required this.rules,
    required this.words,
  });

  factory TajweedAyah.fromJson(Map<String, Object?> json) {
    final surah = _int(json, 'surah_number');
    final ayah = _int(json, 'ayah_number');
    if (json['verse_key'] != '$surah:$ayah') {
      throw const FormatException('Tajweed ayah key mismatch');
    }
    return TajweedAyah(
      surah: surah,
      ayah: ayah,
      page: _int(json, 'page_number'),
      rules: (json['rules'] as List? ?? const []).whereType<String>().toList(),
      words: _list(json['words']).map(TajweedWord.fromJson).toList(),
    );
  }

  final int surah;
  final int ayah;
  final int page;
  final List<String> rules;

  /// Only the words that carry rules.
  final List<TajweedWord> words;

  String get verseKey => '$surah:$ayah';

  TajweedWord? word(int position) =>
      words.where((item) => item.position == position).firstOrNull;
}

/// The rules of one QF Mushaf 19 page.
class TajweedPage {
  const TajweedPage({
    required this.number,
    required this.rules,
    required this.ayahs,
  });

  factory TajweedPage.fromJson(Map<String, Object?> json, int number) {
    if (json['page_number'] != number) {
      throw const FormatException('Tajweed page identity mismatch');
    }
    return TajweedPage(
      number: number,
      rules: (json['rules'] as List? ?? const []).whereType<String>().toList(),
      ayahs: _list(json['ayahs']).map(TajweedAyah.fromJson).toList(),
    );
  }

  final int number;
  final List<String> rules;
  final List<TajweedAyah> ayahs;

  TajweedAyah? ayah(String verseKey) =>
      ayahs.where((item) => item.verseKey == verseKey).firstOrNull;
}

/// A word and the fragments of one rule it carries.
typedef TajweedPart = ({
  TajweedAyah ayah,
  TajweedWord word,
  List<TajweedFragment> fragments,
});

/// Splits [text] into runs for colouring. Where rules nest (a silent alef
/// inside a madd), the narrower rule wins, as in the coloured Mushaf.
List<({String text, String? code})> tajweedRuns(
  String text,
  Iterable<TajweedFragment> fragments,
) {
  final codes = List<String?>.filled(text.length, null);
  final widths = List<int?>.filled(text.length, null);
  for (final fragment in fragments) {
    final width = fragment.end - fragment.start;
    for (var i = fragment.start; i < fragment.end && i < text.length; i++) {
      if (widths[i] == null || width < widths[i]!) {
        widths[i] = width;
        codes[i] = fragment.code;
      }
    }
  }
  // A run never starts on a vowel mark: the mark stays with its letter, so
  // the word keeps its shape (QF marks «د» of أَحَدُۢ without its damma).
  final runs = <({String text, String? code})>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length ||
        (codes[i] != codes[start] && !_combiningMark.hasMatch(text[i]))) {
      runs.add((text: text.substring(start, i), code: codes[start]));
      start = i;
    }
  }
  return runs;
}

final _combiningMark = RegExp(r'\p{M}', unicode: true);

/// The word's own part of [fragment]'s rule plus the neighbouring word the
/// rule continues into, in reading order.
List<TajweedPart> tajweedJoinedParts(
  TajweedAyah ayah,
  TajweedWord word,
  TajweedFragment fragment,
) {
  TajweedPart? neighbour(int position, bool previous) {
    final other = ayah.word(position);
    final part = other?.rules
        .where(
          (item) =>
              item.code == fragment.code &&
              (previous ? item.joinsNext : item.joinsPrevious),
        )
        .firstOrNull;
    return other == null || part == null
        ? null
        : (ayah: ayah, word: other, fragments: [part]);
  }

  return [
    if (fragment.joinsPrevious) ?neighbour(word.position - 1, true),
    (ayah: ayah, word: word, fragments: [fragment]),
    if (fragment.joinsNext) ?neighbour(word.position + 1, false),
  ];
}

/// Every place [code] occurs; a rule spanning two words is one occurrence.
List<List<TajweedPart>> tajweedOccurrences(
  Iterable<TajweedAyah> ayahs,
  String code,
) => [
  for (final ayah in ayahs)
    for (final word in ayah.words)
      for (final fragment in word.rules)
        if (fragment.code == code && !fragment.joinsPrevious)
          tajweedJoinedParts(ayah, word, fragment),
];

/// One step of an ayah's tajweed breakdown: one rule in one place.
typedef TajweedStep = ({
  String code,
  String? variant,

  /// The step's word and, for a rule crossing into the next word, that word.
  List<TajweedPart> parts,
});

/// The steps of a breakdown in reading order, as on the web: several rules of
/// one word are several steps; a rule crossing a word boundary is one step.
List<TajweedStep> tajweedSteps(TajweedAyah ayah, TajweedReference reference) {
  final words = [...ayah.words]
    ..sort((left, right) => left.position.compareTo(right.position));
  return [
    for (final word in words)
      for (final fragment in word.rules)
        if (reference.rule(fragment.code) != null)
          if (tajweedJoinedParts(ayah, word, fragment) case final parts
              when parts.first.word == word)
            (code: fragment.code, variant: fragment.variant, parts: parts),
  ];
}

/// The rules a breakdown met, in order of first appearance, with their steps.
List<({String code, List<int> steps})> tajweedStepRules(
  List<TajweedStep> steps,
) {
  final rules = <String, List<int>>{};
  for (final (index, step) in steps.indexed) {
    rules.putIfAbsent(step.code, () => []).add(index);
  }
  return [
    for (final MapEntry(:key, :value) in rules.entries)
      (code: key, steps: value),
  ];
}

/// `[start, end)` of a step's words in the reciter's track, from the first
/// word to the last; null when one of them is not timed.
({Duration start, Duration end})? tajweedStepTiming(
  Map<int, ({Duration start, Duration end})> words,
  TajweedStep step,
) {
  final first = words[step.parts.first.word.position];
  final last = words[step.parts.last.word.position];
  return first == null || last == null || last.end <= first.start
      ? null
      : (start: first.start, end: last.end);
}

/// The word sounding at [position] of the reciter's track, if it is timed.
int? tajweedTimedPosition(
  Map<int, ({Duration start, Duration end})> words,
  Duration position,
) {
  for (final MapEntry(:key, :value) in words.entries) {
    if (value.start <= position && position < value.end) return key;
  }
  return null;
}
