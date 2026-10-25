import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

const _key = 'quran:${QuranRepository.edition}:surahs';
const _path = '/quran/editions/${QuranRepository.edition}/surahs';

Map<String, Object?> _surah(int number, String name) => <String, Object?>{
  'id': 'surah-$number',
  'number': number,
  'name_ar': 'سورة',
  'name_en': name,
  'name_ru': name,
  'revelation_type': 'meccan',
  'ayah_count': 7,
  'first_page': number,
};

void main() {
  // A device once kept an empty list for a day: every surah list and name in
  // the app went blank until it expired.
  test('a fresh but empty surah cache is fetched again', () async {
    final api = _Api(<Object?>[_surah(1, 'Al-Fatiha'), _surah(2, 'Al-Baqara')]);
    final cache = _Cache()..entries[_key] = _cached(const <Object?>[]);

    final catalog = await QuranRepository(api: api, database: cache).surahs();

    expect(catalog.surahs.map((surah) => surah.number), <int>[1, 2]);
    expect(api.calls, 1);
    expect(cache.entries[_key]!.value, hasLength(2));
  });

  test(
    'an empty response is neither kept nor shown over the old copy',
    () async {
      final api = _Api(const <Object?>[]);
      final cache = _Cache()
        ..entries[_key] = _cached(<Object?>[
          _surah(1, 'Al-Fatiha'),
        ], fresh: false);

      final catalog = await QuranRepository(api: api, database: cache).surahs();

      expect(catalog.fromCache, isTrue);
      expect(catalog.surahs.single.nameEn, 'Al-Fatiha');
      expect(cache.entries[_key]!.value, hasLength(1));
    },
  );

  test(
    'an empty response with nothing cached is an error, not a catalog',
    () async {
      final repository = QuranRepository(
        api: _Api(const <Object?>[]),
        database: _Cache(),
      );

      await expectLater(repository.surahs(), throwsFormatException);
    },
  );
}

CachedValue _cached(List<Object?> payload, {bool fresh = true}) {
  final now = DateTime.now().toUtc();
  return CachedValue(
    value: payload,
    updatedAt: now,
    expiresAt: now.add(
      fresh ? const Duration(hours: 1) : -const Duration(hours: 1),
    ),
  );
}

class _Api implements ApiClient {
  _Api(this.response);

  final Object? response;
  var calls = 0;

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
    expect(path, _path);
    calls += 1;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  final entries = <String, CachedValue>{};

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
