import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/audio/audio_offline_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _recitationId = '11111111-1111-4111-8111-111111111111';

void main() {
  setUpAll(sqfliteFfiInit);

  test('offline audio manifest verifies 114 surahs and canonical checksum', () {
    final fixture = _manifestFixture();

    final manifest = OfflineAudioManifest.fromJson(
      fixture,
      recitationId: _recitationId,
    );

    expect(manifest.tracks, hasLength(114));
    expect(manifest.tracks.first.surah, 1);
    expect(manifest.tracks.last.surah, 114);
    expect(manifest.computedChecksum, manifest.packageChecksum);

    final tampered = Map<String, Object?>.from(
      jsonDecode(jsonEncode(fixture)) as Map,
    );
    final tracks = (tampered['tracks']! as List).cast<Map<String, Object?>>();
    tracks.first['duration_ms'] = 999999;
    expect(
      () =>
          OfflineAudioManifest.fromJson(tampered, recitationId: _recitationId),
      throwsFormatException,
    );
  });

  test(
    'offline audio rejects incomplete, unlicensed and external packages',
    () {
      final incomplete = _mutableFixture();
      (incomplete['tracks']! as List).removeLast();
      expect(
        () => OfflineAudioManifest.fromJson(
          incomplete,
          recitationId: _recitationId,
        ),
        throwsFormatException,
      );

      final unlicensed = _mutableFixture();
      (unlicensed['rights']! as Map<String, Object?>)['offline_download'] =
          false;
      expect(
        () => OfflineAudioManifest.fromJson(
          unlicensed,
          recitationId: _recitationId,
        ),
        throwsFormatException,
      );

      final external = _mutableFixture();
      final tracks = (external['tracks']! as List).cast<Map<String, Object?>>();
      final asset = tracks.first['asset']! as Map<String, Object?>;
      asset['url'] = 'https://example.com/surah-001.mp3';
      expect(
        () => OfflineAudioManifest.fromJson(
          external,
          recitationId: _recitationId,
        ),
        throwsFormatException,
      );
    },
  );

  test('a listening-only package carries the surahs it lists', () {
    final manifest = OfflineAudioManifest.fromJson(
      _manifestFixture(surahs: const <int>[1, 112], listeningOnly: true),
      recitationId: _recitationId,
    );

    expect(manifest.listeningOnly, isTrue);
    expect(manifest.tracks.map((track) => track.surah), <int>[1, 112]);
    expect(manifest.sourceChecksum, isEmpty);

    final complete = OfflineAudioManifest.fromJson(
      _manifestFixture(surahNumbers: true),
      recitationId: _recitationId,
    );
    expect(complete.tracks, hasLength(114));
  });

  test('surah_numbers must match the tracks and partial needs listening', () {
    Map<String, Object?> partial() => Map<String, Object?>.from(
      jsonDecode(
            jsonEncode(
              _manifestFixture(
                surahs: const <int>[1, 112],
                listeningOnly: true,
              ),
            ),
          )
          as Map,
    );

    final mismatched = partial()..['surah_numbers'] = <int>[1, 113];
    final timed = partial()..['listening_only'] = false;
    final unlisted = partial()..remove('surah_numbers');
    for (final json in <Map<String, Object?>>[mismatched, timed, unlisted]) {
      expect(
        () => OfflineAudioManifest.fromJson(json, recitationId: _recitationId),
        throwsFormatException,
      );
    }
  });

  test('a grown listening package downloads only its new surahs', () async {
    final harness = await _harness();
    final repository = harness.repository;
    harness.api.manifest = _manifestFixture(
      surahs: const <int>[1, 112],
      listeningOnly: true,
    );

    final estimate = await repository.estimate(recitationId: _recitationId);
    expect(estimate.totalTracks, 2);
    expect(estimate.completedTracks, 0);

    final installed = await repository.install(recitationId: _recitationId);
    expect(installed.status, AudioDownloadStatus.ready);
    expect(installed.totalTracks, 2);
    expect(harness.api.downloads, <int>[1, 112]);
    expect(
      (await repository.check(_recitationId)).status,
      AudioDownloadStatus.ready,
    );
    expect(
      await repository.activePlayback(recitationId: _recitationId, surah: 113),
      isNull,
    );

    harness.api.manifest = _manifestFixture(
      surahs: const <int>[1, 112, 113],
      listeningOnly: true,
    );
    final update = await repository.check(_recitationId);
    expect(update.status, AudioDownloadStatus.updateAvailable);
    expect(update.completedTracks, 2);
    expect(update.totalTracks, 3);
    expect(update.totalBytes - update.downloadedBytes, _mp3Bytes(113).length);

    // A failed update leaves the stored surahs playable.
    harness.api.failDownloads = true;
    await expectLater(
      repository.install(recitationId: _recitationId),
      throwsStateError,
    );
    expect(
      (await repository.snapshot(_recitationId)).status,
      AudioDownloadStatus.ready,
    );
    expect(
      await repository.activePlayback(recitationId: _recitationId, surah: 1),
      isNotNull,
    );

    harness.api.failDownloads = false;
    harness.api.onDownload = (surah) async {
      expect(
        (await repository.snapshot(_recitationId)).status,
        AudioDownloadStatus.ready,
      );
      expect(
        await repository.activePlayback(recitationId: _recitationId, surah: 1),
        isNotNull,
      );
    };
    final updated = await repository.install(recitationId: _recitationId);

    expect(updated.status, AudioDownloadStatus.ready);
    expect(updated.totalTracks, 3);
    expect(harness.api.downloads, <int>[1, 112, 113, 113]);
    expect(
      (await repository.check(_recitationId)).status,
      AudioDownloadStatus.ready,
    );
    final stored = await repository.snapshot(_recitationId);
    expect(stored.completedTracks, 3);
    expect(stored.totalTracks, 3);
    expect(
      await repository.activePlayback(recitationId: _recitationId, surah: 113),
      isNotNull,
    );
  });

  test('downloaded audio must match signature, size and SHA-256', () async {
    final bytes = _mp3Bytes(1);
    final directory = await Directory.systemTemp.createTemp('iqro-audio-test-');
    final file = File('${directory.path}/surah-001.mp3');
    await file.writeAsBytes(bytes);
    final asset = OfflineAudioAsset(
      url: Uri.parse('https://media.iqro.forum/audio/surah-001.mp3'),
      fileName: 'surah-001.mp3',
      contentType: 'audio/mpeg',
      codec: 'mp3',
      bitrateKbps: 128,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      etag: '"immutable-test"',
    );

    expect(await verifyAudioAssetFile(file, asset), isTrue);
    await file.writeAsBytes(<int>[...bytes]..[0] = 0x00);
    expect(await verifyAudioAssetFile(file, asset), isFalse);

    await directory.delete(recursive: true);
  });
}

