import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/offline_package_items.dart';
import '../../core/storage/offline_storage_quota.dart';
import '../../core/utils/json_helpers.dart';
import 'audio_models.dart';

const _approvedAudioAssetHosts = <String>{
  'media.staging.iqro.forum',
  'media.iqro.forum',
};
const _audioPackageType = 'surah_audio';
const _audioEdition = 'madani-hafs';
const _audioQualities = <String>{'default', 'economy', 'standard', 'high'};
const _audioCodecs = <String>{'mp3', 'aac', 'opus', 'flac'};

enum AudioDownloadStatus { notDownloaded, downloading, ready, failed }

class AudioDownloadSnapshot {
  const AudioDownloadSnapshot({
    required this.status,
    required this.recitationId,
    this.packageId,
    this.quality,
    this.completedTracks = 0,
    this.totalTracks = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  const AudioDownloadSnapshot.empty(String recitationId)
    : this(
        status: AudioDownloadStatus.notDownloaded,
        recitationId: recitationId,
      );

  final AudioDownloadStatus status;
  final String recitationId;
  final String? packageId;
  final String? quality;
  final int completedTracks;
  final int totalTracks;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  double get progress => totalBytes <= 0
      ? 0
      : (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
}

class OfflineAudioAsset {
  const OfflineAudioAsset({
    required this.url,
    required this.fileName,
    required this.contentType,
    required this.codec,
    required this.bitrateKbps,
    required this.bytes,
    required this.sha256,
    required this.etag,
  });

  final Uri url;
  final String fileName;
  final String contentType;
  final String codec;
  final int bitrateKbps;
  final int bytes;
  final String sha256;
  final String etag;

  Map<String, Object?> get checksumJson => <String, Object?>{
    'file_name': fileName,
    'content_type': contentType,
    'codec': codec,
    'bitrate_kbps': bitrateKbps,
    'bytes': bytes,
    'sha256': sha256,
    'etag': etag,
  };
}

class OfflineAudioTrack {
  const OfflineAudioTrack({
    required this.id,
    required this.surah,
    required this.durationMs,
    required this.renditionQuality,
    required this.timing,
    required this.segments,
    required this.asset,
  });

  final String id;
  final int surah;
  final int durationMs;
  final String renditionQuality;
  final Map<String, Object?>? timing;
  final List<Map<String, Object?>> segments;
  final OfflineAudioAsset asset;

  Map<String, Object?> get checksumJson => <String, Object?>{
    'id': id,
    'surah_number': surah,
    'duration_ms': durationMs,
    'rendition_quality': renditionQuality,
    'timing': timing,
    'segments': segments,
    'asset': asset.checksumJson,
  };

  Map<String, Object?> playbackJson(
    String recitationId,
    Uri localUri,
  ) => <String, Object?>{
    'track': <String, Object?>{
      'id': id,
      'recitation_id': recitationId,
      'surah_number': surah,
      'duration_ms': durationMs,
      'offline_download_allowed': true,
      'selected_quality': renditionQuality,
      'asset': <String, Object?>{'url': localUri.toString()},
    },
    'segments': segments
        .map((segment) => <String, Object?>{...segment, 'surah_number': surah})
        .toList(growable: false),
  };
}

class OfflineAudioManifest {
  const OfflineAudioManifest({
    required this.recitationId,
    required this.packageId,
    required this.version,
    required this.quality,
    required this.availableQualities,
    required this.packageChecksum,
    required this.sourceChecksum,
    required this.totalBytes,
    required this.tracks,
    required this.raw,
  });

  factory OfflineAudioManifest.fromJson(
    Map<String, Object?> json, {
    required String recitationId,
  }) {
    final rights = jsonMap(json['rights']);
    final source = jsonMap(json['source']);
    final edition = jsonMap(json['quran_edition']);
    final rawTracks = json['tracks'];
    final packageId = json['package_id']?.toString() ?? '';
    final version = json['version']?.toString() ?? '';
    final quality = json['quality']?.toString() ?? '';
    final packageChecksum = json['package_checksum_sha256']?.toString() ?? '';
    final sourceChecksum = source['checksum_sha256']?.toString() ?? '';
    final trackCount = (json['track_count'] as num?)?.toInt() ?? 0;
    final totalBytes = (json['total_bytes'] as num?)?.toInt() ?? 0;
    final rawQualities = json['available_qualities'];
    final expectedPackageId = 'recitation-$recitationId-$version-$quality';
    if (json['schema_version'] != 1 ||
        json['package_type'] != _audioPackageType ||
        rights['stream'] != true ||
        rights['offline_download'] != true ||
        edition['code'] != _audioEdition ||
        !_isUuid(recitationId) ||
        packageId != expectedPackageId ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(packageId) ||
        version.isEmpty ||
        !_audioQualities.contains(quality) ||
        !_isSha256(packageChecksum) ||
        !_isSha256(sourceChecksum) ||
        rawQualities is! List ||
        rawTracks is! List ||
        rawTracks.isEmpty) {
      throw const FormatException('Offline audio manifest is invalid');
    }

    final availableQualities = rawQualities.whereType<String>().toSet().toList(
      growable: false,
    );
    if (availableQualities.length != rawQualities.length ||
        !availableQualities.every(_audioQualities.contains) ||
        (quality != 'default' && !availableQualities.contains(quality))) {
      throw const FormatException('Offline audio quality is invalid');
    }
    final tracks = rawTracks
        .whereType<Map>()
        .map(
          (item) => _parseTrack(
            Map<String, Object?>.from(item),
            packageQuality: quality,
          ),
        )
        .toList(growable: false);
    if (tracks.length != rawTracks.length ||
        tracks.length != trackCount ||
        trackCount != 114 ||
        totalBytes !=
            tracks.fold<int>(0, (sum, track) => sum + track.asset.bytes)) {
      throw const FormatException('Offline audio coverage is incomplete');
    }
    for (var index = 0; index < tracks.length; index += 1) {
      if (tracks[index].surah != index + 1) {
        throw const FormatException('Offline audio surahs are not contiguous');
      }
    }

    final manifest = OfflineAudioManifest(
      recitationId: recitationId,
      packageId: packageId,
      version: version,
      quality: quality,
      availableQualities: availableQualities,
      packageChecksum: packageChecksum,
      sourceChecksum: sourceChecksum,
      totalBytes: totalBytes,
      tracks: tracks,
      raw: json,
    );
    if (manifest.computedChecksum != packageChecksum) {
      throw const FormatException('Offline audio manifest checksum failed');
    }
    return manifest;
  }

  final String recitationId;
  final String packageId;
  final String version;
  final String quality;
  final List<String> availableQualities;
  final String packageChecksum;
  final String sourceChecksum;
  final int totalBytes;
  final List<OfflineAudioTrack> tracks;
  final Map<String, Object?> raw;

  String get computedChecksum {
    final payload = <String, Object?>{
      'schema_version': 1,
      'package_type': _audioPackageType,
      'package_id': packageId,
      'version': version,
      'quality': quality,
      'source_checksum_sha256': sourceChecksum,
      'tracks': tracks.map((track) => track.checksumJson).toList(),
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalJson(payload))))
        .toString();
  }

  static OfflineAudioTrack _parseTrack(
    Map<String, Object?> json, {
    required String packageQuality,
  }) {
    final id = json['id']?.toString() ?? '';
    final surah = (json['surah_number'] as num?)?.toInt() ?? 0;
    final durationMs = (json['duration_ms'] as num?)?.toInt() ?? 0;
    final renditionQuality = json['rendition_quality']?.toString() ?? '';
    final rawTiming = json['timing'];
    final timing = rawTiming == null ? null : jsonMap(rawTiming);
    final rawSegments = json['segments'];
    final assetJson = jsonMap(json['asset']);
    if (!_isUuid(id) ||
        surah < 1 ||
        surah > 114 ||
        durationMs <= 0 ||
        !_audioQualities.contains(renditionQuality) ||
        renditionQuality == 'default' ||
        (packageQuality != 'default' && renditionQuality != packageQuality) ||
        rawSegments is! List ||
        (timing != null &&
            (timing['version']?.toString().isEmpty != false ||
                !_isSha256(
                  timing['source_checksum_sha256']?.toString() ?? '',
                )))) {
      throw const FormatException('Offline audio track is invalid');
    }
    final segments = rawSegments
        .whereType<Map>()
        .map(
          (item) => _parseSegment(Map<String, Object?>.from(item), durationMs),
        )
        .toList(growable: false);
    if (segments.length != rawSegments.length) {
      throw const FormatException('Offline audio timings are invalid');
    }
    for (var index = 1; index < segments.length; index += 1) {
      if ((segments[index]['ayah_number']! as int) <=
              (segments[index - 1]['ayah_number']! as int) ||
          (segments[index]['start_ms']! as int) <
              (segments[index - 1]['start_ms']! as int)) {
        throw const FormatException('Offline audio timings are not ordered');
      }
    }
    return OfflineAudioTrack(
      id: id,
      surah: surah,
      durationMs: durationMs,
      renditionQuality: renditionQuality,
      timing: timing,
      segments: segments,
      asset: _parseAsset(assetJson, surah),
    );
  }

  static Map<String, Object?> _parseSegment(
    Map<String, Object?> json,
    int durationMs,
  ) {
    final ayahId = json['ayah_id']?.toString() ?? '';
    final ayah = (json['ayah_number'] as num?)?.toInt() ?? 0;
    final start = (json['start_ms'] as num?)?.toInt() ?? -1;
    final end = (json['end_ms'] as num?)?.toInt() ?? -1;
    if (!_isUuid(ayahId) ||
        ayah <= 0 ||
        start < 0 ||
        end <= start ||
        end > durationMs + 2000) {
      throw const FormatException('Offline audio segment is invalid');
    }
    return <String, Object?>{
      'ayah_id': ayahId,
      'ayah_number': ayah,
      'start_ms': start,
      'end_ms': end,
    };
  }

  static OfflineAudioAsset _parseAsset(Map<String, Object?> json, int surah) {
    final url = Uri.tryParse(json['url']?.toString() ?? '');
    final fileName = json['file_name']?.toString() ?? '';
    final contentType = json['content_type']?.toString() ?? '';
    final codec = json['codec']?.toString() ?? '';
    final bitrateKbps = (json['bitrate_kbps'] as num?)?.toInt() ?? 0;
    final bytes = (json['bytes'] as num?)?.toInt() ?? 0;
    final checksum = json['sha256']?.toString() ?? '';
    final etag = json['etag']?.toString() ?? '';
    final expectedContentType = switch (codec) {
      'mp3' => 'audio/mpeg',
      'aac' => 'audio/aac',
      'opus' => 'audio/ogg',
      'flac' => 'audio/flac',
      _ => '',
    };
    if (url == null ||
        url.scheme != 'https' ||
        !_approvedAudioAssetHosts.contains(url.host) ||
        !_audioCodecs.contains(codec) ||
        contentType != expectedContentType ||
        fileName != 'surah-${surah.toString().padLeft(3, '0')}.$codec' ||
        !url.path.toLowerCase().endsWith('.$codec') ||
        bitrateKbps <= 0 ||
        bytes <= 0 ||
        bytes > 512 * 1024 * 1024 ||
        !_isSha256(checksum) ||
        etag.isEmpty ||
        json['range_supported'] != true ||
        json['immutable'] != true) {
      throw const FormatException('Offline audio asset is invalid');
    }
    return OfflineAudioAsset(
      url: url,
      fileName: fileName,
      contentType: contentType,
      codec: codec,
      bitrateKbps: bitrateKbps,
      bytes: bytes,
      sha256: checksum,
      etag: etag,
    );
  }
}

typedef AudioDirectoryProvider = Future<Directory> Function();

class AudioOfflineRepository {
  AudioOfflineRepository({
    required ApiClient api,
    required LocalDatabase database,
    AudioDirectoryProvider? supportDirectory,
  }) : _api = api,
       _database = database,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final ApiClient _api;
  final LocalDatabase _database;
  final AudioDirectoryProvider _supportDirectory;

