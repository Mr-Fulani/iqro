import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/audio/audio_offline_repository.dart';
import 'package:iqro_mobile/features/audio/audio_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<(AudioRepository, _PagedCatalogApi)> createRepository({
    required Map<String, List<Map<String, Object?>>> catalogs,
    int serverPageSize = 100,
    bool repeatCursor = false,
  }) async {
    final sqlDatabase = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(sqlDatabase.close);
    await sqlDatabase.execute('''
      CREATE TABLE cache_entries (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        etag TEXT,
        updated_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
    final accountScope = AccountScope.forTesting('account-a');
    final database = LocalDatabase.forTesting(
      sqlDatabase,
      accountScope: accountScope,
    );
    final api = _PagedCatalogApi(
      AuthRepository(config: _config, accountScope: accountScope),
      catalogs: catalogs,
      serverPageSize: serverPageSize,
      repeatCursor: repeatCursor,
    );
    final repository = AudioRepository(
      api: api,
      database: database,
      offline: AudioOfflineRepository(api: api, database: database),
    );
    return (repository, api);
  }

  test('loads every reciter page instead of only the first one', () async {
    final (repository, api) = await createRepository(
      catalogs: {
        '/reciters': List.generate(237, (index) => _reciter(index + 1)),
      },
    );

    final reciters = await repository.reciters();

    expect(reciters, hasLength(237));
    expect(reciters.last.slug, 'qf-237-reciter');
    expect(api.requests.map((query) => query['cursor']), <Object?>[
      null,
      'c100',
      'c200',
    ]);
    expect(api.requests.every((query) => query['page_size'] == 100), isTrue);

    // The merged catalog is cached, so a later read needs no more pages.
    expect(await repository.reciters(), hasLength(237));
    expect(api.requests, hasLength(3));
  });

  test('keeps recitation filters on every cursor page', () async {
    final (repository, api) = await createRepository(
      catalogs: {
        '/recitations': List.generate(
          130,
          (index) => _recitation(index + 1, reciterId: 'reciter-7'),
        ),
      },
    );

    final recitations = await repository.recitations(reciterId: 'reciter-7');

    expect(recitations, hasLength(130));
    expect(api.requests, hasLength(2));
    for (final query in api.requests) {
      expect(query['reciter_id'], 'reciter-7');
      expect(query['quran_edition'], 'madani-hafs');
    }
  });

  test('rejects a cursor that repeats instead of looping forever', () async {
    final (repository, _) = await createRepository(
      catalogs: {
        '/reciters': List.generate(30, (index) => _reciter(index + 1)),
      },
      serverPageSize: 10,
      repeatCursor: true,
    );

    await expectLater(repository.reciters(), throwsFormatException);
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

Map<String, Object?> _reciter(int index) => <String, Object?>{
  'id': 'reciter-$index',
  'slug': 'qf-$index-reciter',
  'name_ar': 'قارئ $index',
  'name_en': 'Reciter $index',
  'name_ru': 'Чтец $index',
};

Map<String, Object?> _recitation(int index, {required String reciterId}) =>
    <String, Object?>{
      'id': 'recitation-$index',
      'code': 'qf-$index-murattal',
      'style': 'murattal',
      'reciter': <String, Object?>{'id': reciterId, 'name_en': 'Reciter'},
      'coverage': <String, Object?>{'surah_count': 114},
      'rights': <String, Object?>{'stream': true},
    };

class _PagedCatalogApi extends ApiClient {
  _PagedCatalogApi(
    AuthRepository auth, {
    required this.catalogs,
    required this.serverPageSize,
    required this.repeatCursor,
  }) : super(config: _config, authRepository: auth, locale: () => 'ru');

  final Map<String, List<Map<String, Object?>>> catalogs;
  final int serverPageSize;
  final bool repeatCursor;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    final items = catalogs[path];
    if (items == null) throw StateError('Unexpected GET $path');
    requests.add(Map<String, Object?>.of(query ?? const {}));
    final cursor = query?['cursor'] as String?;
    final offset = cursor == null ? 0 : int.parse(cursor.substring(1));
    final end = (offset + serverPageSize).clamp(0, items.length);
    final nextOffset = repeatCursor ? serverPageSize : end;
    return <String, Object?>{
      'next': end < items.length
          ? 'https://iqro.forum/api/v1$path?cursor=c$nextOffset'
                '&page_size=$serverPageSize'
          : null,
      'previous': null,
      'results': items.sublist(offset, end),
    };
  }
}
