import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
/// The texts of the runs that open a link.
List<String> _links(InlineSpan root) {
  final found = <String>[];
  root.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      found.add(span.text ?? '');
    }
    return true;
  });
  return found;
}

String _shownText(({String text, bool arabic, bool bold, Object? link}) s) =>
    s.arabic ? '$_isolateStart${s.text}$_isolateEnd' : s.text;

Iterable<({String text, bool arabic, bool bold, Object? link})> _segments(
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
      // A note is an icon, not text: its own test follows.
      if (segment['note'] != null) continue;
      yield (
        text: segment['text']! as String,
        arabic: segment['lang'] == 'ar',
        bold: heading || segment['bold'] == true,
        link: segment['link'],
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
          // Not the glyph of the «Important» icon nor of a note's «!» or «?».
          .where((text) => text.text.style?.fontFamily != 'MaterialIcons')
          .where(
            (text) => find
                .ancestor(
                  of: find.byWidget(text),
                  matching: find.byType(NoteMarkButton),
                )
                .evaluate()
                .isEmpty,
          )
          .toList();
      final drawn = <(String, TextStyle)>[
        for (final text in texts) ..._leaves(text.text),
      ];
      // «↗» after a link to another site is checked on its own.
      final shown = drawn
          .where((leaf) => leaf.$1 != '\n' && leaf.$1 != ' ↗')
          .toList();

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
        [for (final segment in segments) _shownText(segment)],
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

      // Every note is its icon, every link a tappable run.
      final notes = [
        for (final block in expected)
          for (final line in switch (block['type']) {
            'heading' => [block['text']],
            'list' => block['items']! as List,
            _ => block['lines']! as List,
          })
            for (final segment in (line! as List).cast<Map<Object?, Object?>>())
              if (segment['note'] case {'kind': final String kind}) kind,
      ];
      expect(
        tester
            .widgetList<NoteMarkButton>(find.byType(NoteMarkButton))
            .map((button) => button.mark.kind.name),
        notes,
      );
      final links = segments.where((segment) => segment.link != null);
      final tappable = [
        for (final text in texts) ..._links(text.text),
      ].where((leaf) => leaf != ' ↗');
      expect(tappable, [for (final link in links) _shownText(link)]);
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
  testWidgets('the source of an Arabic verse reads «— Коран»', (tester) async {
    await _pump(
      tester,
      parseNoteBlocks([
        {
          'type': 'quote',
          'dir': 'rtl',
          'lines': [
            [
              {'text': 'نص الآية', 'lang': 'ar'},
            ],
          ],
          'source': 'Коран, 2:183',
        },
      ]),
    );
    final source = find.text('— Коран, 2:183');
    final paragraph = tester.renderObject<RenderParagraph>(source);
    expect(paragraph.textDirection, TextDirection.ltr);
    final dash = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    final name = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 2, extentOffset: 7),
    );
    expect(dash.single.right, lessThanOrEqualTo(name.first.left + 1));
    // It stays at the start edge of the block, the right one.
    final width = tester.getSize(find.byType(CourseNotesView)).width;
    expect(tester.getRect(source).right, closeTo(width - 12, 1));
  });

  testWidgets('a note opens in a sheet that a tap outside, Esc or «Close» '
      'closes', (tester) async {
    final byName = {for (final item in cases) item['name']: item['blocks']};
    await _pump(tester, parseNoteBlocks(byName['note_warning_after_word']));
    final mark = find.byType(NoteMarkButton);
    // A 22 dp circle in a 44 dp target, named for the screen reader.
    expect(tester.getSize(mark), const Size(44, 44));
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Внимание'), findsOneWidget);
    semantics.dispose();

    await tester.tap(mark);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-note-sheet-title')), findsOne);
    expect(find.text('Внимание'), findsOneWidget);
    expect(
      find.textContaining('Произносить его вслух не обязательно.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-note-sheet-title')), findsNothing);

    await tester.tap(mark);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-note-sheet-title')), findsNothing);

    await tester.tap(mark);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('course-note-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('course-note-sheet-title')), findsNothing);
  });

  testWidgets('a help note in Arabic sits left of its word', (tester) async {
    await _pump(
      tester,
      parseNoteBlocks([
        {
          'type': 'paragraph',
          'dir': 'rtl',
          'lines': [
            [
              {'text': 'النية', 'lang': 'ar'},
              {
                'text': '',
                'note': {
                  'kind': 'help',
                  'text': [
                    {'text': 'توضيح', 'lang': 'ar'},
                  ],
                },
              },
            ],
          ],
        },
      ]),
      locale: 'ar',
    );
    final mark = tester.getRect(find.byType(NoteMarkButton));
    final word = tester.getRect(find.byType(RichText).first);
    expect(mark.center.dx, lessThan(word.right - 30));
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('توضيح'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an internal link opens its screen in the app', (tester) async {
    final byName = {for (final item in cases) item['name']: item['blocks']};
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: CourseNotesView(
              blocks: parseNoteBlocks(byName['link_internal_ayah']),
            ),
          ),
        ),
        GoRoute(
          path: '/reader/:surah',
          builder: (context, state) => Text(
            'reader ${state.pathParameters['surah']} '
            '${state.uri.queryParameters['ayah']}',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        routerConfig: router,
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('аят аль-Курси'));
    await tester.pumpAndSettle();
    expect(find.text('reader 2 255'), findsOneWidget);
  });

  testWidgets('a link to another site says it opens in the browser', (
    tester,
  ) async {
    final byName = {for (final item in cases) item['name']: item['blocks']};
    await _pump(tester, parseNoteBlocks(byName['link_external_allowed']));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final arrow = <TextSpan>[];
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && span.text == ' ↗') arrow.add(span);
      return true;
    });
    expect(arrow.single.semanticsLabel, ' (откроется в браузере)');
    expect(arrow.single.recognizer, isA<TapGestureRecognizer>());
  });

  test('links map to the app\'s routes; others stay text', () {
    String? route(String href) =>
        NoteLink.tryParse({'href': href, 'kind': 'internal'})?.route;
    expect(route('/quran/2'), '/reader/2');
    expect(route('/quran/2:255'), '/reader/2?ayah=255');
    expect(route('/courses/ramadan/namerenie'), '/courses/ramadan/namerenie');
    expect(route('/dua/hisn/12'), '/dua/hisn/12');
    expect(route('/tajweed/izhar'), '/tajweed/lesson/izhar');
    expect(route('/tajweed/practice'), '/tajweed/practice');
    expect(route('/tajweed'), '/tajweed');
    expect(route('/admin'), isNull);
    expect(
      NoteLink.tryParse({'href': 'http://sunnah.com', 'kind': 'external'}),
      isNull,
    );
    expect(
      NoteLink.tryParse({'href': 'javascript:alert(1)', 'kind': 'external'}),
      isNull,
    );
    expect(
      NoteLink.tryParse({
        'href': 'https://sunnah.com/x',
        'kind': 'external',
      })?.external,
      isTrue,
    );
    final broken = NoteSegment.fromJson({
      'text': '',
      'note': {'kind': 'other', 'text': []},
    });
    expect(broken.note, isNull);
  });

  testWidgets('a tajweed lesson in Arabic keeps the text font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        home: Scaffold(
          body: CourseNotesView(
            plainArabic: true,
            blocks: parseNoteBlocks([
              {
                'type': 'paragraph',
                'dir': 'rtl',
                'lines': [
                  [
                    {'text': 'الإظهار', 'lang': 'ar'},
                  ],
                ],
              },
            ]),
          ),
        ),
      ),
    );
    final leaves = _leaves(tester.widget<RichText>(find.byType(RichText)).text);
    expect(leaves.single.$1, 'الإظهار');
    expect(leaves.single.$2.fontFamily, isNot(IqroTheme.arabicFontFamily));
  });
}
