import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/share/share_card_layout.dart';

void main() {
  final spec = File('../../docs/share-card/layout.json').readAsStringSync();

  test('the app carries the layout of the specification', () {
    expect(File('assets/share_card/layout.json').readAsStringSync(), spec);
  });

  test('texts become the same cards as on the site', () {
    final layout = ShareCardLayout.parse(spec);
    final fixtures =
        jsonDecode(
              File('../../docs/share-card/fixtures.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    ShareCardWords words(Object? json) => (
      widths: ((json! as Map)['widths'] as List)
          .map((width) => (width as num).toDouble())
          .toList(),
      space: ((json as Map)['space'] as num).toDouble(),
    );
    List<List<int>> lines(List<ShareCardLine> lines) => [
      for (final line in lines) [line.start, line.end],
    ];
    for (final item
        in (fixtures['cases']! as List).cast<Map<String, Object?>>()) {
      final pages = composeShareCard(
        layout,
        ShareCardFormat.values.byName(item['format']! as String),
        words(item['arabic']),
        words(item['translation']),
      );
      expect(
        pages
            ?.map(
              (page) => {
                'arabicSize': page.arabicSize,
                'arabicLines': lines(page.arabicLines),
                'translationSize': page.translationSize,
                'translationLines': lines(page.translationLines),
              },
            )
            .toList(),
        item['pages'],
        reason: item['name']! as String,
      );
    }
  });
}
