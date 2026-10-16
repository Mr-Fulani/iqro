import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_paper.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/truetype_glyph.dart';

const _fontUrl =
    'https://static-cdn.tarteel.ai/qul/fonts/surah-names/surah-header/QCF_SurahHeader_COLOR-Regular.ttf';

/// A two-glyph TrueType file: an empty .notdef and a 200×100 "heading" whose
/// top-right corner is a quadratic curve through one off-curve point.
Uint8List _font() {
  final glyph = BytesBuilder()
    ..add(_i16([1, 0, 0, 200, 100, 3, 0]))
    ..add([1, 1, 0, 1])
    ..add(_i16([0, 200, 0, -200, 0, 0, 100, 0]));
  final glyf = glyph.toBytes();
  final head = Uint8List(54)
    ..buffer.asByteData().setInt16(18, 1000)
    ..buffer.asByteData().setInt16(50, 1);
  final maxp = Uint8List(6)
    ..buffer.asByteData().setUint32(0, 0x00005000)
    ..buffer.asByteData().setUint16(4, 2);
  final loca = Uint8List(12)..buffer.asByteData().setUint32(8, glyf.length);
  final tables = {'glyf': glyf, 'head': head, 'loca': loca, 'maxp': maxp};
  final directory = ByteData(12 + 16 * tables.length)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, tables.length);
  final data = BytesBuilder();
  var offset = directory.lengthInBytes;
  var index = 0;
  for (final MapEntry(:key, :value) in tables.entries) {
    final record = 12 + 16 * index++;
    for (var char = 0; char < 4; char++) {
      directory.setUint8(record + char, key.codeUnitAt(char));
    }
    directory
      ..setUint32(record + 8, offset)
      ..setUint32(record + 12, value.length);
    final padded = (value.length + 3) & ~3;
    data.add([...value, ...List.filled(padded - value.length, 0)]);
    offset += padded;
  }
  return Uint8List.fromList([
    ...directory.buffer.asUint8List(),
    ...data.toBytes(),
  ]);
}

List<int> _i16(List<int> values) {
  final data = ByteData(values.length * 2);
  for (var index = 0; index < values.length; index++) {
    data.setInt16(index * 2, values[index]);
  }
  return data.buffer.asUint8List();
}

FoundationMushafPage _page({Map<String, Object?>? header, bool qul = true}) =>
    FoundationMushafPage.fromJson({
      'mushaf_id': 19,
      'page_number': 187,
      'pages_count': 604,
      'lines_per_page': 15,
      'source_checksum_sha256': 'a' * 64,
      'rendering': {'available': true, 'version': 2, 'mode': 'word-images'},
      'surah_header': ?header,
      if (qul)
        'layout': {
          'version': 1,
          'lines': [
            {'line_number': 1, 'line_type': 'surah_name', 'surah_number': 9},
            {'line_number': 2, 'line_type': 'ayah', 'is_centered': false},
          ],
        },
      'words': [
        if (qul)
          for (var index = 1; index <= 3; index++)
            {
              'id': index,
              'verse_key': '9:1',
              'text': 'نَصّ',
              'line_number': 2,
              'position_in_verse': index,
              'position_in_page': index,
            },
      ],
    }, fromCache: false);

void main() {
  final font = _font();
  final heading = readTrueTypeGlyph(ByteData.sublistView(font), 1)!;

  test('reads quadratic TrueType outlines with y pointing down', () {
    expect(heading.bounds, const Rect.fromLTRB(0, -100, 200, 0));
    expect(heading.path.contains(const Offset(100, -20)), isTrue);
    // The off-curve corner point pulls the curve without being on it.
    expect(heading.path.contains(const Offset(198, -98)), isFalse);
    expect(readTrueTypeGlyph(ByteData.sublistView(font), 0), isNull);
    expect(readTrueTypeGlyph(ByteData.sublistView(font), 2), isNull);
  });

  test('loads only the pinned heading font and its listed glyphs', () async {
    final directory = await Directory.systemTemp.createTemp('surah-header');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/header.ttf')..writeAsBytesSync(font);
    final requested = <Uri>[];
    Future<File> asset(Uri uri, String version) async {
      requested.add(uri);
      return file;
    }

    Map<String, Object?> header(String checksum) => {
      'font_url': _fontUrl,
      'font_sha256': checksum,
      'glyph_ids': {'9': 1, '10': 0},
    };
    final pinned = await loadFoundationPageResources(
      _page(header: header(sha256.convert(font).toString()), qul: false),
      asset,
    );
    expect(requested, [Uri.parse(_fontUrl)]);
    expect(pinned.surahHeaders.keys, [9]);
    final changed = await loadFoundationPageResources(
      _page(header: header('b' * 64), qul: false),
      asset,
    );
    expect(changed.surahHeaders, isEmpty);
  });

  test('a source heading replaces the text title', () {
    const size = Size(360, 552);
    final layout = FoundationPageLayout(
      _page(),
      FoundationPageResources(surahHeaders: {9: heading}),
      size,
      const [],
    );
    addTearDown(layout.dispose);
    expect(layout.decorations, isEmpty);
    final (_, rect) = layout.headers.single;
    const rowHeight = 552 * .93 / 15;
    expect(rect.center.dx, closeTo(size.width / 2, .001));
    expect(rect.center.dy, closeTo(552 * .035 + rowHeight / 2, .001));
    expect(rect.width / rect.height, closeTo(2, .001));
    expect(rect.height, closeTo(rowHeight * .92, .001));
  });

  testWidgets('page canvas fills the source heading in Mushaf ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 552,
            child: FoundationPageCanvas(
              page: _page(),
              resources: FoundationPageResources(surahHeaders: {9: heading}),
              selected: null,
              playing: null,
              onSelect: (_) {},
              onOpen: (_) {},
              onBackgroundTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(FoundationPageCanvas),
        matching: find.byType(CustomPaint),
      ),
      paints..something(
        (method, arguments) =>
            method == #drawPath &&
            arguments[0] == heading.path &&
            (arguments[1] as Paint).color.toARGB32() ==
                mushafInkColor.toARGB32(),
      ),
    );
  });
}