/// Without [surahs] a complete package as servers before surah_numbers sent.
Map<String, Object?> _manifestFixture({
  List<int>? surahs,
  bool listeningOnly = false,
  bool surahNumbers = false,
}) {
  final trackMaps = <Map<String, Object?>>[];
  final trackModels = <OfflineAudioTrack>[];
  final numbers = surahs ?? List<int>.generate(114, (index) => index + 1);
  for (final surah in numbers) {
    final bytes = _mp3Bytes(surah);
    final checksum = sha256.convert(bytes).toString();
    final id = _uuidFor(surah);
    final ayahId = _uuidFor(surah + 200);
    final segments = <Map<String, Object?>>[
      <String, Object?>{
        'ayah_id': ayahId,
        'ayah_number': 1,
        'start_ms': 0,
        'end_ms': 900,
      },
    ];
    final asset = OfflineAudioAsset(
      url: Uri.parse(
        'https://media.iqro.forum/audio/surah-${surah.toString().padLeft(3, '0')}.mp3',
      ),
      fileName: 'surah-${surah.toString().padLeft(3, '0')}.mp3',
      contentType: 'audio/mpeg',
      codec: 'mp3',
      bitrateKbps: 128,
      bytes: bytes.length,
      sha256: checksum,
      etag: '"surah-$surah"',
    );
    final timing = <String, Object?>{
      'version': '1.0.0',
      'source_checksum_sha256': 'b' * 64,
    };
    final track = OfflineAudioTrack(
      id: id,
      surah: surah,
      durationMs: 1000,
      renditionQuality: 'standard',
      timing: listeningOnly ? null : timing,
      segments: listeningOnly ? const <Map<String, Object?>>[] : segments,
      asset: asset,
    );
    trackModels.add(track);
    trackMaps.add(<String, Object?>{
      ...track.checksumJson,
      'asset': <String, Object?>{
        ...asset.checksumJson,
        'url': asset.url.toString(),
        'range_supported': true,
        'immutable': true,
      },
    });
  }
  final packageId = 'recitation-$_recitationId-1.0.0-standard';
  final provisional = OfflineAudioManifest(
    recitationId: _recitationId,
    packageId: packageId,
    version: '1.0.0',
    quality: 'standard',
    availableQualities: const <String>['economy', 'standard'],
    packageChecksum: '0' * 64,
    sourceChecksum: listeningOnly ? '' : 'a' * 64,
    totalBytes: trackModels.fold<int>(
      0,
      (sum, track) => sum + track.asset.bytes,
    ),
    tracks: trackModels,
    raw: const <String, Object?>{},
  );
  return <String, Object?>{
    'schema_version': 1,
    'package_type': 'surah_audio',
    'package_id': packageId,
    'version': '1.0.0',
    'quality': 'standard',
    'available_qualities': const <String>['economy', 'standard'],
    'package_checksum_sha256': provisional.computedChecksum,
    'published_at': '2026-01-01T00:00:00Z',
    'source': <String, Object?>{
      'name': 'Test',
      'url': 'https://example.test',
      'version': '1.0.0',
      'checksum_sha256': provisional.sourceChecksum,
    },
    'license': const <String, Object?>{},
    'rights': const <String, Object?>{'stream': true, 'offline_download': true},
    'reciter': const <String, Object?>{},
    'quran_edition': <String, Object?>{
      'code': 'madani-hafs',
      'version': '1.0.0',
      'checksum_sha256': 'c' * 64,
    },
    if (surahs != null || surahNumbers) ...<String, Object?>{
      'listening_only': listeningOnly,
      'surah_numbers': numbers,
    },
    'track_count': trackModels.length,
    'total_bytes': provisional.totalBytes,
    'tracks': trackMaps,
  };
}