  Future<AudioDownloadSnapshot> snapshot(String recitationId) async {
    final rows = await _database.database.query(
      'offline_packages',
      where: 'content_key = ?',
      whereArgs: <Object?>[_contentKey(recitationId)],
      orderBy: 'is_active DESC, updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return AudioDownloadSnapshot.empty(recitationId);
    return _snapshotFromRow(rows.single, recitationId);
  }

  Future<AudioDownloadSnapshot> install({
    required String recitationId,
    String? quality,
    int expectedTrackCount = 114,
    void Function(AudioDownloadSnapshot progress)? onProgress,
  }) async {
    final manifest = await _manifest(
      recitationId: recitationId,
      quality: quality,
      expectedTrackCount: expectedTrackCount,
    );
    await ensureOfflineStorageCapacity(
      _database,
      packageId: manifest.packageId,
      packageBytes: manifest.totalBytes,
    );
    final support = await _supportDirectory();
    final packageDirectory = Directory(
      p.join(support.path, 'offline_packages', 'audio', manifest.packageId),
    );
    await packageDirectory.create(recursive: true);
    await _preparePackage(manifest, packageDirectory);

    var completedTracks = 0;
    var completedBytes = 0;
    try {
      for (final track in manifest.tracks) {
        final destination = File(
          p.join(packageDirectory.path, track.asset.fileName),
        );
        if (!await verifyAudioAssetFile(destination, track.asset)) {
          final partial = File(
            '${destination.path}.${track.asset.sha256.substring(0, 12)}.part',
          );
          await _api.downloadPublicFile(
            track.asset.url,
            partial,
            allowedHosts: _approvedAudioAssetHosts,
            expectedBytes: track.asset.bytes,
            expectedEtag: track.asset.etag,
            maxBytes: 512 * 1024 * 1024,
            onProgress: (received, total) {
              onProgress?.call(
                AudioDownloadSnapshot(
                  status: AudioDownloadStatus.downloading,
                  recitationId: recitationId,
                  packageId: manifest.packageId,
                  quality: manifest.quality,
                  completedTracks: completedTracks,
                  totalTracks: manifest.tracks.length,
                  downloadedBytes: completedBytes + received,
                  totalBytes: manifest.totalBytes,
                ),
              );
            },
          );
          if (!await verifyAudioAssetFile(partial, track.asset)) {
            await partial.writeAsBytes(const <int>[], flush: true);
            throw const FormatException(
              'Downloaded audio failed its integrity check',
            );
          }
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
        }
        completedTracks += 1;
        completedBytes += track.asset.bytes;
        await _markTrackReady(
          manifest,
          track,
          completedTracks: completedTracks,
          completedBytes: completedBytes,
        );
        onProgress?.call(
          AudioDownloadSnapshot(
            status: AudioDownloadStatus.downloading,
            recitationId: recitationId,
            packageId: manifest.packageId,
            quality: manifest.quality,
            completedTracks: completedTracks,
            totalTracks: manifest.tracks.length,
            downloadedBytes: completedBytes,
            totalBytes: manifest.totalBytes,
          ),
        );
      }
      await _activate(manifest);
      final ready = AudioDownloadSnapshot(
        status: AudioDownloadStatus.ready,
        recitationId: recitationId,
        packageId: manifest.packageId,
        quality: manifest.quality,
        completedTracks: completedTracks,
        totalTracks: manifest.tracks.length,
        downloadedBytes: completedBytes,
        totalBytes: manifest.totalBytes,
      );
      onProgress?.call(ready);
      return ready;
    } on Object catch (error) {
      await _markPackageFailed(manifest.packageId, error);
      rethrow;
    }
  }

  Future<AudioDownloadSnapshot> estimate({
    required String recitationId,
    String? quality,
    int expectedTrackCount = 114,
  }) async {
    final manifest = await _manifest(
      recitationId: recitationId,
      quality: quality,
      expectedTrackCount: expectedTrackCount,
    );
    return AudioDownloadSnapshot(
      status: AudioDownloadStatus.notDownloaded,
      recitationId: recitationId,
      packageId: manifest.packageId,
      quality: manifest.quality,
      totalTracks: manifest.tracks.length,
      totalBytes: manifest.totalBytes,
    );
  }

  Future<OfflineAudioManifest> _manifest({
    required String recitationId,
    required String? quality,
    required int expectedTrackCount,
  }) async {
    if (!_isUuid(recitationId) ||
        (quality != null &&
            (quality == 'default' || !_audioQualities.contains(quality)))) {
      throw const FormatException('Offline audio request is invalid');
    }
    final payload = await _api.get(
      '/recitations/$recitationId/offline-manifest',
      query: quality == null ? null : <String, Object?>{'quality': quality},
      public: true,
    );
    final manifest = OfflineAudioManifest.fromJson(
      jsonMap(payload),
      recitationId: recitationId,
    );
    if (manifest.tracks.length != expectedTrackCount) {
      throw const FormatException('The offline audio package is not complete');
    }
    return manifest;
  }

  Future<SurahPlayback?> activePlayback({
    required String recitationId,
    required int surah,
  }) async {
    if (!_isUuid(recitationId) || surah < 1 || surah > 114) return null;
    final rows = await _database.database.rawQuery(
      '''
      SELECT item.local_path, item.size_bytes, item.metadata
      FROM offline_package_items AS item
      INNER JOIN offline_packages AS package
        ON package.package_id = item.package_id
      WHERE package.content_key = ?
        AND package.package_type = ?
        AND package.status = 'ready'
        AND package.is_active = 1
        AND item.item_number = ?
        AND item.status = 'ready'
      LIMIT 1
      ''',
      <Object?>[_contentKey(recitationId), _audioPackageType, surah],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = File(row['local_path']! as String);
    if (!await file.exists() || await file.length() != row['size_bytes']) {
      return null;
    }
    final metadata = jsonDecode(row['metadata']! as String);
    if (metadata is! Map) return null;
    final track = Map<String, Object?>.from(metadata);
    if ((track['surah_number'] as num?)?.toInt() != surah ||
        !_isUuid(track['id']?.toString() ?? '') ||
        (track['duration_ms'] as num?) == null ||
        track['segments'] is! List) {
      return null;
    }
    return SurahPlayback.fromJson(<String, Object?>{
      'track': <String, Object?>{
        'id': track['id'],
        'recitation_id': recitationId,
        'surah_number': surah,
        'duration_ms': track['duration_ms'],
        'offline_download_allowed': true,
        'selected_quality': track['rendition_quality'],
        'asset': <String, Object?>{'url': file.uri.toString()},
      },
      'segments': (track['segments']! as List)
          .whereType<Map>()
          .map(
            (segment) => <String, Object?>{
              ...Map<String, Object?>.from(segment),
              'surah_number': surah,
            },
          )
          .toList(growable: false),
    });
  }

  Future<void> _preparePackage(
    OfflineAudioManifest manifest,
    Directory packageDirectory,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.insert('offline_packages', <String, Object?>{
        'package_id': manifest.packageId,
        'package_type': _audioPackageType,
        'content_key': _contentKey(manifest.recitationId),
        'version': manifest.version,
        'width': null,
        'checksum_sha256': manifest.packageChecksum,
        'manifest': jsonEncode(manifest.raw),
        'status': 'downloading',
        'is_active': 0,
        'total_items': manifest.tracks.length,
        'completed_items': 0,
        'total_bytes': manifest.totalBytes,
        'downloaded_bytes': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'manifest': jsonEncode(manifest.raw),
          'status': 'downloading',
          'total_items': manifest.tracks.length,
          'total_bytes': manifest.totalBytes,
          'last_error': null,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
      final items = transaction.batch();
      for (final track in manifest.tracks) {
        final localPath = p.join(packageDirectory.path, track.asset.fileName);
        enqueueOfflinePackageItem(
          items,
          packageId: manifest.packageId,
          itemKey: 'surah:${track.surah}',
          itemNumber: track.surah,
          fileName: track.asset.fileName,
          localPath: localPath,
          url: track.asset.url.toString(),
          checksum: track.asset.sha256,
          sizeBytes: track.asset.bytes,
          metadata: jsonEncode(track.checksumJson),
          updatedAt: now,
        );
      }
      await items.commit(noResult: true);
    });
  }

  Future<void> _markTrackReady(
    OfflineAudioManifest manifest,
    OfflineAudioTrack track, {
    required int completedTracks,
    required int completedBytes,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'offline_package_items',
        <String, Object?>{
          'status': 'ready',
          'downloaded_bytes': track.asset.bytes,
          'updated_at': now,
        },
        where: 'package_id = ? AND item_key = ?',
        whereArgs: <Object?>[manifest.packageId, 'surah:${track.surah}'],
      );
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'completed_items': completedTracks,
          'downloaded_bytes': completedBytes,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
    });
  }

