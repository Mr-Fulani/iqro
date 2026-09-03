import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database sqlDatabase;
  late LocalDatabase database;
  late _FakeDuaRemote remote;
  late DuaRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sqlDatabase = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createSchema(sqlDatabase);
    database = LocalDatabase.forTesting(sqlDatabase);
    remote = _FakeDuaRemote();
    repository = DuaRepository(database: database, remote: remote);
  });

  tearDown(() => sqlDatabase.close());

  test(
    'parses full entry metadata and preserves it through favorites',
    () async {
      final entry = DuaEntry.fromJson(
        _entryPayload(7, repetitionLabel: '33 · 33 · 34'),
      );

      expect(entry.repetitions, 3);
      expect(entry.collectionVersion, 'hisn-full-test');
      expect(entry.repetitionLabel, '33 · 33 · 34');
      expect(entry.sourceLabel, 'Hisn al-Muslim');
      expect(entry.source?.languageCode, 'ru');
      expect(entry.source?.provider, 'islamhouse');
      expect(entry.source?.sourceItemId, '39062');
      expect(entry.source?.author, 'Said bin Ali bin Wahf Al-Qahtani');
      expect(entry.source?.translator, 'Translation team');
      expect(entry.source?.reviewer, 'Editorial team');
      expect(entry.source?.sourceUrl, 'https://islamhouse.com/en/books/39062');
      expect(entry.source?.rightsUrl, 'https://islamhouse.com/terms');
      expect(entry.source?.sourceVersion, '2026-08-28');
      expect(entry.evidence, hasLength(1));
      expect(entry.evidence.single.kind, 'hadith');
      expect(entry.evidence.single.sourceReference, 'Muslim 7');
      expect(entry.evidence.single.grade, 'Sahih');
      expect(entry.evidence.single.externalId, 'muslim-7');
      expect(entry.evidence.single.isEditoriallyVerified, isFalse);
      expect(entry.audio, hasLength(1));
      expect(entry.audio.single.languageCode, 'ar');
      expect(entry.audio.single.readerName, 'Arabic reader');
      expect(entry.audio.single.readerNameAr, 'القارئ');
      expect(
        entry.audio.single.url,
        'https://www.hisnmuslim.com/audio/ar/7.mp3',
      );
      expect(entry.audio.single.sourceUrl, 'https://www.hisnmuslim.com/7');
      expect(entry.audio.single.rightsUrl, 'https://www.hisnmuslim.com/terms');

      expect(await repository.toggleFavorite(entry), isTrue);
      final favorite = (await repository.favorites()).single;

      expect(remote.favoriteWrites, <_FavoriteWrite>[
        const _FavoriteWrite('hisn-al-muslim', 7, true),
      ]);
      expect(favorite.repetitionLabel, entry.repetitionLabel);
      expect(favorite.source?.sourceItemId, entry.source?.sourceItemId);
      expect(
        favorite.evidence.single.verificationStatus,
        entry.evidence.single.verificationStatus,
      );
      expect(favorite.audio.single.url, entry.audio.single.url);
      expect(await sqlDatabase.query('outbox'), isEmpty);
    },
  );

  test(
    'loads every cursor page in order, deduplicates, and caches the merged catalog',
    () async {
      remote.onEntries = (call) {
        if (call.cursor == null) {
          return _page(
            List<Object?>.generate(20, (index) => _entryPayload(index + 1)),
            next: _nextUrl('page-two', category: 'sleep'),
          );
        }
        if (call.cursor == 'page-two') {
          return _page(<Object?>[
            _entryPayload(20),
            ...List<Object?>.generate(4, (index) => _entryPayload(index + 21)),
          ]);
        }
        throw StateError('Unexpected cursor ${call.cursor}');
      };

      final online = await repository.entries('ru', category: 'sleep');

      expect(online, hasLength(24));
      expect(
        online.map((entry) => entry.sourceNumber),
        orderedEquals(List<int>.generate(24, (index) => index + 1)),
      );
      expect(remote.entryCalls, hasLength(2));
      expect(remote.entryCalls.map((call) => call.cursor), <String?>[
        null,
        'page-two',
      ]);
      for (final call in remote.entryCalls) {
        expect(call.locale, 'ru');
        expect(call.category, 'sleep');
        expect(call.pageSize, 100);
      }

      final cacheRow = (await sqlDatabase.query('cache_entries')).single;
      expect(cacheRow['cache_key'], startsWith('dua:https%3A'));
      expect(cacheRow['cache_key'], endsWith(':entries:v3:ru:sleep'));
      final cachedPayload = jsonDecode(cacheRow['payload']! as String) as Map;
      expect(cachedPayload['count'], 24);
      expect(cachedPayload['next'], isNull);
      expect(cachedPayload['results'], hasLength(24));

      remote.failEntries = true;
      final fresh = await repository.entries('ru', category: 'sleep');
      expect(fresh, hasLength(24));
      expect(remote.entryCalls, hasLength(2));

      await sqlDatabase.update('cache_entries', <String, Object?>{
        'expires_at': '2020-01-01T00:00:00Z',
      });
      final offline = await repository.entries('ru', category: 'sleep');
      expect(offline, hasLength(24));
      expect(remote.entryCalls, hasLength(3));
    },
  );

  test('featured entries keep Home bounded to one validated page', () async {
    remote.onEntries = (_) => _page(
      List<Object?>.generate(20, (index) => _entryPayload(index + 1)),
      next: _nextUrl('page-two'),
    );

    final entries = await repository.featuredEntries('ru');

    expect(entries, hasLength(20));
    expect(remote.entryCalls, hasLength(1));
    expect(remote.entryCalls.single.pageSize, 20);
    expect(remote.entryCalls.single.category, isNull);
    expect(remote.entryCalls.single.cursor, isNull);

    remote.failEntries = true;
    final cached = await repository.featuredEntries('ru');
    expect(cached, hasLength(20));
    expect(remote.entryCalls, hasLength(1));
    expect(
      (await sqlDatabase.query('cache_entries')).single['cache_key'],
      endsWith(':featured:v3:ru'),
    );
  });

  test('cache is isolated by API origin', () async {
    remote.onEntries = (_) => _page(<Object?>[_entryPayload(1)]);
    expect((await repository.entries('ru')).single.sourceNumber, 1);

    final productionRemote = _FakeDuaRemote(
      apiBaseUri: Uri.parse('https://iqro.forum/api/v1'),
    )..onEntries = (_) => _page(<Object?>[_entryPayload(2)]);
    final productionRepository = DuaRepository(
      database: database,
      remote: productionRemote,
    );

    expect((await productionRepository.entries('ru')).single.sourceNumber, 2);
    expect(productionRemote.entryCalls, hasLength(1));
    expect(await sqlDatabase.query('cache_entries'), hasLength(2));
  });

  test('corrupt cache rows recover from a valid network response', () async {
    remote.onEntries = (_) => _page(<Object?>[_entryPayload(1)]);
    await repository.entries('ru', category: 'recovery');

    await sqlDatabase.update('cache_entries', <String, Object?>{
      'payload': '{not-json',
    });
    remote.onEntries = (_) => _page(<Object?>[_entryPayload(2)]);
    expect(
      (await repository.entries(
        'ru',
        category: 'recovery',
      )).single.sourceNumber,
      2,
    );

    await sqlDatabase.update('cache_entries', <String, Object?>{
      'payload': jsonEncode('wrong-shape'),
      'updated_at': 'not-a-date',
    });
    remote.onEntries = (_) => _page(<Object?>[_entryPayload(3)]);
    expect(
      (await repository.entries(
        'ru',
        category: 'recovery',
      )).single.sourceNumber,
      3,
    );
    expect(remote.entryCalls, hasLength(3));
  });

  test('never follows an untrusted pagination URL', () async {
    final invalidLinks = <String>[
      'https://evil.example/api/v1/dua/entries?cursor=stolen',
      'https://staging.iqro.forum/api/v1/accounts?cursor=wrong-path',
      'https://staging.iqro.forum/api/v1/dua/entries?cursor=one&cursor=two',
      'https://staging.iqro.forum/api/v1/dua/entries?language=ru',
      'https://user@staging.iqro.forum/api/v1/dua/entries?cursor=user-info',
      'https://staging.iqro.forum/api/v1/dua/entries?cursor=fragment#bad',
    ];

    for (final (index, link) in invalidLinks.indexed) {
      remote.onEntries = (_) => _page(<Object?>[_entryPayload(1)], next: link);

      await expectLater(
        repository.entries('ru', category: 'invalid-$index'),
        throwsA(isA<FormatException>()),
      );
    }

    expect(await sqlDatabase.query('cache_entries'), isEmpty);
    expect(remote.entryCalls, hasLength(invalidLinks.length));
  });

  test('rejects a repeated cursor without caching a partial catalog', () async {
    remote.onEntries = (call) => _page(<Object?>[
      _entryPayload(call.cursor == null ? 1 : 2),
    ], next: _nextUrl('loop'));

    await expectLater(
      repository.entries('ru', category: 'loop'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cursor repeated'),
        ),
      ),
    );

    expect(remote.entryCalls, hasLength(2));
    expect(await sqlDatabase.query('cache_entries'), isEmpty);
  });

  test('stops pagination at the bounded page limit', () async {
    remote.onEntries = (call) {
      final page = remote.entryCalls.length;
      return _page(<Object?>[
        _entryPayload(page),
      ], next: _nextUrl('page-$page'));
    };

    await expectLater(
      repository.entries('ru', category: 'unbounded'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('safe limit'),
        ),
      ),
    );

    expect(remote.entryCalls, hasLength(50));
    expect(await sqlDatabase.query('cache_entries'), isEmpty);
  });

  test('keeps legacy favorites and malformed optional metadata usable', () {
    final legacy = DuaEntry.fromFavorite(<String, Object?>{
      'id': 'legacy',
      'source_number': 9,
      'collection': 'hisn-al-muslim',
      'category_title': 'Legacy category',
      'arabic_text': 'دعاء',
      'meaning': 'Meaning',
      'transliteration': 'Transliteration',
      'repetitions': 0,
      'source_label': 'Legacy source',
      'source': 'not-an-object',
      'evidence': <Object?>[
        'not-an-object',
        <String, Object?>{'source_reference': 'Reference'},
      ],
      'audio': 'not-a-list',
    });

    expect(legacy.categoryTitle, 'Legacy category');
    expect(legacy.meaning, 'Meaning');
    expect(legacy.transliteration, 'Transliteration');
    expect(legacy.repetitions, 1);
    expect(legacy.sourceLabel, 'Legacy source');
    expect(legacy.source, isNull);
    expect(legacy.evidence, hasLength(1));
    expect(legacy.evidence.single.sourceReference, 'Reference');
    expect(legacy.evidence.single.isEditoriallyVerified, isFalse);
    expect(legacy.audio, isEmpty);
  });

  test(
    'rejects malformed page shapes without caching an empty catalog',
    () async {
      for (final payload in <Object?>[
        null,
        <String, Object?>{},
        <String, Object?>{'results': 'not-a-list'},
        <String, Object?>{
          'results': <Object?>['not-an-entry'],
        },
        <String, Object?>{'results': <Object?>[], 'next': 123},
      ]) {
        remote.onEntries = (_) => payload;
        await expectLater(
          repository.entries('ru', category: 'bad-${remote.entryCalls.length}'),
          throwsFormatException,
          reason: '$payload',
        );
      }
      expect(await sqlDatabase.query('cache_entries'), isEmpty);
    },
  );

  test('rejects a catalog version change between cursor pages', () async {
    remote.onEntries = (call) => call.cursor == null
        ? _page(<Object?>[_entryPayload(1)], next: _nextUrl('new-version'))
        : _page(<Object?>[
            <String, Object?>{
              ..._entryPayload(2),
              'collection_version': 'hisn-full-next',
            },
          ]);

    await expectLater(
      repository.entries('ru', category: 'version-race'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('version changed'),
        ),
      ),
    );
    expect(await sqlDatabase.query('cache_entries'), isEmpty);
  });

  test(
    'rejects corrupt nested evidence instead of overstating verification',
    () async {
      final entry = _entryPayload(1);
      entry['evidence'] = <Object?>[
        <String, Object?>{
          ...(entry['evidence']! as List).first as Map,
          'verification_status': 'editorially_verified',
        },
        'corrupt evidence',
      ];
      remote.onEntries = (_) => _page(<Object?>[entry]);

      await expectLater(
        repository.entries('ru', category: 'corrupt-evidence'),
        throwsFormatException,
      );
      expect(await sqlDatabase.query('cache_entries'), isEmpty);
    },
  );

  test('rejects missing core fields and unknown evidence kinds', () async {
    final malformed = <Map<String, Object?>>[];
    for (final key in <String>[
      'collection',
      'collection_version',
      'repetitions',
    ]) {
      final entry = _entryPayload(malformed.length + 1)..remove(key);
      malformed.add(entry);
    }
    malformed.add(<String, Object?>{..._entryPayload(4), 'repetitions': 0});
    final unknownEvidence = _entryPayload(5);
    unknownEvidence['evidence'] = <Object?>[
      <String, Object?>{
        ...(unknownEvidence['evidence']! as List).single as Map,
        'kind': 'unknown-proof',
        'verification_status': 'editorially_verified',
      },
    ];
    malformed.add(unknownEvidence);

    for (final entry in malformed) {
      remote.onEntries = (_) => _page(<Object?>[entry]);
      await expectLater(
        repository.entries(
          'ru',
          category: 'strict-${remote.entryCalls.length}',
        ),
        throwsFormatException,
      );
    }
    expect(await sqlDatabase.query('cache_entries'), isEmpty);
  });

  test('does not cache a malformed category response', () async {
    remote.categoryPayload = <String, Object?>{'results': <Object?>[]};

    await expectLater(repository.categories('ru'), throwsFormatException);

    expect(await sqlDatabase.query('cache_entries'), isEmpty);
  });
}

