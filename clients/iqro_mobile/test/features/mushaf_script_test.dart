import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/text/arabic_digits.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_script.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

class _Repository extends QuranRepository {
  _Repository({this.mode = 'page-font', MushafIdentity? mushaf})
    : super(
        api: _Unused(),
        database: _UnusedDatabase(),
        mushaf: mushaf ?? MushafIdentity.defaultEdition,
      );

  final String mode;
  var pagesRead = 0;

  @override
  Future<Map<String, List<int>>> foundationPageIndex() async => {
    '2:1': [2],
    '2:2': [2, 3],
  };

  @override
  Future<MushafPageData> mushafPage(
    int page, {
    bool forceRefresh = false,
  }) async {
    pagesRead++;
    return MushafPageData.fromFoundation({
      'mushaf_id': 19,
      'page_number': page,
      'pages_count': 604,
      'lines_per_page': 15,
      'source_checksum_sha256': 'c' * 64,
      'verse_mapping': {'2': '1-2'},
      'rendering': {
        'available': true,
        'version': 2,
        'mode': mode,
        'color_format': 'COLRv1',
        'native_font_url':
            'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p$page.ttf',
      },
      'words': [
        for (final (index, (key, type)) in const [
          ('2:1', 'word'),
          ('2:1', 'end'),
          ('2:2', 'word'),
        ].indexed)
          {
            'id': index + 1,
            'verse_key': key,
            'line_number': 3,
            'position_in_verse': 1,
            'position_in_page': index + 1,
            'char_type_name': type,
            'text': 'ﱁ',
          },
      ],
    });
  }

  @override
  Future<File> foundationAsset(Uri uri, String version) async =>
      File('assets/fonts/AmiriQuran-Regular.ttf');
}

class _Unused implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedDatabase implements LocalDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_Repository repository) {
  final container = ProviderContainer(
    overrides: [selectedMushafRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a page of a font Mushaf gives each ayah its words, its page font '
      'and whether the font is coloured', () async {
    final container = _container(_Repository());
    final page = (await container.read(mushafPageScriptProvider(2).future))!;
    expect(page.keys, ['2:1', '2:2']);
    expect(page['2:1']!.words.map((word) => word['char_type_name']), [
      'word',
      'end',
    ]);
    expect(page['2:1']!.fontFamily, startsWith('qf-'));
    expect(page['2:1']!.colored, isTrue);
    expect((await container.read(mushafVersePagesProvider.future))!['2:2'], [
      2,
      3,
    ]);
  });

  test('a Mushaf of pictures has no script: the readers keep the plain '
      'text', () async {
    final images = _container(_Repository(mode: 'word-images'));
    expect(await images.read(mushafPageScriptProvider(2).future), isNull);

    final raster = _Repository(mushaf: MushafIdentity.primary);
    final container = _container(raster);
    expect(await container.read(mushafPageScriptProvider(2).future), isNull);
    expect(await container.read(mushafVersePagesProvider.future), isNull);
    expect(raster.pagesRead, 0);
  });

  test('an ayah is on its page of the selected Mushaf, else on its Madani '
      'page', () {
    const pages = {
      '2:6': [4],
    };
    expect(mushafPageOfAyah(pages, 2, 6, const [3]), 4);
    expect(mushafPageOfAyah(pages, 2, 7, const [3]), 3);
    expect(mushafPageOfAyah(null, 2, 6, const [3, 4]), 3);
    expect(mushafPageOfAyah(null, 2, 6, const []), isNull);
  });

  test('numbers beside the interface use the digits its reader knows', () {
    expect(readerDigits('ru', 255), '255');
    expect(readerDigits('en', 7), '7');
    expect(readerDigits('ar', 255), '٢٥٥');
  });
}
