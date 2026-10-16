import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';
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

void _expectPrintedCartouche(FoundationPageLayout layout, double row) {
  expect(layout.frames, hasLength(1));
  final frame = layout.frames.single;
  // The cartouche spans the text block and stays inside its reserved row.
  expect(frame.left, closeTo(_size.width * .06, .001));
  expect(frame.right, closeTo(_size.width * .94, .001));
  final rowTop = _size.height * .035 + (row - 1) * _rowHeight;
  expect(frame.top, greaterThanOrEqualTo(rowTop));
  expect(frame.bottom, lessThanOrEqualTo(rowTop + _rowHeight));
  final title = layout.decorations.firstWhere(
    (decoration) => decoration.$1.plainText.startsWith('سُورَةُ'),
  );
  expect((title.$2 & title.$1.size).center.dy, closeTo(frame.center.dy, .001));
  expect(title.$1.width, lessThan(frame.width / 2));
}

void main() {
  test('QUL surah_name rows get the cartouche, basmala rows do not', () {
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
    _expectPrintedCartouche(layout, 7);
  });

  test('QUL opening page frames Al-Fatihah in its centred block', () {
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
    _expectPrintedCartouche(layout, 2 + 5.5);
  });

  test('fallback rows frame At-Tawbah, which has no basmala', () {
    final layout = _layout(_page(pageNumber: 187, surah: 9, firstLine: 3));
    expect(layout.decorations.map((d) => d.$1.plainText), ['سُورَةُ التوبة']);
    _expectPrintedCartouche(layout, 1);
  });

  test('fallback rows frame the title above the basmala', () {
    final layout = _layout(_page(pageNumber: 106, surah: 5, firstLine: 3));
    expect(layout.decorations, hasLength(2));
    _expectPrintedCartouche(layout, 1);
  });

  testWidgets('page canvas paints the cartouche beneath the surah title', (
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
    // Paint keeps 8-bit channels, so compare packed colors.
    final band = mushafAccentColor.withValues(alpha: .2).toARGB32();
    bool Function(Symbol, List<dynamic>) banded(Symbol draw) =>
        (method, arguments) =>
            method == draw && (arguments[1] as Paint).color.toARGB32() == band;
    expect(
      find.descendant(
        of: find.byType(FoundationPageCanvas),
        matching: find.byType(CustomPaint),
      ),
      paints
        // Left end cap, patterned middle band, mirrored right end cap…
        ..something(banded(#drawPath))
        ..something(banded(#drawRect))
        ..something(banded(#drawPath))
        // …then the title text on top of the frame.
        ..paragraph(),
    );
    expect(tester.takeException(), isNull);
  });
}
