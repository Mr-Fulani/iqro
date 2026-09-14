import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

Map<String, Object?> page({int id = 7, String? version}) => {
  'mushaf_id': id,
  'page_number': 548,
  'pages_count': 548,
  'lines_per_page': 16,
  'source_checksum_sha256': version ?? 'a' * 64,
  'verse_mapping': {'114': '5-6'},
  'rendering': {'available': true, 'version': 2, 'mode': 'unicode-font'},
  'words': [
    for (final ayah in [5, 6])
      {
        'id': ayah,
        'verse_key': '114:$ayah',
        'line_number': 16,
        'position_in_verse': 1,
        'position_in_page': ayah - 4,
        'text': 'نَصّ',
      },
  ],
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'QUL rows justify words, preserve centered rows and share text baselines',
    () {
      for (final width in [320.0, 500.0]) {
        final source = FoundationMushafPage.fromJson({
          ...page(),
          'layout': {
            'version': 1,
            'lines': [
              {'line_number': 15, 'line_type': 'ayah', 'is_centered': false},
              {'line_number': 16, 'line_type': 'ayah', 'is_centered': true},
            ],
          },
          'words': [
            for (var line = 15; line <= 16; line++)
              for (var index = 1; index <= 3; index++)
                {
                  'id': line * 3 + index,
                  'verse_key': '114:6',
                  'text': 'نَصّ',
                  'line_number': line,
                  'position_in_page': line * 3 + index,
                },
          ],
        }, fromCache: false);
        final layout = FoundationPageLayout(
          source,
          FoundationPageResources(),
          Size(width, width * 1380 / 900),
          const [],
        );
        addTearDown(layout.dispose);
        final full = layout.words.take(3).toList();
        final centered = layout.words.skip(3).toList();
        expect(full.first.rect.right, closeTo(width * .94, .001));
        expect(full.last.rect.left, closeTo(width * .06, .001));
        expect(
          centered.first.rect.right + centered.last.rect.left,
          closeTo(width, .001),
        );
        expect(centered.last.rect.left, greaterThan(width * .06));
        for (final word in full) {
          expect(word.rect.width, closeTo(full.first.rect.width, .001));
        }
        final baselines = full
            .map(
              (word) =>
                  word.rect.top + word.baseline * word.rect.width / word.width,
            )
            .toList();
        expect(baselines.last, closeTo(baselines.first, .001));
      }
    },
  );
  test('all 13 source identities retain their own page counts and version', () {
    for (final id in [1, 2, 4, 5, 6, 7, 10, 11, 12, 14, 15, 16, 19]) {
      final count = [6, 14].contains(id)
          ? 610
          : [7, 15].contains(id)
          ? 548
          : 604;
      final edition = NativeMushafEdition.fromFoundation({
        'source_id': id,
        'name': 'Source $id',
        'pages_count': count,
        'lines_per_page': [7, 15].contains(id) ? 16 : 15,
        'qirat_name': 'Hafs',
        'mapping_mode': 'reference',
        'source_checksum_sha256': 'a' * 64,
        'rendering': {'available': true, 'version': 2, 'mode': 'unicode-font'},
      });
      expect(edition, isNotNull, reason: '$id');
      expect(edition!.pagesCount, count);
      expect(edition.sourceChecksum, 'a' * 64);
      expect(edition.identity.apiPath, '/quran/foundation/mushafs/$id');
    }
  });

  test(
    'out of range words and mismatched source versions are rejected',
    () async {
      for (final change in [
        {'page_number': 549},
        {'lines_per_page': 15},
        {'source_checksum_sha256': ''},
        {
          'words': [
            {'id': 1, 'verse_key': '115:1', 'line_number': 1, 'text': 'x'},
          ],
        },
      ]) {
        expect(
          () => MushafPageData.fromFoundation({...page(), ...change}),
          throwsFormatException,
        );
      }
      final api = _Api();
      final cache = _Cache();
      final repo = QuranRepository(
        api: api,
        database: cache,
        mushaf: MushafIdentity.fromPreference('native:qf-7'),
        foundationVersion: 'b' * 64,
      );
      await expectLater(repo.mushafPage(548), throwsFormatException);
      expect(cache.entries, isEmpty);
    },
  );

  test(
    'page and verse-index caches remain isolated across content versions',
    () async {
      final api = _Api();
      final cache = _Cache();
      final first = QuranRepository(
        api: api,
        database: cache,
        mushaf: MushafIdentity.fromPreference('native:qf-7'),
        foundationVersion: 'a' * 64,
      );
      expect((await first.mushafPage(548)).contentVersion, 'a' * 64);
      expect(await first.pageForAyah(114, 6, fallback: 604), 548);
      expect((await first.foundationPageIndex())['114:5'], [547, 548]);
      api.version = 'b' * 64;
      final second = first.withFoundationVersion(api.version);
      expect((await second.mushafPage(548)).contentVersion, 'b' * 64);
      expect(await second.pageForAyah(114, 6, fallback: 604), 548);
      api.offline = true;
      expect((await first.mushafPage(548)).contentVersion, 'a' * 64);
      expect((await second.mushafPage(548)).contentVersion, 'b' * 64);
      expect(cache.entries.length, 4);
    },
  );

  test(
    'font and PNG cache works offline, deduplicates and detects corruption',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'iqro-foundation-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => directory.path,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final api = _Api();
      final repo = QuranRepository(api: api, database: _Cache());
      for (final url in [
        'https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/p1.ttf',
        'https://static.qurancdn.com/images/w/qa-color/1/1/1.png?v=1',
      ]) {
        api.offline = false;
        final before = api.downloads;
        final files = await Future.wait(
          List.generate(4, (_) => repo.foundationAsset(Uri.parse(url), 'a')),
        );
        expect(api.downloads, before + 1);
        expect(files.map((file) => file.path).toSet(), hasLength(1));
        api.offline = true;
        expect(
          (await repo.foundationAsset(Uri.parse(url), 'a')).path,
          files.first.path,
        );
        await files.first.writeAsBytes([9, 9, 9, 9]);
        await expectLater(
          repo.foundationAsset(Uri.parse(url), 'a'),
          throwsStateError,
        );
        api.offline = false;
        await repo.foundationAsset(Uri.parse(url), 'a');
        expect(api.downloads, before + 3);
      }
      await expectLater(
        repo.foundationAsset(Uri.parse('https://evil.example/font.ttf'), 'a'),
        throwsFormatException,
      );
    },
  );

  test(
    'juz lookup uses ayah boundaries across different physical pagination',
    () {
      const division = QuranDivision(
        number: 30,
        startAyah: QuranAyahReference(id: '', surah: 78, ayah: 1),
        endAyah: QuranAyahReference(id: '', surah: 114, ayah: 6),
        startPage: 582,
        endPage: 604,
      );
      expect(
        division.containsAyah(
          MushafPageData.fromFoundation(page()).ayahReferences.last,
        ),
        isTrue,
      );
      expect(
        division.containsAyah(
          const QuranAyahReference(id: '', surah: 77, ayah: 50),
        ),
        isFalse,
      );
    },
  );

  testWidgets('painted word geometry drives tap and long-press selection', (
    tester,
  ) async {
    final source = MushafPageData.fromFoundation(page()).foundation!;
    final resources = FoundationPageResources();
    const size = Size(360, 552);
    final layout = FoundationPageLayout(source, resources, size, const []);
    addTearDown(layout.dispose);
    QuranAyahReference? selected;
    QuranAyahReference? opened;
    var backgrounds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: FoundationPageCanvas(
              page: source,
              resources: resources,
              selected: null,
              playing: null,
              onSelect: (ref) => selected = ref,
              onOpen: (ref) => opened = ref,
              onBackgroundTap: () => backgrounds++,
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(layout.words.last.rect.center);
    expect(selected?.key, '114:6');
    await tester.longPressAt(layout.words.first.rect.center);
    expect(opened?.key, '114:5');
    await tester.tapAt(const Offset(10, 10));
    expect(backgrounds, 1);
    expect(tester.takeException(), isNull);
  });
}

class _Cache implements LocalDatabase {
  final entries = <String, CachedValue>{};
  @override
  Future<CachedValue?> readCache(String key) async => entries[key];
  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(hours: 1),
  }) async {
    entries[key] = CachedValue(value: value, updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements ApiClient {
  @override
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
  String version = 'a' * 64;
  bool offline = false;
  int downloads = 0;
  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    if (path.endsWith('page-index')) {
      return {
        'mushaf_id': 7,
        'pages_count': 548,
        'source_checksum_sha256': version,
        'verse_pages': {
          '114:5': [547, 548],
          '114:6': [548],
        },
      };
    }
    return page(version: version);
  }

  @override
  Future<Uint8List> getPublicBytes(
    Uri uri, {
    required Set<String> allowedHosts,
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    downloads++;
    if (offline) throw StateError('offline');
    return Uint8List.fromList([0, 1, 2, uri.path.endsWith('ttf') ? 3 : 4]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
