import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:iqro_mobile/features/quran/mushaf_offline_repository.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = MushafIdentity.fromPreference('native:qcf-v2-hafs');

  test(
    'visual keys never replace canonical Quran, audio or downloaded package keys',
    () {
      expect(MushafIdentity.canonical.contentKey, 'quran-edition:madani-hafs');
      expect(
        MushafIdentity.canonical.pageCacheKey(3),
        'quran:madani-hafs:page:3',
      );
      expect(native.contentKey, 'mushaf-rendition:qcf-v2-hafs');
      expect(native.pageCacheKey(3), 'mushaf-rendition:qcf-v2-hafs:page:3');
      expect(native.apiPath, '/quran/mushaf-renditions/qcf-v2-hafs');
      expect(QuranRepository.edition, 'madani-hafs');
    },
  );

  test('only complete native Hafs catalog entries are selectable', () {
    final json = <String, Object?>{
      'code': 'qcf-v2-hafs',
      'names': {'en': 'QCF V2', 'ar': 'مصحف'},
      'available': true,
      'canonical_edition': 'madani-hafs',
      'pages_count': 604,
      'format': 'raster-regions-v1',
      'checksum_sha256': 'a' * 64,
      'version': 'v1',
      'staging_only': true,
    };
    expect(NativeMushafEdition.parse(json)!.nameFor('ar'), 'مصحف');
    expect(NativeMushafEdition.parse(json)!.nameFor('tr'), 'QCF V2');
    for (final change in <Map<String, Object?>>[
      {'pages_count': 603},
      {'available': false},
      {'code': '../bad'},
      {'format': 'web-font'},
      {'checksum_sha256': ''},
      {'canonical_edition': 'warsh'},
    ]) {
      expect(NativeMushafEdition.parse({...json, ...change}), isNull);
    }
  });

  test('staging preference cannot enable a preview in production', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesStore(await SharedPreferences.getInstance());
    await store.write(store.read().copyWith(mushafVariant: native.preference));
    for (final env in ['staging', 'production']) {
      final container = ProviderContainer(
        overrides: [
          preferencesStoreProvider.overrideWithValue(store),
          planRepositoryProvider.overrideWithValue(_Plan()),
          appConfigProvider.overrideWithValue(
            AppConfig(
              apiBaseUrl: 'https://iqro.forum',
              fallbackDownloadUrl: 'https://iqro.forum',
              environment: env,
            ),
          ),
        ],
      );
      expect(
        container.read(selectedMushafIdentityProvider),
        env == 'staging' ? native : MushafIdentity.canonical,
      );
      container.dispose();
    }
  });

  test(
    'page cache and API paths are isolated across visual editions',
    () async {
      final cache = _Cache();
      final api = _Api();
      final old = QuranRepository(api: api, database: cache);
      final next = old.forMushaf(native);
      expect((await old.mushafPage(3)).editionCode, 'madani-hafs');
      expect((await next.mushafPage(3)).editionCode, native.code);
      expect(
        cache.entries.keys,
        containsAll([
          MushafIdentity.canonical.pageCacheKey(3),
          native.pageCacheKey(3),
        ]),
      );
      api.offline = true;
      expect((await old.mushafPage(3)).editionCode, 'madani-hafs');
      expect((await next.mushafPage(3)).editionCode, native.code);
      api.offline = false;
      api.wrongEdition = true;
      await expectLater(next.mushafPage(4), throwsFormatException);
      expect(cache.entries.containsKey(native.pageCacheKey(4)), isFalse);
    },
  );

  test(
    'switching edition during a download does not update a disposed controller',
    () async {
      final repo = _Offline();
      final controller = MushafDownloadController(repo);
      await Future<void>.delayed(Duration.zero);
      final task = controller.download();
      controller.dispose();
      repo.progress?.call(const MushafDownloadSnapshot.empty());
      repo.result.complete(
        const MushafDownloadSnapshot(status: MushafDownloadStatus.ready),
      );
      await task;
    },
  );

  test(
    'switching away and back retains the single in-flight download',
    () async {
      final choice = StateProvider<MushafIdentity>((ref) => native);
      final repo = _Offline();
      final container = ProviderContainer(
        overrides: [
          selectedMushafIdentityProvider.overrideWith(
            (ref) => ref.watch(choice),
          ),
          mushafOfflineRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final original = container.read(selectedMushafDownloadControllerProvider);
      final job = original.download();
      container.read(choice.notifier).state = MushafIdentity.canonical;
      expect(
        container.read(selectedMushafDownloadControllerProvider),
        isNot(same(original)),
      );
      container.read(choice.notifier).state = native;
      final restored = container.read(selectedMushafDownloadControllerProvider);
      expect(restored, same(original));
      await restored.download();
      expect(repo.installs, 1);
      repo.result.complete(
        const MushafDownloadSnapshot(status: MushafDownloadStatus.ready),
      );
      await job;
      expect(
        container.read(mushafDownloadProvider).status,
        MushafDownloadStatus.ready,
      );
    },
  );

  test(
    'edge-to-edge native page is not cropped by legacy landscape gutter compensation',
    () {
      final layout = calculateMushafPageLayout(
        viewport: const Size(800, 400),
        source: const Size(1000, 1600),
        landscapeBleedFactor: 1,
      );
      expect(layout.width, 800);
      expect(layout.horizontalOffset, 0);
      expect(layout.height, 1280);
    },
  );
}

class _Plan implements PlanRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    entries[key] = CachedValue(value: value, updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements ApiClient {
  bool offline = false;
  bool wrongEdition = false;
  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (offline) throw StateError('offline');
    final native = path.contains('mushaf-renditions') && !wrongEdition;
    return {
      'number': int.parse(path.split('/').last),
      'edition_code': native ? 'qcf-v2-hafs' : 'madani-hafs',
      'content_version': 'v1',
      'image_width': 1000,
      'image_height': 1600,
      'assets': [],
      'regions': [],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Offline implements MushafOfflineRepository {
  int installs = 0;
  @override
  MushafOfflineRepository forMushaf(MushafIdentity identity) => this;
  final result = Completer<MushafDownloadSnapshot>();
  void Function(MushafDownloadSnapshot)? progress;
  @override
  Future<MushafDownloadSnapshot> snapshot() async =>
      const MushafDownloadSnapshot.empty();
  @override
  Future<MushafDownloadSnapshot> install({
    int? width,
    int expectedPageCount = 604,
    void Function(MushafDownloadSnapshot)? onProgress,
  }) {
    installs++;
    progress = onProgress;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
