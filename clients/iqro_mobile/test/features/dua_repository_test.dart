import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
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

  test('accepts source audio when the reader is not identified', () async {
    final payload = _entryPayload(8);
    final audio = Map<String, Object?>.from(
      (payload['audio']! as List).single! as Map,
    );
    audio['reader_name'] = '';
    payload['audio'] = <Object?>[audio];
    remote.onEntries = (_) => _page(<Object?>[payload]);

    final entry = (await repository.entries('ru', category: 'sleep')).single;

    expect(entry.audio.single.readerName, isEmpty);
    expect(entry.audio.single.provider, 'hisnmuslim');
  });

  test('preserves a withdrawn server favorite as removable identity', () async {
    AccountScopeSnapshot? requestScope;
    remote.onFavorites = (locale, accountScope) {
      expect(locale, 'ru');
      requestScope = accountScope;
      return <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'collection': 'hisn-al-muslim',
            'source_number': 7,
            'is_favorite': true,
            'entry': null,
          },
        ],
      };
    };

    final favorite = (await repository.favorites(locale: 'ru')).single;

    expect(requestScope?.userId, 'test-owner');
    expect(favorite.favoriteKey, 'dua:hisn-al-muslim:7');
    expect(favorite.available, isFalse);
    expect(await repository.toggleFavorite(favorite), isFalse);
    expect(remote.favoriteWrites, <_FavoriteWrite>[
      const _FavoriteWrite('hisn-al-muslim', 7, false),
    ]);
    expect(await repository.favorites(), isEmpty);
    expect(await sqlDatabase.query('outbox'), isEmpty);
  });

  test(
    'favorite action captured by A cannot mutate B after an account switch',
    () async {
      final entry = DuaEntry.unavailableFavorite(
        collection: 'hisn-al-muslim',
        sourceNumber: 7,
      );
      final scopeA = await database.captureAccount();
      database.accountScope.activate('owner-b');

      await expectLater(
        repository.toggleFavorite(entry, accountScope: scopeA),
        throwsA(isA<AccountScopeChanged>()),
      );
      await expectLater(
        repository.favorites(locale: 'ru', accountScope: scopeA),
        throwsA(isA<AccountScopeChanged>()),
      );

      expect(await sqlDatabase.query('favorites'), isEmpty);
      expect(await sqlDatabase.query('outbox'), isEmpty);
      expect(remote.favoriteWrites, isEmpty);
    },
  );

  test(
    'authoritative favorite pull atomically overlays pending local intent',
    () async {
      final localAdd = DuaEntry.fromJson(_entryPayload(2));
      await sqlDatabase.insert('favorites', <String, Object?>{
        'owner_id': 'test-owner',
        'item_key': localAdd.favoriteKey,
        'kind': 'dua',
        'payload': jsonEncode(localAdd.toJson()),
        'updated_at': '2026-09-01T10:00:00Z',
      });
      await _insertFavoriteIntent(
        sqlDatabase,
        operationId: 'pending-add',
        sourceNumber: 2,
        isFavorite: true,
      );
      await _insertFavoriteIntent(
        sqlDatabase,
        operationId: 'pending-remove',
        sourceNumber: 1,
        isFavorite: false,
      );
      remote.onFavorites = (_, _) => <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'collection': 'hisn-al-muslim',
            'source_number': 1,
            'is_favorite': true,
            'entry': _entryPayload(1),
          },
        ],
      };

      final favorites = await repository.favorites(locale: 'ru');

      expect(favorites, hasLength(1));
      expect(favorites.single.sourceNumber, 2);
      expect(favorites.single.arabicText, localAdd.arabicText);
      expect(await sqlDatabase.query('outbox'), hasLength(2));
    },
  );

  test(
    'invalid favorite pull leaves the previous snapshot untouched',
    () async {
      final existing = DuaEntry.fromJson(_entryPayload(4));
      await sqlDatabase.insert('favorites', <String, Object?>{
        'owner_id': 'test-owner',
        'item_key': existing.favoriteKey,
        'kind': 'dua',
        'payload': jsonEncode(existing.toJson()),
        'updated_at': '2026-09-01T10:00:00Z',
      });
      remote.onFavorites = (_, _) => <String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'collection': 'hisn-al-muslim',
            'source_number': 5,
            'is_favorite': true,
            'entry': <String, Object?>{..._entryPayload(6), 'source_number': 6},
          },
        ],
      };

      await expectLater(
        repository.favorites(locale: 'ru'),
        throwsFormatException,
      );

      final favorites = await repository.favorites();
      expect(favorites, hasLength(1));
      expect(favorites.single.sourceNumber, 4);
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
        expect(call.collection, isNull);
        expect(call.category, 'sleep');
        expect(call.query, isNull);
        expect(call.pageSize, 100);
      }

      final cacheRow = (await sqlDatabase.query('cache_entries')).single;
      expect(cacheRow['cache_key'], startsWith('dua:https%3A'));
      expect(cacheRow['cache_key'], endsWith(':entries:v4:ru:all:sleep'));
      final cachedPayload = jsonDecode(cacheRow['payload']! as String) as Map;
      expect(cachedPayload['count'], 24);
      expect(cachedPayload['next'], isNull);
      expect(cachedPayload['collection_versions'], <String, Object?>{
        'hisn-al-muslim': 'hisn-full-test',
      });
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
      expect(offline.every((entry) => !entry.catalogVersionVerified), isTrue);
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
      endsWith(':featured:v4:ru'),
    );
  });

  test(
    'search forwards collection and query across every cursor page',
    () async {
      remote.onEntries = (call) => call.cursor == null
          ? _page(<Object?>[_entryPayload(1)], next: _nextUrl('search-page'))
          : _page(<Object?>[_entryPayload(2)]);

      final results = await repository.search(
        'ru',
        '  утро  ',
        collection: 'hisn-al-muslim',
        category: 'sleep',
      );

      expect(results.map((entry) => entry.sourceNumber), <int>[1, 2]);
      expect(remote.entryCalls, hasLength(2));
      for (final call in remote.entryCalls) {
        expect(call.collection, 'hisn-al-muslim');
        expect(call.category, 'sleep');
        expect(call.query, 'утро');
      }
    },
  );

  test(
    'detail revalidates identity and uses cache only as untrusted fallback',
    () async {
      const entryId = '0192d920-4cb5-7e72-9a4d-9f0ab8d90e31';
      remote.onEntry = (locale, id) => <String, Object?>{
        ..._entryPayload(7),
        'id': entryId,
      };

      final online = await repository.entry('ru', entryId.toUpperCase());
      expect(online.id, entryId);
      expect(remote.detailCalls, <String>[entryId]);

      remote.failDetail = true;
      final cached = await repository.entry('ru', entryId);
      expect(cached.sourceNumber, 7);
      expect(cached.catalogVersionVerified, isFalse);
      expect(remote.detailCalls, hasLength(2));

      await expectLater(
        repository.entry('ru', 'not-a-uuid'),
        throwsFormatException,
      );
    },
  );

  test('detail never masks an authoritative withdrawal with cache', () async {
    const entryId = '0192d920-4cb5-7e72-9a4d-9f0ab8d90e32';
    remote.onEntry = (locale, id) => <String, Object?>{
      ..._entryPayload(8),
      'id': entryId,
    };
    await repository.entry('ru', entryId);
    remote.onEntry = (locale, id) =>
        throw const ApiException(message: 'withdrawn', statusCode: 404);

    await expectLater(
      repository.entry('ru', entryId),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('canonical reference resolves the active replacement entry', () async {
    final oldFavorite = DuaEntry.fromFavorite(<String, Object?>{
      ..._entryPayload(9),
      'id': '0192d920-4cb5-7e72-9a4d-000000000009',
      'collection_version': 'hisn-old',
    });
    remote.onResolveEntry = (locale, collection, sourceNumber) =>
        <String, Object?>{
          ..._entryPayload(sourceNumber),
          'id': '0192d920-4cb5-7e72-9a4d-000000009999',
          'collection_version': 'hisn-full-test',
        };

    final current = await repository.entryByReference(
      'ru',
      collection: oldFavorite.collection,
      sourceNumber: oldFavorite.sourceNumber,
    );

    expect(current.id, isNot(oldFavorite.id));
    expect(current.collectionVersion, 'hisn-full-test');
    expect(remote.referenceCalls, <DuaEntryIdentity>[
      (collection: 'hisn-al-muslim', sourceNumber: 9),
    ]);
    await expectLater(
      repository.entryByReference(
        'ru',
        collection: 'hisn-al-muslim',
        sourceNumber: 32768,
      ),
      throwsArgumentError,
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
    remote.onEntries = (_) => _page(<Object?>[_scopedEntry('recovery', 1)]);
    await repository.entries('ru', category: 'recovery');

    await sqlDatabase.update('cache_entries', <String, Object?>{
      'payload': '{not-json',
    });
    remote.onEntries = (_) => _page(<Object?>[_scopedEntry('recovery', 2)]);
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
    remote.onEntries = (_) => _page(<Object?>[_scopedEntry('recovery', 3)]);
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
      'https://iqro.forum/api/v1/accounts?cursor=wrong-path',
      'https://iqro.forum/api/v1/dua/entries?cursor=one&cursor=two',
      'https://iqro.forum/api/v1/dua/entries?language=ru',
      'https://user@iqro.forum/api/v1/dua/entries?cursor=user-info',
      'https://iqro.forum/api/v1/dua/entries?cursor=fragment#bad',
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
      _scopedEntry('loop', call.cursor == null ? 1 : 2),
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
        _scopedEntry('unbounded', page),
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
        ? _page(<Object?>[
            _scopedEntry('version-race', 1),
          ], next: _nextUrl('new-version'))
        : _page(<Object?>[
            <String, Object?>{
              ..._scopedEntry('version-race', 2),
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
    'rejects an empty tail after the active catalog version changes',
    () async {
      remote.onCollections = (call) => <Object?>[
        <String, Object?>{
          'slug': 'hisn-al-muslim',
          'version': call == 1 ? 'hisn-full-test' : 'hisn-full-next',
        },
      ];
      remote.onEntries = (call) => call.cursor == null
          ? _page(<Object?>[
              _scopedEntry('snapshot-race', 1),
            ], next: _nextUrl('new-version'))
          : _page(const <Object?>[]);

      await expectLater(
        repository.entries('ru', category: 'snapshot-race'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('version changed'),
          ),
        ),
      );
      expect(remote.collectionCalls, 2);
      expect(await sqlDatabase.query('cache_entries'), isEmpty);
    },
  );

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

  test('refreshes category metadata when the active version changes', () async {
    remote.onCollections = (call) => <Object?>[
      <String, Object?>{
        'slug': 'hisn-al-muslim',
        'version': call <= 2 ? 'hisn-full-test' : 'hisn-full-next',
      },
    ];
    remote.categoryPayload = <Object?>[
      _categoryPayload(title: 'Old title', version: 'hisn-full-test'),
    ];

    expect((await repository.categories('ru')).single.title, 'Old title');

    remote.categoryPayload = <Object?>[
      _categoryPayload(title: 'New title', version: 'hisn-full-next'),
    ];
    final refreshed = await repository.categories('ru');

    expect(refreshed.single.title, 'New title');
    expect(remote.categoryCalls, 2);
    expect(remote.collectionCalls, 5);
  });

  test(
    'category identity includes collection and rejects duplicates',
    () async {
      final category = <String, Object?>{
        'id': 'category-1',
        'collection': 'hisn-al-muslim',
        'collection_version': 'hisn-full-test',
        'source_number': 27,
        'slug': 'sleep',
        'title': 'Sleep',
        'entry_count': 24,
      };
      remote.categoryPayload = <Object?>[category];

      final parsed = await repository.categories('ru');

      expect(parsed.single.identity, (
        collection: 'hisn-al-muslim',
        slug: 'sleep',
      ));
      expect(parsed.single.collectionVersion, 'hisn-full-test');
      expect(parsed.single.sourceNumber, 27);

      await sqlDatabase.delete('cache_entries');
      remote.categoryPayload = <Object?>[
        category,
        {...category, 'id': 'category-2'},
      ];
      await expectLater(repository.categories('ru'), throwsFormatException);
    },
  );
}

class _EntryCall {
  const _EntryCall({
    required this.locale,
    required this.collection,
    required this.category,
    required this.query,
    required this.cursor,
    required this.pageSize,
  });

  final String locale;
  final String? collection;
  final String? category;
  final String? query;
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
    : _apiBaseUri = apiBaseUri ?? Uri.parse('https://iqro.forum/api/v1');

  final Uri _apiBaseUri;

  @override
  Uri get apiBaseUri => _apiBaseUri;

  final entryCalls = <_EntryCall>[];
  final detailCalls = <String>[];
  final referenceCalls = <DuaEntryIdentity>[];
  var collectionCalls = 0;
  var categoryCalls = 0;
  final favoriteWrites = <_FavoriteWrite>[];
  Object? Function(_EntryCall call)? onEntries;
  Object? categoryPayload = const <Object?>[];
  bool failEntries = false;
  bool failDetail = false;
  Object? Function(String locale, String id)? onEntry;
  Object? Function(String locale, String collection, int sourceNumber)?
  onResolveEntry;
  Object? Function(int call)? onCollections;
  Object? Function(String locale, AccountScopeSnapshot? accountScope)?
  onFavorites;

  @override
  Future<Object?> collections(String locale) async {
    collectionCalls += 1;
    return onCollections?.call(collectionCalls) ??
        <Object?>[
          <String, Object?>{
            'slug': 'hisn-al-muslim',
            'version': 'hisn-full-test',
          },
        ];
  }

  @override
  Future<Object?> categories(String locale) async {
    categoryCalls += 1;
    return categoryPayload;
  }

  @override
  Future<Object?> entries(
    String locale, {
    String? collection,
    String? category,
    String? query,
    String? cursor,
    required int pageSize,
  }) async {
    final call = _EntryCall(
      locale: locale,
      collection: collection,
      category: category,
      query: query,
      cursor: cursor,
      pageSize: pageSize,
    );
    entryCalls.add(call);
    if (failEntries) throw StateError('offline');
    return onEntries == null ? _page(const <Object?>[]) : onEntries!.call(call);
  }

  @override
  Future<Object?> entry(String locale, String id) async {
    detailCalls.add(id);
    if (failDetail) throw StateError('offline');
    final callback = onEntry;
    if (callback == null) throw StateError('Unexpected detail request');
    return callback(locale, id);
  }

  @override
  Future<Object?> resolveEntry(
    String locale, {
    required String collection,
    required int sourceNumber,
  }) async {
    referenceCalls.add((collection: collection, sourceNumber: sourceNumber));
    if (failDetail) throw StateError('offline');
    final callback = onResolveEntry;
    if (callback == null) throw StateError('Unexpected reference request');
    return callback(locale, collection, sourceNumber);
  }

  @override
  Future<void> setFavorite(
    String collection,
    int sourceNumber,
    bool isFavorite, {
    AccountScopeSnapshot? accountScope,
  }) async {
    favoriteWrites.add(_FavoriteWrite(collection, sourceNumber, isFavorite));
  }

  @override
  Future<Object?> favorites(
    String locale, {
    AccountScopeSnapshot? accountScope,
  }) async =>
      onFavorites?.call(locale, accountScope) ??
      <String, Object?>{'results': const <Object?>[]};
}

Future<void> _insertFavoriteIntent(
  Database database, {
  required String operationId,
  required int sourceNumber,
  required bool isFavorite,
}) async {
  await database.insert('outbox', <String, Object?>{
    'owner_id': 'test-owner',
    'operation_id': operationId,
    'entity_type': 'dua_favorite',
    'entity_id': 'dua:hisn-al-muslim:$sourceNumber',
    'payload': jsonEncode(<String, Object?>{
      'collection': 'hisn-al-muslim',
      'source_number': sourceNumber,
      'is_favorite': isFavorite,
    }),
    'created_at': '2026-09-01T10:00:00Z',
  });
}

Map<String, Object?> _page(List<Object?> results, {String? next}) =>
    <String, Object?>{
      'count': results.length,
      'next': next,
      'previous': null,
      'results': results,
    };

Map<String, Object?> _categoryPayload({
  required String title,
  required String version,
}) => <String, Object?>{
  'id': '0192d920-4cb5-7e72-9a4d-000000000027',
  'collection': 'hisn-al-muslim',
  'collection_version': version,
  'source_number': 27,
  'slug': 'sleep',
  'title': title,
  'entry_count': 24,
};

String _nextUrl(String cursor, {String category = 'test'}) =>
    Uri.https('iqro.forum', '/api/v1/dua/entries', <String, String>{
      'language': 'ru',
      'category': category,
      'page_size': '100',
      'cursor': cursor,
    }).toString();

Map<String, Object?> _entryPayload(int number, {String repetitionLabel = ''}) =>
    <String, Object?>{
      'id': _entryId(number),
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

String _entryId(int number) =>
    '0192d920-4cb5-7e72-9a4d-${number.toRadixString(16).padLeft(12, '0')}';

Map<String, Object?> _scopedEntry(String category, int number) {
  final entry = _entryPayload(number);
  entry['category'] = <String, Object?>{
    ...entry['category']! as Map,
    'slug': category,
  };
  return entry;
}

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
      owner_id TEXT NOT NULL,
      item_key TEXT NOT NULL,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, item_key)
    )
  ''');
  await database.execute('''
    CREATE TABLE outbox (
      owner_id TEXT NOT NULL,
      operation_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_error TEXT,
      PRIMARY KEY (owner_id, operation_id)
    )
  ''');
}
