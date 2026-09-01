import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_offline_repository.dart';

const _recitationId = '11111111-1111-4111-8111-111111111111';

void main() {
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

Map<String, Object?> _manifestFixture() {
  final trackMaps = <Map<String, Object?>>[];
  final trackModels = <OfflineAudioTrack>[];
  for (var surah = 1; surah <= 114; surah += 1) {
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
        'https://media.staging.iqro.forum/audio/surah-${surah.toString().padLeft(3, '0')}.mp3',
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
      timing: timing,
      segments: segments,
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
    sourceChecksum: 'a' * 64,
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
