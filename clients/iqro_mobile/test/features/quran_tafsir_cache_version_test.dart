import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

const _catalogKey = 'quran:tafsirs:catalog:ru';
const _surahKey = 'quran:tafsirs:170:surah:112';
const _surahPath = '/quran/tafsirs/170/surahs/112';
const _published = '2026-10-21T01:07:13Z';
const _republished = '2026-11-12T09:00:00Z';

List<Object?> _catalog(String publishedAt) => <Object?>[
  <String, Object?>{
    'source_id': 170,
    'language_code': 'ru',
    'name': "Al-Sa'di",
    'author_name': 'Saddi',
    'active_version': <String, Object?>{
      'sync_sequence': 547646,
      'published_at': publishedAt,
    },
  },
];

List<Object?> _rows(String text) => <Object?>[
  <String, Object?>{
    'verse_key': '112:1',
    'start_verse_key': '112:1',
    'end_verse_key': '112:4',
    'text': text,
  },
];

Future<String> _read(_Api api, _Cache cache) async {
  // A new repository stands for the next app start: nothing kept in memory.
  final repository = QuranRepository(api: api, database: cache);
  await repository.tafsirEditions('ru');
  return (await repository.tafsirs(sourceId: 170, surah: 112)).single.text;
}

void main() {
  // Phones kept the misplaced Al-Sa'di texts for up to 30 days after the
  // server was corrected: nothing in the kept copy said which version it was.
  test('a surah kept from an older version of the edition is loaded again '
      'once the catalog shows the new one', () async {
    final api = _Api(catalog: _catalog(_published), rows: _rows('old'));
    final cache = _Cache();
    expect(await _read(api, cache), 'old');
    expect(await _read(api, cache), 'old');
    expect(api.surahCalls, 1, reason: 'the kept copy is still current');

    api
      ..catalog = _catalog(_republished)
      ..rows = _rows('corrected');
    cache.expire(_catalogKey);

    expect(await _read(api, cache), 'corrected');
    expect(await _read(api, cache), 'corrected');
    expect(api.surahCalls, 2, reason: 'one request per surah and version');
  });

  test('offline, the copy of the older version is still shown', () async {
    final api = _Api(catalog: _catalog(_published), rows: _rows('old'));
    final cache = _Cache();
    await _read(api, cache);

    api
      ..catalog = _catalog(_republished)
      ..rows = null;
    cache.expire(_catalogKey);
    expect(await _read(api, cache), 'old');

    api.catalog = null;
    cache.expire(_catalogKey);
    expect(await _read(api, cache), 'old');
  });

  test('a copy kept before versions were recorded is loaded again', () async {
    final api = _Api(catalog: _catalog(_published), rows: _rows('corrected'));
    final cache = _Cache();
    await cache.writeCache(
      _surahKey,
      _rows('misplaced'),
      maxAge: const Duration(days: 30),
    );

    expect(await _read(api, cache), 'corrected');
    expect(await _read(api, cache), 'corrected');
    expect(api.surahCalls, 1);
  });

  test('offline, a copy kept before versions were recorded is shown', () async {
    final api = _Api(catalog: _catalog(_published), rows: null);
    final cache = _Cache();
    await cache.writeCache(
      _surahKey,
      _rows('misplaced'),
      maxAge: const Duration(days: 30),
    );

    expect(await _read(api, cache), 'misplaced');
  });
}

class _Api implements ApiClient {
  _Api({required this.catalog, required this.rows});

  /// `null` stands for a request that fails: the phone is offline.
  List<Object?>? catalog;
  List<Object?>? rows;
  var surahCalls = 0;

  @override
  final Dio dio = Dio();

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    final response = path == '/quran/tafsirs' ? catalog : rows;
    if (path != '/quran/tafsirs') {
      expect(path, _surahPath);
      surahCalls += 1;
    }
    if (response == null) throw StateError('offline');
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  final entries = <String, CachedValue>{};

  void expire(String key) {
    final entry = entries[key]!;
    entries[key] = CachedValue(
      value: entry.value,
      updatedAt: entry.updatedAt,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
  }

  @override
  Future<CachedValue?> readCache(String key) async => entries[key];

  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final now = DateTime.now().toUtc();
    entries[key] = CachedValue(
      value: value,
      updatedAt: now,
      expiresAt: now.add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