class _EntryCall {
  const _EntryCall({
    required this.locale,
    required this.category,
    required this.cursor,
    required this.pageSize,
  });

  final String locale;
  final String? category;
  final String? cursor;
  final int pageSize;
}

class _FavoriteWrite {
  const _FavoriteWrite(this.collection, this.sourceNumber, this.isFavorite);

  final String collection;
  final int sourceNumber;
  final bool isFavorite;

  @override
  bool operator ==(Object other) =>
      other is _FavoriteWrite &&
      collection == other.collection &&
      sourceNumber == other.sourceNumber &&
      isFavorite == other.isFavorite;

  @override
  int get hashCode => Object.hash(collection, sourceNumber, isFavorite);
}

class _FakeDuaRemote implements DuaRemoteGateway {
  _FakeDuaRemote({Uri? apiBaseUri})
    : _apiBaseUri =
          apiBaseUri ?? Uri.parse('https://staging.iqro.forum/api/v1');

  final Uri _apiBaseUri;

  @override
  Uri get apiBaseUri => _apiBaseUri;

  final entryCalls = <_EntryCall>[];
  final favoriteWrites = <_FavoriteWrite>[];
  Object? Function(_EntryCall call)? onEntries;
  Object? categoryPayload = const <Object?>[];
  bool failEntries = false;

