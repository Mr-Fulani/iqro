import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';

const _size = Size(360, 552);
const _rowHeight = 552 * .93 / 15;

final _surahs = [
  for (final (number, name) in [(1, 'الفاتحة'), (5, 'المائدة'), (9, 'التوبة')])
    Surah(
      id: '$number',
      number: number,
      nameAr: name,
      nameEn: '',
      nameRu: '',
      ayahCount: 7,
      revelationType: '',
    ),
];

FoundationMushafPage _page({
  required int pageNumber,
  required int surah,
  required int firstLine,
  List<Map<String, Object?>>? layoutLines,
}) => FoundationMushafPage.fromJson({
  'mushaf_id': 5,
  'page_number': pageNumber,
  'pages_count': 604,
  'lines_per_page': 15,
  'source_checksum_sha256': 'a' * 64,
  'rendering': {'available': true, 'version': 2, 'mode': 'unicode-font'},
  if (layoutLines != null) 'layout': {'version': 1, 'lines': layoutLines},
  'words': [
    for (var line = firstLine; line <= firstLine + 1; line++)
      for (var index = 1; index <= 3; index++)
        {
          'id': line * 3 + index,
          'verse_key': '$surah:${line - firstLine + 1}',
          'text': 'نَصّ',
          'line_number': line,
          'position_in_verse': index,
          'position_in_page': line * 3 + index,
        },
  ],
}, fromCache: false);

FoundationPageLayout _layout(FoundationMushafPage page) {
  final layout = FoundationPageLayout(
    page,
    FoundationPageResources(),
    _size,
    _surahs,
  );
  addTearDown(layout.dispose);
  return layout;
}

/// Without the source heading font the title stays plain text, centred on
/// its reserved row at the size it had before source headings existed.
void _expectPlainTitle(FoundationPageLayout layout, double row) {
  expect(layout.headers, isEmpty);
  final title = layout.decorations.firstWhere(
    (decoration) => decoration.$1.plainText.startsWith('سُورَةُ'),
  );
  final rowTop = _size.height * .035 + (row - 1) * _rowHeight;
  expect(
    (title.$2 & title.$1.size).center.dy,
    closeTo(rowTop + _rowHeight / 2, .001),
  );
  expect(title.$1.text!.style!.fontSize, closeTo(_size.width * .038, .001));
}

void main() {
  test('QUL surah_name rows keep a plain title above the basmala', () {
    final layout = _layout(
      _page(
        pageNumber: 106,
        surah: 5,
        firstLine: 9,
        layoutLines: [
          {'line_number': 7, 'line_type': 'surah_name', 'surah_number': 5},
          {'line_number': 8, 'line_type': 'basmallah'},
          {'line_number': 9, 'line_type': 'ayah', 'is_centered': false},
          {'line_number': 10, 'line_type': 'ayah', 'is_centered': false},
        ],
      ),
    );
    expect(layout.decorations, hasLength(2));
    _expectPlainTitle(layout, 7);
  });

  test('QUL opening page titles Al-Fatihah in its centred block', () {
    final layout = _layout(
      _page(
        pageNumber: 1,
        surah: 1,
        firstLine: 3,
        layoutLines: [
          {'line_number': 2, 'line_type': 'surah_name', 'surah_number': 1},
          {'line_number': 3, 'line_type': 'ayah', 'is_centered': true},
          {'line_number': 4, 'line_type': 'ayah', 'is_centered': true},
        ],
      ),
    );
    expect(layout.decorations, hasLength(1));
    // Page 1 centres its four source rows: (15 - 4) / 2 rows of offset.
    _expectPlainTitle(layout, 2 + 5.5);
  });

  test('fallback rows title At-Tawbah, which has no basmala', () {
    final layout = _layout(_page(pageNumber: 187, surah: 9, firstLine: 3));
    expect(layout.decorations.map((d) => d.$1.plainText), ['سُورَةُ التوبة']);
    _expectPlainTitle(layout, 1);
  });

  test('fallback rows title the surah above the basmala', () {
    final layout = _layout(_page(pageNumber: 106, surah: 5, firstLine: 3));
    expect(layout.decorations, hasLength(2));
    _expectPlainTitle(layout, 1);
  });

  testWidgets('page canvas paints only text without a source heading', (
    tester,
  ) async {
    final page = _page(
      pageNumber: 187,
      surah: 9,
      firstLine: 2,
      layoutLines: [
        {'line_number': 1, 'line_type': 'surah_name', 'surah_number': 9},
        {'line_number': 2, 'line_type': 'ayah', 'is_centered': false},
        {'line_number': 3, 'line_type': 'ayah', 'is_centered': false},
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: _size,
            child: FoundationPageCanvas(
              page: page,
              resources: FoundationPageResources(),
              selected: null,
              playing: null,
              surahs: _surahs,
              onSelect: (_) {},
              onOpen: (_) {},
              onBackgroundTap: () {},
            ),
          ),
        ),
      ),
    );
    final canvas = find.descendant(
      of: find.byType(FoundationPageCanvas),
      matching: find.byType(CustomPaint),
    );
    expect(canvas, paints..paragraph());
    expect(canvas, isNot(paints..path()));
    expect(tester.takeException(), isNull);
  });
}
