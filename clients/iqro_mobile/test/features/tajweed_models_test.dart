import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_models.dart';
import 'package:iqro_mobile/features/tajweed/tajweed_repository.dart';

import 'tajweed_test_data.dart';

void main() {
  test('rule reference keeps its order, colours, texts and variants', () {
    final reference = TajweedReference.fromJson(tajweedRulesJson);
    expect(reference.pendingReview, isTrue);
    expect(reference.rules.map((rule) => rule.code), [
      'ikhafa',
      'idgham_wo_ghunnah',
      'qalaqah',
      'madda_normal',
    ]);
    final madd = reference.rule('madda_normal')!;
    expect(madd.color, const Color(0xFFCE9E00));
    expect(madd.arabicName, 'المد الطبيعي');
    expect(tajweedText(madd.name, 'ru'), 'Мадд табии');
    expect(tajweedText(madd.name, 'de'), 'Natural madd');
    expect(
      tajweedText(madd.variant('silah_sughra')!.why, 'en'),
      'The pronoun ha between voweled letters.',
    );
    expect(madd.variant('missing'), isNull);
    expect(
      reference
          .present(['madda_normal', 'idgham_wo_ghunnah'])
          .map((rule) => rule.code),
      ['idgham_wo_ghunnah', 'madda_normal'],
    );
  });

  test('page words carry fragments with their joins and variants', () {
    final page = TajweedPage.fromJson(tajweedPage604Json, 604);
    final ayah = page.ayah('112:4')!;
    expect(ayah.page, 604);
    expect(ayah.words.map((word) => word.position), [2, 3, 5]);
    final yakun = ayah.word(2)!.rules.single;
    expect((yakun.code, yakun.start, yakun.end), ('idgham_wo_ghunnah', 3, 5));
    expect(
      (yakun.joinsNext, yakun.joinsPrevious, yakun.variant),
      (true, false, null),
    );
    final lahu = ayah.word(3)!.rules;
    expect(lahu.first.joinsPrevious, isTrue);
    expect(lahu.last.variant, 'silah_sughra');
    expect(ayah.word(1), isNull);
    expect(
      () => TajweedPage.fromJson(tajweedPage604Json, 603),
      throwsFormatException,
    );
    expect(
      () => TajweedFragment.fromJson({'code': 'x', 'start': 2, 'end': 2}),
      throwsFormatException,
    );
    expect(
      () => TajweedRule.fromJson({
        ...(tajweedRulesJson['rules']! as List).first as Map<String, Object?>,
        'color': 'green',
      }),
      throwsFormatException,
    );
  });

  test('runs colour the narrower rule where rules nest', () {
    const word = 'قَالُوٓا';
    final runs = tajweedRuns(word, const [
      TajweedFragment(code: 'madda_normal', start: 1, end: 8),
      TajweedFragment(code: 'slnt', start: 7, end: 8),
    ]);
    expect(runs.map((run) => run.text).join(), word);
    expect(runs.map((run) => run.code), [null, 'madda_normal', 'slnt']);
    expect(runs.last.text, 'ا');
    expect(tajweedRuns('لَّهُۥ', const []).single.code, isNull);
  });

  test('runs keep vowel marks with their letter', () {
    final ayah = TajweedAyah.fromJson(tajweedAyah1124Json);
    final qalqalah = tajweedRuns('أَحَدُۢ', ayah.word(5)!.rules);
    expect(qalqalah.map((run) => run.text), ['أَحَ', 'دُۢ']);
    expect(qalqalah.map((run) => run.code), [null, 'qalaqah']);
    final idgham = tajweedRuns('يَكُن', ayah.word(2)!.rules);
    expect(idgham.map((run) => run.text), ['يَكُ', 'ن']);
  });

  test('a rule joining two words is one occurrence with both words', () {
    final ayah = TajweedAyah.fromJson(tajweedAyah1124Json);
    final fromSecond = tajweedJoinedParts(
      ayah,
      ayah.word(3)!,
      ayah.word(3)!.rules.first,
    );
    expect(fromSecond.map((part) => part.word.text), ['يَكُن', 'لَّهُۥ']);
    final fromFirst = tajweedJoinedParts(
      ayah,
      ayah.word(2)!,
      ayah.word(2)!.rules.single,
    );
    expect(fromFirst.map((part) => part.word.position), [2, 3]);

    final idgham = tajweedOccurrences([ayah], 'idgham_wo_ghunnah');
    expect(idgham, hasLength(1));
    expect(idgham.single.map((part) => part.word.position), [2, 3]);
    expect(
      tajweedOccurrences([ayah], 'qalaqah').single.single.word.text,
      'أَحَدُۢ',
    );
    expect(tajweedOccurrences([ayah], 'ikhafa'), isEmpty);
  });

  test('ayah playback keeps only valid word timings', () {
    final playback = AyahPlayback.fromJson({
      'track': {
        'id': 'track',
        'recitation_id': 'recitation',
        'surah_number': 112,
        'duration_ms': 60000,
        'asset': {'url': 'https://cdn.example/112.mp3'},
      },
      'segment': {
        'ayah_id': 'a',
        'surah_number': 112,
        'ayah_number': 4,
        'start_ms': 9000,
        'end_ms': 14000,
        'words': [
          [1, 9000, 9600],
          [2, 9600, 10100],
          [3, 10100, 10100],
          [4, -5, 100],
          [5, 'x', 1],
          [6, 12000],
        ],
      },
    });
    expect(playback.track.url, 'https://cdn.example/112.mp3');
    expect(playback.words.keys, [1, 2]);
    expect(playback.words[2], (
      start: const Duration(milliseconds: 9600),
      end: const Duration(milliseconds: 10100),
    ));
    expect(
      AyahPlayback.fromJson({
        'track': {'asset': <String, Object?>{}},
        'segment': <String, Object?>{},
      }).words,
      isEmpty,
    );
  });

  group('repository', () {
    test('caches rules and pages, falls back to stale data offline', () async {
      final api = _Api();
      final cache = _Cache();
      final repository = TajweedRepository(api: api, database: cache);
      expect((await repository.rules())!.rules, hasLength(4));
      expect((await repository.page(604))!.ayahs.single.verseKey, '112:4');
      expect(cache.maxAges, {
        'quran:tajweed:rules': const Duration(days: 7),
        'quran:tajweed:page:604': const Duration(days: 30),
      });

      // Fresh entries do not reach the network.
      api.offline = true;
      expect(await repository.page(604), isNotNull);
      expect(api.requests, 2);

      // Expired entries are refreshed, and kept when the refresh fails.
      cache.expireAll();
      expect((await repository.rules())!.pendingReview, isTrue);
      expect((await repository.page(604))!.number, 604);
      expect(api.requests, 4);
    });

    test('a missing markup is no tajweed and is not cached', () async {
      final api = _Api()..missing = true;
      final cache = _Cache();
      final repository = TajweedRepository(api: api, database: cache);
      expect(await repository.page(1), isNull);
      expect(cache.entries, isEmpty);
      // Further page turns do not ask again while the markup is missing.
      expect(await repository.page(2), isNull);
      expect(api.requests, 1);

      final fresh = TajweedRepository(api: api, database: cache);
      api.missing = false;
      api.offline = true;
      await expectLater(fresh.page(1), throwsA(isA<StateError>()));
    });
  });
}

class _Cache implements LocalDatabase {
  final entries = <String, CachedValue>{};
  final maxAges = <String, Duration>{};

  void expireAll() {
    for (final MapEntry(:key, :value) in entries.entries.toList()) {
      entries[key] = CachedValue(
        value: value.value,
        updatedAt: value.updatedAt,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
    }
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
    maxAges[key] = maxAge;
    entries[key] = CachedValue(
      value: value,
      updatedAt: DateTime.now(),
      expiresAt: DateTime.now().toUtc().add(maxAge),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements ApiClient {
  @override
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
  var offline = false;
  var missing = false;
  var requests = 0;

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    requests++;
    if (offline) throw StateError('offline');
    if (missing) {
      throw const ApiException(message: 'Not found', statusCode: 404);
    }
    if (path == '/quran/tajweed/rules') return tajweedRulesJson;
    if (path == '/quran/tajweed/pages/604') return tajweedPage604Json;
    throw StateError('unexpected $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
