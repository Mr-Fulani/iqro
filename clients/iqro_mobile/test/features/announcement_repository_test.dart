import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/announcements/announcement_logic.dart';
import 'package:iqro_mobile/features/announcements/announcement_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'announcement_test_data.dart';

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Database sql;
  late LocalDatabase database;
  late _Api api;
  late AnnouncementRepository repository;

  setUp(() async {
    sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await sql.execute('''
      CREATE TABLE cache_entries (
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        etag TEXT,
        updated_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
    await sql.execute('''
      CREATE TABLE device_state (
        state_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await sql.execute('''
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
    final scope = AccountScope.forTesting('user-1');
    database = LocalDatabase.forTesting(sql, accountScope: scope);
    api = _Api(AuthRepository(config: _config, accountScope: scope));
    repository = AnnouncementRepository(
      api: api,
      database: database,
      platform: 'android',
      appVersion: () async => '1.0.0',
    );
  });

  tearDown(() => sql.close());

  test('active announcements come for this app and stay for offline', () async {
    api.responses['/announcements/active'] = <String, Object?>{
      'enabled': true,
      'results': <Object?>[
        announcementPayload(),
        // The server leaves fundraising out for the app; the app does too.
        announcementPayload(<String, Object?>{
          'id': announcementIdB,
          'kind': 'fundraising',
        }),
        announcementPayload(<String, Object?>{
          'id': announcementIdC,
          'ends_at': '2026-10-23T00:00:00Z',
        }),
      ],
    };

    final online = await repository.active(locale: 'ru');
    expect(online.fromCache, isFalse);
    expect(online.items.map((item) => item.id), [
      announcementIdA,
      announcementIdC,
    ]);
    expect(api.queries.single, <String, Object?>{
      'platform': 'android',
      'locale': 'ru',
      'app_version': '1.0.0',
    });
    expect(api.publicPaths, ['/announcements/active']);

    // Without the network the last copy is used, minus what has run out.
    api.offline = true;
    final offline = await repository.active(
      locale: 'ru',
      refresh: true,
      now: DateTime.utc(2026, 10, 25),
    );
    expect(offline.fromCache, isTrue);
    expect(offline.items.map((item) => item.id), [announcementIdA]);

    // Another language has no copy yet.
    await expectLater(
      repository.active(locale: 'en', refresh: true),
      throwsA(isA<ApiException>()),
    );
  });

  test('a switched-off announcement service shows nothing', () async {
    api.responses['/announcements/active'] = <String, Object?>{
      'enabled': false,
      'results': <Object?>[announcementPayload()],
    };
    expect((await repository.active(locale: 'ru')).items, isEmpty);
  });

  test('the feed keeps its first page for reading offline', () async {
    api.responses['/announcements'] = <String, Object?>{
      'next_cursor': 'abc',
      'results': <Object?>[
        announcementPayload(),
        announcementPayload(<String, Object?>{
          'id': announcementIdB,
          'kind': 'fundraising',
        }),
      ],
    };
    final online = await repository.feed(locale: 'ru', kind: 'reciter');
    expect(online.page.nextCursor, 'abc');
    expect(online.page.results.map((item) => item.id), [announcementIdA]);
    expect(api.queries.single['kind'], 'reciter');

    api.offline = true;
    final offline = await repository.feed(locale: 'ru', kind: 'reciter');
    expect(offline.fromCache, isTrue);
    expect(offline.page.nextCursor, isNull);
    expect(offline.page.results.map((item) => item.id), [announcementIdA]);
    await expectLater(
      repository.feed(locale: 'ru', kind: 'reciter', cursor: 'abc'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a mark is sent with its wave and leaves the outbox', () async {
    await repository.sendReceipt(announcementIdA, read: true, wave: 2);
    expect(api.puts, hasLength(1));
    expect(api.puts.single.$1, '/me/announcement-receipts/$announcementIdA');
    expect(api.puts.single.$2, <String, Object?>{'read': true, 'wave': 2});
    expect(await sql.query('outbox'), isEmpty);
  });

  test('without the network the mark waits in the outbox', () async {
    api.offline = true;
    await repository.sendReceipt(announcementIdA, dismissed: true, wave: 3);
    final rows = await sql.query('outbox');
    expect(rows, hasLength(1));
    expect(rows.single['owner_id'], 'user-1');
    expect(rows.single['entity_type'], announcementReceiptEntity);
    expect(rows.single['entity_id'], announcementIdA);
    expect(rows.single['attempts'], 1);
    expect(
      rows.single['payload'],
      '{"announcement_id":"$announcementIdA","dismissed":true,"wave":3}',
    );
  });

  test('a mark on a withdrawn announcement is dropped', () async {
    api.putError = const ApiException(message: 'Not found', statusCode: 404);
    await repository.sendReceipt(announcementIdA, read: true, wave: 1);
    expect(await sql.query('outbox'), isEmpty);
  });

  test('the marks of this device survive a restart', () async {
    final state = markRead(
      const AnnouncementLocalState(),
      announcementIdA,
      DateTime.utc(2026, 10, 22),
      2,
    );
    await repository.saveState(state);
    final restored = await AnnouncementRepository(
      api: api,
      database: database,
      platform: 'android',
    ).loadState();
    expect(restored.toJson(), state.toJson());
  });

  test('counters go out anonymously in batches of 50', () async {
    for (var index = 0; index < 51; index++) {
      repository.track(announcementIdA, 'bubble', 'impression', 1);
    }
    await repository.flushEvents();
    expect(api.posts, hasLength(2));
    final first = api.posts.first;
    expect(first.$1, '/announcements/events');
    expect((first.$2 as Map)['platform'], 'android');
    expect((first.$2 as Map)['events'], hasLength(50));
    expect(((first.$2 as Map)['events'] as List).first, <String, Object?>{
      'id': announcementIdA,
      'surface': 'bubble',
      'event': 'impression',
      'wave': 1,
    });
    expect(api.publicPaths, ['/announcements/events', '/announcements/events']);

    // Counters never fail the app.
    api.offline = true;
    repository.track(announcementIdA, 'bubble', 'open', 1);
    await repository.flushEvents();
    expect(repository.pendingEvents, 0);
  });
}

class _Api extends ApiClient {
  _Api(AuthRepository auth)
    : super(config: _config, authRepository: auth, locale: () => 'ru');

  final responses = <String, Object?>{};
  final queries = <Map<String, Object?>>[];
  final publicPaths = <String>[];
  final puts = <(String, Object?)>[];
  final posts = <(String, Object?)>[];
  var offline = false;
  ApiException? putError;

  ApiException get _offline => const ApiException(message: 'Offline');

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw _offline;
    if (public) publicPaths.add(path);
    queries.add(query ?? const <String, Object?>{});
    return responses[path];
  }

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw _offline;
    final error = putError;
    if (error != null) throw error;
    puts.add((path, data));
    return <String, Object?>{};
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    bool public = false,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw _offline;
    if (public) publicPaths.add(path);
    posts.add((path, data));
    return <String, Object?>{'accepted': 1};
  }
}
