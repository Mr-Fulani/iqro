import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/calendar/calendar_catalog.dart';

const config = AppConfig(
  apiBaseUrl: 'https://staging.iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'staging',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> seed() => Map<String, Object?>.from(
    jsonDecode(File('assets/calendar/events-v1.json').readAsStringSync())
        as Map,
  );

  ProviderContainer container(_Api api, _Cache cache) {
    final result = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        localDatabaseProvider.overrideWithValue(cache),
        appConfigProvider.overrideWithValue(config),
      ],
    );
    result.listen(calendarCatalogProvider, (_, _) {});
    addTearDown(result.dispose);
    return result;
  }

  test(
    'bundled first launch is usable before HTTP and server edits persist',
    () async {
      final api = _Api();
      final cache = _Cache();
      final state = container(api, cache);
      expect(
        (await state.read(calendarCatalogProvider.future)).events,
        hasLength(8),
      );
      await pumpEventQueue();
      final updated = seed();
      ((updated['events'] as List).first['titles'] as Map)['ru'] = 'Из админки';
      api.pending.complete(updated);
      await pumpEventQueue();
      expect(
        state
            .read(calendarCatalogProvider)
            .requireValue
            .events
            .first
            .title('ru'),
        'Из админки',
      );
      expect(cache.values.keys.single, 'calendar:${config.apiV1}:catalog-v1');
      expect(api.paths, ['/calendar/catalog']);
    },
  );

  for (final malformed in [false, true]) {
    test(
      'last-good empty catalog survives ${malformed ? 'invalid data' : 'network failure'} and refresh',
      () async {
        final api = _Api();
        final cache = _Cache();
        final key = 'calendar:${config.apiV1}:catalog-v1';
        final empty = {...seed(), 'events': <Object?>[]};
        await cache.writeCache(key, empty);
        final state = container(api, cache);
        expect(
          (await state.read(calendarCatalogProvider.future)).events,
          isEmpty,
        );
        await pumpEventQueue();
        if (malformed) {
          api.pending.complete({'schema_version': 999});
        } else {
          api.pending.completeError(const SocketException('offline'));
        }
        await pumpEventQueue();
        expect(
          state.read(calendarCatalogProvider).requireValue.events,
          isEmpty,
        );
        expect(cache.values[key]!.value, empty);
        api.pending = Completer<Object?>();
        state.invalidate(calendarCatalogProvider);
        expect(
          (await state.read(calendarCatalogProvider.future)).events,
          isEmpty,
        );
        await pumpEventQueue();
        expect(api.paths, hasLength(2));
        api.pending.complete(seed());
        await pumpEventQueue();
        expect(
          state.read(calendarCatalogProvider).requireValue.events,
          hasLength(8),
        );
      },
    );
  }
}

class _Api implements ApiClient {
  Completer<Object?> pending = Completer<Object?>();
  final paths = <String>[];
  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) {
    expect(public, isTrue);
    paths.add(path);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements LocalDatabase {
  final values = <String, CachedValue>{};
  @override
  Future<CachedValue?> readCache(String key) async => values[key];
  @override
  Future<void> writeCache(
    String key,
    Object? value, {
    String? etag,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    values[key] = CachedValue(value: value, updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
