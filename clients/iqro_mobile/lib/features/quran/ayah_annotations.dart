import 'package:flutter/material.dart';

import 'quran_models.dart';

const ayahHighlightColorKeys = <String>[
  'yellow',
  'lime',
  'blue',
  'pink',
  'lavender',
];

String normalizeAyahHighlightColor(String? colorKey) {
  return ayahHighlightColorKeys.contains(colorKey) ? colorKey! : 'lime';
}

Color ayahHighlightColor(String? colorKey) {
  return switch (normalizeAyahHighlightColor(colorKey)) {
    'yellow' => Colors.amber.shade300,
    'blue' => Colors.lightBlue.shade300,
    'pink' => Colors.pink.shade300,
    'lavender' => Colors.deepPurple.shade200,
    _ => Colors.lightGreen.shade400,
  };
}

Color ayahHighlightCardColor(BuildContext context, String? colorKey) {
  return Color.alphaBlend(
    ayahHighlightColor(colorKey).withValues(alpha: .22),
    Theme.of(context).colorScheme.surface,
  );
}

Map<QuranAyahReference, String> ayahHighlightColorsFromRows(
  Iterable<Map<String, Object?>> rows,
) {
  final colors = <QuranAyahReference, String>{};
  for (final row in rows) {
    final surah = (row['surah'] as num?)?.toInt();
    final ayah = (row['ayah'] as num?)?.toInt();
    if (surah == null || ayah == null || surah < 1 || ayah < 1) continue;
    final reference = QuranAyahReference(id: '', surah: surah, ayah: ayah);
    if (colors.containsKey(reference)) continue;
    colors[reference] = normalizeAyahHighlightColor(
      row['color_key']?.toString(),
    );
  }
  return Map<QuranAyahReference, String>.unmodifiable(colors);
}