  Future<void> _activate(OfflineAudioManifest manifest) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'offline_packages',
        <String, Object?>{'is_active': 0},
        where: 'content_key = ?',
        whereArgs: <Object?>[_contentKey(manifest.recitationId)],
      );
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'status': 'ready',
          'is_active': 1,
          'completed_items': manifest.tracks.length,
          'downloaded_bytes': manifest.totalBytes,
          'last_error': null,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
    });
  }

  Future<void> _markPackageFailed(String packageId, Object error) async {
    final message = error.toString();
    await _database.database.update(
      'offline_packages',
      <String, Object?>{
        'status': 'failed',
        'last_error': message.substring(0, message.length.clamp(0, 500)),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'package_id = ?',
      whereArgs: <Object?>[packageId],
    );
  }

  AudioDownloadSnapshot _snapshotFromRow(
    Map<String, Object?> row,
    String recitationId,
  ) {
    final status = switch (row['status']) {
      'ready' => AudioDownloadStatus.ready,
      'downloading' => AudioDownloadStatus.failed,
      'failed' => AudioDownloadStatus.failed,
      _ => AudioDownloadStatus.notDownloaded,
    };
    final manifest = jsonDecode(row['manifest']! as String);
    final quality = manifest is Map ? manifest['quality']?.toString() : null;
    return AudioDownloadSnapshot(
      status: status,
      recitationId: recitationId,
      packageId: row['package_id'] as String?,
      quality: quality,
      completedTracks: row['completed_items']! as int,
      totalTracks: row['total_items']! as int,
      downloadedBytes: row['downloaded_bytes']! as int,
      totalBytes: row['total_bytes']! as int,
      error: row['last_error'] as String?,
    );
  }
}

Future<bool> verifyAudioAssetFile(File file, OfflineAudioAsset asset) async {
  if (!await file.exists() || await file.length() != asset.bytes) return false;
  final header = await file
      .openRead(0, 16)
      .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
  if (!_validAudioHeader(header, asset.codec)) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == asset.sha256;
}

bool _validAudioHeader(List<int> bytes, String codec) {
  if (bytes.length < 4) return false;
  return switch (codec) {
    'mp3' =>
      (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
          (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0),
    'aac' => bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0,
    'opus' =>
      bytes.length >= 12 &&
          bytes[0] == 0x4f &&
          bytes[1] == 0x67 &&
          bytes[2] == 0x67 &&
          bytes[3] == 0x53,
    'flac' =>
      bytes[0] == 0x66 &&
          bytes[1] == 0x4c &&
          bytes[2] == 0x61 &&
          bytes[3] == 0x43,
    _ => false,
  };
}

String _contentKey(String recitationId) => 'recitation:$recitationId';
bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool _isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value);

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _canonicalJson(entry.value);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}