Map<String, Object?> _mutableFixture() => Map<String, Object?>.from(
  jsonDecode(jsonEncode(_manifestFixture())) as Map,
);

String _uuidFor(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

List<int> _mp3Bytes(int marker) => <int>[
  0x49,
  0x44,
  0x33,
  4,
  marker & 0xff,
  0,
  0,
  0,
  0,
  0,
  1,
  2,
  3,
  4,
  5,
  6,
];

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

class _Harness {
  _Harness(this.repository, this.api);

  final AudioOfflineRepository repository;
  final _OfflineAudioApi api;
}

Future<_Harness> _harness() async {
  final support = await Directory.systemTemp.createTemp('iqro-audio-offline-');
  final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await raw.execute('''
    CREATE TABLE offline_packages (
      package_id TEXT PRIMARY KEY,
      package_type TEXT NOT NULL,
      content_key TEXT NOT NULL,
      version TEXT NOT NULL,
      width INTEGER,
      checksum_sha256 TEXT NOT NULL,
      manifest TEXT NOT NULL,
      status TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 0,
      total_items INTEGER NOT NULL,
      completed_items INTEGER NOT NULL DEFAULT 0,
      total_bytes INTEGER NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
  await raw.execute('''
    CREATE TABLE offline_package_items (
      package_id TEXT NOT NULL,
      item_key TEXT NOT NULL,
      item_number INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      local_path TEXT NOT NULL,
      url TEXT NOT NULL,
      checksum_sha256 TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      metadata TEXT NOT NULL,
      status TEXT NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (package_id, item_key)
    )
  ''');
  addTearDown(() async {
    await raw.close();
    if (await support.exists()) await support.delete(recursive: true);
  });
  final accountScope = AccountScope.forTesting('account-a');
  final api = _OfflineAudioApi(
    AuthRepository(config: _config, accountScope: accountScope),
  );
  return _Harness(
    AudioOfflineRepository(
      api: api,
      database: LocalDatabase.forTesting(raw),
      supportDirectory: () async => support,
    ),
    api,
  );
}

class _OfflineAudioApi extends ApiClient {
  _OfflineAudioApi(AuthRepository auth)
    : super(config: _config, authRepository: auth, locale: () => 'ru');

  Map<String, Object?> manifest = const <String, Object?>{};
  final List<int> downloads = <int>[];
  bool failDownloads = false;
  Future<void> Function(int surah)? onDownload;

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) async {
    if (path != '/recitations/$_recitationId/offline-manifest') {
      throw StateError('Unexpected GET $path');
    }
    return jsonDecode(jsonEncode(manifest));
  }

  @override
  Future<int> downloadPublicFile(
    Uri uri,
    File destination, {
    required Set<String> allowedHosts,
    required int expectedBytes,
    String? expectedEtag,
    int maxBytes = 8 * 1024 * 1024,
    void Function(int received, int total)? onProgress,
  }) async {
    final surah = int.parse(RegExp(r'surah-(\d+)').firstMatch(uri.path)![1]!);
    downloads.add(surah);
    if (failDownloads) throw StateError('Network is down');
    await onDownload?.call(surah);
    final bytes = _mp3Bytes(surah);
    await destination.writeAsBytes(bytes, flush: true);
    return bytes.length;
  }
}