  @override
  Future<Object?> categories(String locale) async => categoryPayload;

  @override
  Future<Object?> entries(
    String locale, {
    String? category,
    String? cursor,
    required int pageSize,
  }) async {
    final call = _EntryCall(
      locale: locale,
      category: category,
      cursor: cursor,
      pageSize: pageSize,
    );
    entryCalls.add(call);
    if (failEntries) throw StateError('offline');
    return onEntries == null ? _page(const <Object?>[]) : onEntries!.call(call);
  }

  @override
  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite,
  ) async {
    favoriteWrites.add(_FavoriteWrite(collection, sourceNumber, isFavorite));
  }
}

Map<String, Object?> _page(List<Object?> results, {String? next}) =>
    <String, Object?>{
      'count': results.length,
      'next': next,
      'previous': null,
      'results': results,
    };

String _nextUrl(String cursor, {String category = 'test'}) =>
    Uri.https('staging.iqro.forum', '/api/v1/dua/entries', <String, String>{
      'language': 'ru',
      'category': category,
      'page_size': '100',
      'cursor': cursor,
    }).toString();

Map<String, Object?> _entryPayload(int number, {String repetitionLabel = ''}) =>
    <String, Object?>{
      'id': 'entry-$number',
      'source_number': number,
      'collection': 'hisn-al-muslim',
      'collection_version': 'hisn-full-test',
      'category': <String, Object?>{
        'source_number': 27,
        'slug': 'sleep',
        'title': 'Sleep',
      },
      'arabic_text': 'دعاء $number',
      'repetitions': 3,
      'repetition_label': repetitionLabel,
      'translation': <String, Object?>{
        'language_code': 'ru',
        'meaning_text': 'Meaning $number',
        'transliteration': 'Transliteration $number',
      },
      'evidence': <Object?>[
        <String, Object?>{
          'kind': 'hadith',
          'provider': 'islamhouse',
          'source_name': 'Hisn al-Muslim, note $number',
          'source_reference': 'Muslim $number',
          'source_url': 'https://islamhouse.com/en/books/39062',
          'grade': 'Sahih',
          'external_id': 'muslim-$number',
          'verification_status': 'source_only',
        },
      ],
      'source': <String, Object?>{
        'language_code': 'ru',
        'provider': 'islamhouse',
        'source_item_id': '39062',
        'title': 'Hisn al-Muslim',
        'author': 'Said bin Ali bin Wahf Al-Qahtani',
        'translator': 'Translation team',
        'reviewer': 'Editorial team',
        'source_url': 'https://islamhouse.com/en/books/39062',
        'rights_url': 'https://islamhouse.com/terms',
        'source_version': '2026-08-28',
      },
      'audio': <Object?>[
        <String, Object?>{
          'id': 'audio-$number',
          'language_code': 'ar',
          'provider': 'hisnmuslim',
          'reader_name': 'Arabic reader',
          'reader_name_ar': 'القارئ',
          'url': 'https://www.hisnmuslim.com/audio/ar/$number.mp3',
          'source_url': 'https://www.hisnmuslim.com/$number',
          'rights_url': 'https://www.hisnmuslim.com/terms',
          'source_version': '2026-08-28',
        },
      ],
    };

Future<void> _createSchema(Database database) async {
  await database.execute('''
    CREATE TABLE cache_entries (
      cache_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      etag TEXT,
      updated_at TEXT NOT NULL,
      expires_at TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE favorites (
      item_key TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE outbox (
      operation_id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_error TEXT
    )
  ''');
}
