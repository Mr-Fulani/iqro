import 'package:flutter/material.dart';

import '../../core/theme/iqro_theme.dart';
import '../tajweed/tajweed_models.dart';
import '../tajweed/tajweed_sheet.dart' show tajweedArabicStyle;
import 'tajweed_course_models.dart';

/// A word with the letters of [occurrence] in the target's colour.
TextSpan tajweedWordSpan(
  TajweedCourseWord word,
  TajweedOccurrence? occurrence,
  TajweedCourseTarget target,
) => TextSpan(
  children: <InlineSpan>[
    for (final run in tajweedRuns(
      word.text,
      occurrence?.fragments(word.position) ?? const [],
    ))
      TextSpan(
        text: run.text,
        style: run.code == null ? null : TextStyle(color: target.color),
      ),
  ],
);

/// The words of an occurrence in reading order, its letters coloured.
TextSpan tajweedOccurrenceSpan(
  TajweedCourseExample example,
  TajweedOccurrence occurrence,
  TajweedCourseTarget target,
) {
  final positions = occurrence.positions;
  final words = [
    for (final word in example.words)
      if (positions.contains(word.position)) word,
  ];
  return TextSpan(
    children: <InlineSpan>[
      for (final (index, word) in words.indexed) ...<InlineSpan>[
        if (index > 0) const TextSpan(text: ' '),
        tajweedWordSpan(word, occurrence, target),
      ],
    ],
  );
}

/// The ayah in Unicode text, right to left. The words of [lit] have the
/// target's tint and underline, their letters its colour. With [buttons]
/// every word is a button for «find the rule».
class TajweedAyahWords extends StatelessWidget {
  const TajweedAyahWords({
    required this.example,
    required this.target,
    this.lit,
    this.buttons = false,
    this.chosen,
    this.wrong = const {},
    this.onWord,
    super.key,
  });

  final TajweedCourseExample example;
  final TajweedCourseTarget target;
  final TajweedOccurrence? lit;
  final bool buttons;

  /// The word the learner tapped last.
  final int? chosen;

  /// Words tapped that have no place of the target.
  final Set<int> wrong;

  /// Null makes the word buttons inactive.
  final ValueChanged<int>? onWord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = tajweedArabicStyle(context, 26).copyWith(height: 2);
    Widget word(TajweedCourseWord word) {
      final inLit = lit?.contains(word.position) ?? false;
      final missed = wrong.contains(word.position);
      final text = Text.rich(
        tajweedWordSpan(word, inLit ? lit : null, target),
        textDirection: TextDirection.rtl,
        style: style,
      );
      final decoration = BoxDecoration(
        color: inLit
            ? target.color.withValues(alpha: .18)
            : missed
            ? scheme.errorContainer
            : buttons
            ? scheme.surface
            : null,
        border: inLit
            ? Border(bottom: BorderSide(color: target.color, width: 2))
            : buttons
            ? Border.all(color: missed ? scheme.error : context.iqroColors.line)
            : null,
        borderRadius: BorderRadius.circular(buttons ? 10 : 6),
      );
      // Not animated: a border between an outline and an underline has
      // sides of two colours, which a rounded box cannot paint.
      final box = Container(
        key: ValueKey(
          '${buttons ? 'tajweed-course-find' : 'tajweed-course-word'}-'
          '${word.position}',
        ),
        // The underline goes below the marks under the letters.
        padding: EdgeInsetsDirectional.fromSTEB(
          buttons ? 8 : 3,
          0,
          buttons ? 8 : 3,
          4,
        ),
        decoration: decoration,
        child: text,
      );
      if (!buttons) return box;
      final onTap = onWord == null ? null : () => onWord!(word.position);
      return Semantics(
        button: true,
        enabled: onTap != null,
        selected: chosen == word.position,
        label: word.text,
        textDirection: TextDirection.rtl,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: box,
        ),
      );
    }

    final words = Wrap(
      textDirection: TextDirection.rtl,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: buttons ? 8 : 4,
      runSpacing: buttons ? 8 : 2,
      children: <Widget>[for (final item in example.words) word(item)],
    );
    return Container(
      key: const ValueKey('tajweed-course-ayah'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: buttons
          ? words
          // The ayah reads as one line of text, not word by word.
          : Semantics(
              label: example.words.map((word) => word.text).join(' '),
              textDirection: TextDirection.rtl,
              excludeSemantics: true,
              child: words,
            ),
    );
  }
}
