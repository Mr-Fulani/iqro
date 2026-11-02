import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/ayah_share.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

// 6:2 begins on page 128 of Mushaf 19 and ends on page 129.
Map<String, Object?> _page(
  int number,
  String version,
  List<(int, String, String)> words,
) => {
  'mushaf_id': 19,
  'page_number': number,
  'pages_count': 604,
  'lines_per_page': 15,
  'source_checksum_sha256': version,
  'verse_mapping': {'6': number == 128 ? '1-2' : '2-3'},
  'rendering': {
    'available': true,
    'version': 2,
    'mode': 'page-font',
    'native_font_url':
        'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p$number.ttf',
  },
  'words': [
    for (final (index, (id, verseKey, text)) in words.indexed)
      {
        'id': id,
        'verse_key': verseKey,
        'line_number': 15,
        'position_in_verse': index + 1,
        'position_in_page': index + 1,
        'char_type_name': 'word',
        'text': text,
      },
  ],
};

class _Repository extends QuranRepository {
  _Repository({this.fontsFail = false})
    : super(
        api: _UnusedApi(),
        database: _UnusedDatabase(),
        mushaf: MushafIdentity.defaultEdition,
      );

  final bool fontsFail;

  // A version of its own, as loaded fonts are kept for the next share.
  String get _version => fontsFail ? 'b' * 64 : 'a' * 64;

  @override
  Future<Map<String, List<int>>> foundationPageIndex() async => {
    '6:2': [128, 129],
  };

  @override
  Future<MushafPageData> mushafPage(
    int page, {
    bool forceRefresh = false,
  }) async => MushafPageData.fromFoundation(
    page == 128
        ? _page(128, _version, [
            (1, '6:1', 'ﱁ'),
            (3, '6:2', 'ﱃ'),
            (4, '6:2', 'ﱄ'),
          ])
        : _page(129, _version, [(5, '6:2', 'ﱅ'), (7, '6:3', 'ﱇ')]),
  );

  @override
  Future<File> foundationAsset(Uri uri, String version) async {
    if (fontsFail) throw const SocketException('offline');
    return File('assets/fonts/AmiriQuran-Regular.ttf');
  }
}

class _UnusedApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedDatabase implements LocalDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an ayah over two pages takes its words from both page fonts', () async {
    final spans = await ayahShareGlyphs(_Repository(), 6, 2);
    expect(spans.map((span) => span.toPlainText()), ['ﱃ', 'ﱄ', 'ﱅ']);
    final families = spans
        .map((span) => (span as TextSpan).style?.fontFamily)
        .toList();
    expect(families[0], families[1]);
    expect(families[1], isNot(families[2]));
  });

  test('without the page fonts the card keeps the plain script', () async {
    expect(await ayahShareGlyphs(_Repository(fontsFail: true), 6, 2), isEmpty);
  });
}
