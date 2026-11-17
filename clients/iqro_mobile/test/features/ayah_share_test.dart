import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/share/content_share.dart';
import 'package:iqro_mobile/features/quran/ayah_share.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:iqro_mobile/features/quran/word_range.dart';

// 6:2 begins on page 128 of the Mushaf and ends on page 129, with its end
// sign; a [coloured] page font paints its own colours (tajweed).
Map<String, Object?> _page(
  int number,
  String version,
  List<(int, String, String)> words, {
  bool coloured = false,
}) => {
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
    if (coloured) 'color_format': 'colrv1',
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
        'char_type_name': text == 'ﱆ' ? 'end' : 'word',
        'text': text,
      },
  ],
};

class _Repository extends QuranRepository {
  _Repository({this.fontsFail = false, this.coloured = false})
    : super(
        api: _UnusedApi(),
        database: _UnusedDatabase(),
        mushaf: MushafIdentity.defaultEdition,
      );

  final bool fontsFail;
  final bool coloured;

  // A version of its own, as loaded fonts are kept for the next share.
  String get _version =>
      (fontsFail
          ? 'b'
          : coloured
          ? 'c'
          : 'a') *
      64;

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
          ], coloured: coloured)
        : _page(129, _version, [
            (5, '6:2', 'ﱅ'),
            (6, '6:2', 'ﱆ'),
            (7, '6:3', 'ﱇ'),
          ], coloured: coloured),
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

  test('an ayah over two pages takes its words from both page fonts, the end '
      'sign with the last word', () async {
    final spans = await ayahShareGlyphs(_Repository(), 6, 2);
    expect(spans.map((span) => span.toPlainText()), ['ﱃ', 'ﱄ', 'ﱅ\u00a0ﱆ']);
    final families = spans
        .map((span) => (span as TextSpan).style?.fontFamily)
        .toList();
    expect(families[0], families[1]);
    expect(families[0], isNotNull);
    final last = (spans[2] as TextSpan).children!;
    expect((last.first as TextSpan).style?.fontFamily, isNot(families[1]));
  });

  test('without the page fonts the card keeps the plain script', () async {
    expect(await ayahShareGlyphs(_Repository(fontsFail: true), 6, 2), isEmpty);
  });

  test('a font that paints its own colours cannot take the ink of the card: '
      'the plain script is drawn', () async {
    expect(await ayahShareGlyphs(_Repository(coloured: true), 6, 2), isEmpty);
  });

  group('selected words', () {
    const ayahs = [
      QuranAyah(
        id: 'a',
        surahNumber: 2,
        number: 285,
        textUthmani: 'ءَامَنَ ٱلرَّسُولُ بِمَآ أُنزِلَ',
        pages: [49],
      ),
      QuranAyah(
        id: 'b',
        surahNumber: 2,
        number: 286,
        textUthmani: 'لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا وُسْعَهَا ۚ لَهَا',
        pages: [49],
      ),
    ];
    String partOf(String reference, {required bool several}) =>
        several ? 'из аятов $reference' : 'из аята $reference';
    ContentShare share(
      QuranWord start,
      QuranWord end, {
      Map<int, AyahShareScript> scripts = const {},
    }) => wordRangeContentShare(
      locale: 'ru',
      surahName: 'Аль-Бакара',
      range: QuranWordRange.between(start, end)!,
      ayahs: ayahs,
      readInIqro: 'Читать в IQRO',
      partOf: partOf,
      scripts: scripts,
      translations: const {
        285: 'Посланник уверовал',
        286: 'Аллах не возлагает',
      },
    );
    List<String> drawn(ContentShare share) =>
        share.arabicGlyphs.map((span) => span.toPlainText()).toList();

    test('a part of an ayah has its words alone: no meaning, no end sign, '
        'and says it is a part', () {
      final part = share(
        const QuranWord(2, 286, 1),
        const QuranWord(2, 286, 5),
      );
      // The pause mark belongs to the word before it.
      expect(part.arabic, 'لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا');
      expect(drawn(part), part.arabic.split(' '));
      expect(part.translation, isEmpty);
      expect(part.cardReference, 'Аль-Бакара · из аята 2:286');
      expect(part.title, part.cardReference);
      expect(
        part.url,
        'https://iqro.forum/ru/quran/madani-hafs/surah/2/ayah/286',
      );
    });

    test('the last word of an ayah brings its end sign', () {
      final part = share(
        const QuranWord(2, 286, 6),
        const QuranWord(2, 286, 7),
      );
      expect(drawn(part), ['وُسْعَهَا ۚ', 'لَهَا ۝٢٨٦']);
      expect(part.arabic, 'وُسْعَهَا ۚ لَهَا');
      expect(part.cardReference, 'Аль-Бакара · из аята 2:286');
    });

    test('whole ayahs carry their meanings and both end signs', () {
      final whole = share(
        const QuranWord(2, 285, 1),
        const QuranWord(2, 286, 7),
      );
      expect(whole.cardReference, 'Аль-Бакара · 2:285–286');
      expect(whole.translation, 'Посланник уверовал Аллах не возлагает');
      expect(drawn(whole)[3], 'أُنزِلَ ۝٢٨٥');
      expect(drawn(whole).last, 'لَهَا ۝٢٨٦');
      expect(whole.arabic, ayahs.map((ayah) => ayah.textUthmani).join(' '));
    });

    test('words across two ayahs say so; one whole ayah is as the ayah', () {
      expect(
        share(
          const QuranWord(2, 285, 3),
          const QuranWord(2, 286, 2),
        ).cardReference,
        'Аль-Бакара · из аятов 2:285–286',
      );
      final one = share(const QuranWord(2, 285, 1), const QuranWord(2, 285, 4));
      expect(one.cardReference, 'Аль-Бакара · 2:285');
      expect(one.translation, 'Посланник уверовал');
    });

    test('the Mushaf\'s script is drawn when it has the words the reader '
        'counts, else the plain script', () {
      const font = TextStyle(fontFamily: 'p49');
      final script = (
        words: const <InlineSpan>[
          TextSpan(text: 'ﱁ', style: font),
          TextSpan(text: 'ﱂ', style: font),
          TextSpan(text: 'ﱃ', style: font),
          TextSpan(text: 'ﱄ', style: font),
        ],
        end: const TextSpan(text: 'ﱅ', style: font),
      );
      final inScript = share(
        const QuranWord(2, 285, 3),
        const QuranWord(2, 285, 4),
        scripts: {285: script},
      );
      expect(drawn(inScript), ['ﱃ', 'ﱄ ﱅ']);
      // The message keeps the plain text.
      expect(inScript.arabic, 'بِمَآ أُنزِلَ');

      final mismatch = share(
        const QuranWord(2, 286, 1),
        const QuranWord(2, 286, 2),
        scripts: {286: script},
      );
      expect(drawn(mismatch), ['لَا', 'يُكَلِّفُ']);
    });
  });
}
