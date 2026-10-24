import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/courses/course_notes_view.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'course_test_data.dart';

const _isolateStart = '\u2068';
const _isolateEnd = '\u2069';

Future<void> _pump(
  WidgetTester tester,
  List<NoteBlock> blocks, {
  String locale = 'ru',
}) => tester.pumpWidget(
  MaterialApp(
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: IqroTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(child: CourseNotesView(blocks: blocks)),
    ),
  ),
);

/// The leaf spans of a block's text with the style each one ends up with.
List<(String, TextStyle)> _leaves(InlineSpan root) {
  final leaves = <(String, TextStyle)>[];
  void walk(InlineSpan span, TextStyle style) {
    if (span is! TextSpan) return;
    final merged = style.merge(span.style);
    if (span.text case final text? when text.isNotEmpty) {
      leaves.add((text, merged));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, merged);
    }
  }

  walk(root, const TextStyle());
  return leaves;
}

/// What a block is expected to show, segment by segment; headings are bold
/// as a whole.
Iterable<({String text, bool arabic, bool bold})> _segments(
  Map<Object?, Object?> block,
) sync* {
  final heading = block['type'] == 'heading';
  final lines = switch (block['type']) {
    'heading' => [block['text']],
    'list' => block['items']! as List,
    _ => block['lines']! as List,
  };
  for (final line in lines) {
    for (final segment in (line! as List).cast<Map<Object?, Object?>>()) {
      yield (
        text: segment['text']! as String,
        arabic: segment['lang'] == 'ar',
        bold: heading || segment['bold'] == true,
      );
    }
  }
}

void main() {
  final cases =
      ((courseDocsJson('notes-markup.cases.json')! as Map)['cases']! as List)
          .cast<Map<Object?, Object?>>();

  test('the shared cases cover every block type and both directions', () {
    final blocks = [
      for (final item in cases) ...(item['blocks']! as List).cast<Map>(),
    ];
    expect(blocks.map((block) => block['type']).toSet(), {
      'heading',
      'paragraph',
      'list',
      'quote',
      'note',
    });
    expect(blocks.map((block) => block['dir']).toSet(), {'ltr', 'rtl'});
  });

  for (final item in cases) {
    testWidgets('draws the case «${item['name']}»', (tester) async {
      final expected = (item['blocks']! as List).cast<Map<Object?, Object?>>();
      final blocks = parseNoteBlocks(expected);
      await _pump(tester, blocks);

      // One rich text per block, list items one each.
      final texts = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(CourseNotesView),
              matching: find.byType(RichText),
            ),
          )
          // Not the glyph of the «Important» icon.
          .where((text) => text.text.style?.fontFamily != 'MaterialIcons')
          .toList();
      final drawn = <(String, TextStyle)>[
        for (final text in texts) ..._leaves(text.text),
      ];
      final shown = drawn.where((leaf) => leaf.$1 != '\n').toList();

      final segments = [for (final block in expected) ..._segments(block)];
      final labels = <String>[];
      for (final block in expected) {
        if (block['type'] == 'list' && block['ordered'] == true) {
          for (
            var index = 1;
            index <= (block['items']! as List).length;
            index++
          ) {
            labels.add('$index.');
          }
        }
        if (block case {'type': 'quote', 'source': final String s}) {
          labels.add('— $s');
        }
        if (block['type'] == 'note') labels.add('Важно');
      }
      expect(
        shown.map((leaf) => leaf.$1).where((text) => !labels.contains(text)),
        [
          for (final segment in segments)
            segment.arabic
                ? '$_isolateStart${segment.text}$_isolateEnd'
                : segment.text,
        ],
      );
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      var index = 0;
      for (final leaf in shown.where((leaf) => !labels.contains(leaf.$1))) {
        final segment = segments[index++];
        expect(
          leaf.$2.fontFamily == IqroTheme.arabicFontFamily,
          segment.arabic,
          reason: '${leaf.$1}: Arabic font',
        );
        expect(
          leaf.$2.fontWeight == FontWeight.w700,
          segment.bold,
          reason: '${leaf.$1}: weight',
        );
      }

      // Each block in its own direction.
      final directions = [
        for (final block in expected)
          for (final _
              in block['type'] == 'list'
                  ? block['items']! as List
                  : const [null])
            block['dir'] == 'rtl' ? TextDirection.rtl : TextDirection.ltr,
      ];
      final paragraphs = [
        for (final text in texts)
          if (!labels.contains(text.text.toPlainText()))
            tester.renderObject<RenderParagraph>(find.byWidget(text)),
      ];
      expect(
        paragraphs.map((paragraph) => paragraph.textDirection),
        directions,
      );
    });
  }

  testWidgets('a right-to-left block starts at the right edge', (tester) async {
    final blocks = parseNoteBlocks([
      {
        'type': 'paragraph',
        'dir': 'rtl',
        'lines': [
          [
            {'text': 'بسم الله', 'lang': 'ar'},
          ],
        ],
      },
      {
        'type': 'list',
        'dir': 'rtl',
        'ordered': true,
        'items': [
          [
            {'text': 'الصوم', 'lang': 'ar'},
          ],
        ],
      },
      {
        'type': 'paragraph',
        'dir': 'ltr',
        'lines': [
          [
            {'text': 'Пост'},
          ],
        ],
      },
    ]);
    await _pump(tester, blocks);
    // Where the glyphs are, inside the paragraph that fills the width.
    (double, double, double) span(Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      );
      return (
        boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b),
        boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b),
        paragraph.size.width,
      );
    }

    final (arabicLeft, arabicRight, arabicWidth) = span(
      find.textContaining('بسم الله'),
    );
    expect(arabicRight, closeTo(arabicWidth, 1));
    expect(arabicLeft, greaterThan(arabicWidth / 2));
    final (latinLeft, _, _) = span(find.text('Пост'));
    expect(latinLeft, closeTo(0, 1));
    // The number of an Arabic list item is on the right of the item.
    final number = tester.getRect(find.text('1.'));
    final item = tester.getRect(find.textContaining('الصوم'));
    expect(number.left, greaterThan(item.right - 1));
  });

  testWidgets('the Arabic run in Russian text keeps the sentence order', (
    tester,
  ) async {
    final blocks = parseNoteBlocks([
      {
        'type': 'paragraph',
        'dir': 'ltr',
        'lines': [
          [
            {'text': 'Пост ('},
            {'text': 'الصوم', 'lang': 'ar'},
            {'text': ') — обязанность.'},
          ],
        ],
      },
    ]);
    await _pump(tester, blocks);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final text = paragraph.text.toPlainText();
    Rect box(String part) {
      final start = text.indexOf(part);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + part.length),
      );
      return boxes
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b));
    }

    final opening = box('(');
    final word = box('الصوم');
    final closing = box(')');
    expect(opening.right, lessThanOrEqualTo(word.left + 1));
    expect(word.right, lessThanOrEqualTo(closing.left + 1));
  });
}
