import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/network/api_client.dart';
import '../../core/network/public_asset_uri.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/offline_package_items.dart';
import '../../core/storage/offline_package_queries.dart';
import '../../core/storage/offline_storage_quota.dart';
import '../../core/utils/json_helpers.dart';
import 'quran_models.dart';
import 'mushaf_edition.dart';

const _mushafEdition = 'kfgqpc-hafs';
const _approvedMushafAssetHosts = <String>{'media.iqro.forum'};

enum MushafDownloadStatus { notDownloaded, downloading, ready, failed }

class MushafDownloadSnapshot {
  const MushafDownloadSnapshot({
    required this.status,
    this.packageId,
    this.completedPages = 0,
    this.totalPages = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  const MushafDownloadSnapshot.empty()
    : this(status: MushafDownloadStatus.notDownloaded);

  final MushafDownloadStatus status;
  final String? packageId;
  final int completedPages;
  final int totalPages;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  double get progress => totalBytes <= 0
      ? 0
      : (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
}

class OfflineMushafPage {
  const OfflineMushafPage({
    required this.number,
    required this.url,
    required this.fileName,
    required this.width,
    required this.height,
    required this.bytes,
    required this.sha256,
    required this.metadata,
  });

  final int number;
  final Uri url;
  final String fileName;
  final int width;
  final int height;
  final int bytes;
  final String sha256;
  final Map<String, Object?> metadata;
}

class OfflineMushafManifest {
  const OfflineMushafManifest({
    required this.packageId,
    required this.version,
    required this.packageChecksum,
    required this.sourceChecksum,
    required this.width,
    required this.totalBytes,
    required this.pages,
    required this.raw,
  });

  factory OfflineMushafManifest.fromJson(
    Map<String, Object?> json, {
    String expectedEdition = _mushafEdition,
    Uri? localApiBase,
  }) {
    final rights = jsonMap(json['rights']);
    final identity = jsonMap(json['mushaf']);
    final source = jsonMap(json['source']);
    final rawPages = json['pages'];
    final packageId = json['package_id']?.toString() ?? '';
    final version = json['version']?.toString() ?? '';
    final packageChecksum = json['package_checksum_sha256']?.toString() ?? '';
    final sourceChecksum = source['checksum_sha256']?.toString() ?? '';
    final width = (json['width'] as num?)?.toInt() ?? 0;
    final declaredPageCount = (json['page_count'] as num?)?.toInt() ?? 0;
    final declaredTotalBytes = (json['total_bytes'] as num?)?.toInt() ?? 0;
    if (json['schema_version'] != 1 ||
        json['package_type'] != 'mushaf_pages' ||
        rights['offline_download'] != true ||
        identity['edition_code'] != expectedEdition ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(packageId) ||
        version.isEmpty ||
        !_isSha256(packageChecksum) ||
        !_isSha256(sourceChecksum) ||
        width <= 0 ||
        rawPages is! List ||
        rawPages.isEmpty) {
      throw const FormatException('Offline Mushaf manifest is invalid');
    }

    final pages = rawPages
        .whereType<Map>()
        .map(
          (item) => _parsePage(
            Map<String, Object?>.from(item),
            width,
            expectedEdition,
            localApiBase,
          ),
        )
        .toList(growable: false);
    if (pages.length != rawPages.length ||
        pages.length != declaredPageCount ||
        declaredPageCount <= 0 ||
        declaredTotalBytes !=
            pages.fold<int>(0, (sum, page) => sum + page.bytes)) {
      throw const FormatException('Offline Mushaf coverage is incomplete');
    }
    for (var index = 0; index < pages.length; index += 1) {
      if (pages[index].number != index + 1) {
        throw const FormatException('Offline Mushaf pages are not contiguous');
      }
    }

    final manifest = OfflineMushafManifest(
      packageId: packageId,
      version: version,
      packageChecksum: packageChecksum,
      sourceChecksum: sourceChecksum,
      width: width,
      totalBytes: declaredTotalBytes,
      pages: pages,
      raw: json,
    );
    if (manifest.computedChecksum != packageChecksum) {
      throw const FormatException('Offline Mushaf manifest checksum failed');
    }
    return manifest;
  }

  final String packageId;
  final String version;
  final String packageChecksum;
  final String sourceChecksum;
  final int width;
  final int totalBytes;
  final List<OfflineMushafPage> pages;
  final Map<String, Object?> raw;

  String get computedChecksum {
    final checksumPages = pages
        .map(
          (page) => <String, Object?>{
            'number': page.number,
            'metadata': _metadataWithoutAssetUrl(page.metadata),
          },
        )
        .toList(growable: false);
    final payload = <String, Object?>{
      'schema_version': 1,
      'package_type': 'mushaf_pages',
      'package_id': packageId,
      'version': version,
      'source_checksum_sha256': sourceChecksum,
      'pages': checksumPages,
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalJson(payload))))
        .toString();
  }

  static OfflineMushafPage _parsePage(
    Map<String, Object?> json,
    int width,
    String expectedEdition,
    Uri? localApiBase,
  ) {
    final number = (json['number'] as num?)?.toInt() ?? 0;
    final asset = jsonMap(json['asset']);
    final metadata = jsonMap(json['metadata']);
    final rawUrl = asset['url']?.toString() ?? '';
    final url = localApiBase == null
        ? Uri.tryParse(rawUrl)
        : localApiBase.resolve(rawUrl);
    final fileName = asset['file_name']?.toString() ?? '';
    final assetWidth = (asset['width'] as num?)?.toInt() ?? 0;
    final height = (asset['height'] as num?)?.toInt() ?? 0;
    final bytes = (asset['bytes'] as num?)?.toInt() ?? 0;
    final checksum = asset['sha256']?.toString() ?? '';
    if (number <= 0 ||
        url == null ||
        !isApprovedPublicAssetUri(
          url,
          allowedHosts: _approvedMushafAssetHosts,
          localApiBase: localApiBase,
        ) ||
        !url.path.toLowerCase().endsWith('.webp') ||
        !RegExp(r'^page-\d{3,4}-\d+\.webp$').hasMatch(fileName) ||
        asset['content_type'] != 'image/webp' ||
        assetWidth != width ||
        height <= 0 ||
        bytes <= 0 ||
        bytes > 4 * 1024 * 1024 ||
        !_isSha256(checksum) ||
        metadata.isEmpty) {
      throw const FormatException('Offline Mushaf page asset is invalid');
    }
    final pageData = MushafPageData.fromJson(metadata);
    final metadataAsset = pageData.assets.singleOrNull;
    if (pageData.number != number ||
        pageData.editionCode != expectedEdition ||
        metadataAsset == null ||
        metadataAsset.url != rawUrl ||
        metadataAsset.width != width ||
        metadataAsset.height != height ||
        metadataAsset.bytes != bytes ||
        metadataAsset.sha256 != checksum) {
      throw const FormatException(
        'Offline Mushaf page metadata is inconsistent',
      );
    }
    return OfflineMushafPage(
      number: number,
      url: url,
      fileName: fileName,
      width: width,
      height: height,
      bytes: bytes,
      sha256: checksum,
      metadata: metadata,
    );
  }
}

typedef MushafDirectoryProvider = Future<Directory> Function();

class MushafOfflineRepository {
  MushafOfflineRepository({
    required ApiClient api,
    required LocalDatabase database,
    MushafDirectoryProvider? supportDirectory,
    this.mushaf = MushafIdentity.primary,
  }) : _api = api,
       _database = database,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final ApiClient _api;
  final LocalDatabase _database;
  final MushafDirectoryProvider _supportDirectory;
  final MushafIdentity mushaf;
  String get _mushafContentKey => mushaf.contentKey;

  MushafOfflineRepository forMushaf(MushafIdentity identity) =>
      identity == mushaf
      ? this
      : MushafOfflineRepository(
          api: _api,
          database: _database,
          supportDirectory: _supportDirectory,
          mushaf: identity,
        );

  Future<MushafDownloadSnapshot> snapshot() async {
    final rows = await _database.database.query(
      'offline_packages',
      columns: offlinePackageSummaryColumns,
      where: 'content_key = ?',
      whereArgs: <Object?>[_mushafContentKey],
      orderBy: 'is_active DESC, updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return const MushafDownloadSnapshot.empty();
    return _snapshotFromRow(rows.single);
  }

  Future<MushafDownloadSnapshot> install({
    int? width,
    int expectedPageCount = 604,
    void Function(MushafDownloadSnapshot progress)? onProgress,
  }) async {
    final manifest = await _manifest(width, expectedPageCount);
    await ensureOfflineStorageCapacity(
      _database,
      packageId: manifest.packageId,
      packageBytes: manifest.totalBytes,
    );
    final support = await _supportDirectory();
    final packageDirectory = Directory(
      p.join(support.path, 'offline_packages', 'mushaf', manifest.packageId),
    );
    await packageDirectory.create(recursive: true);
    await _preparePackage(manifest, packageDirectory);

    var completedPages = 0;
    var completedBytes = 0;
    try {
      for (final page in manifest.pages) {
        final destination = File(p.join(packageDirectory.path, page.fileName));
        if (!await verifyMushafAssetFile(destination, page)) {
          final partial = File('${destination.path}.part');
          await _api.downloadPublicFile(
            page.url,
            partial,
            allowedHosts: _approvedMushafAssetHosts,
            expectedBytes: page.bytes,
            maxBytes: 4 * 1024 * 1024,
            onProgress: (received, total) {
              onProgress?.call(
                MushafDownloadSnapshot(
                  status: MushafDownloadStatus.downloading,
                  packageId: manifest.packageId,
                  completedPages: completedPages,
                  totalPages: manifest.pages.length,
                  downloadedBytes: completedBytes + received,
                  totalBytes: manifest.totalBytes,
                ),
              );
            },
          );
          if (!await verifyMushafAssetFile(partial, page)) {
            await partial.writeAsBytes(const <int>[], flush: true);
            throw const FormatException(
              'Downloaded Mushaf page failed integrity check',
            );
          }
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
        }
        completedPages += 1;
        completedBytes += page.bytes;
        await _markPageReady(
          manifest,
          page,
          completedPages: completedPages,
          completedBytes: completedBytes,
        );
        onProgress?.call(
          MushafDownloadSnapshot(
            status: MushafDownloadStatus.downloading,
            packageId: manifest.packageId,
            completedPages: completedPages,
            totalPages: manifest.pages.length,
            downloadedBytes: completedBytes,
            totalBytes: manifest.totalBytes,
          ),
        );
      }
      await _activate(manifest);
      final ready = MushafDownloadSnapshot(
        status: MushafDownloadStatus.ready,
        packageId: manifest.packageId,
        completedPages: completedPages,
        totalPages: manifest.pages.length,
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

  Future<MushafDownloadSnapshot> estimate({
    int? width,
    int expectedPageCount = 604,
  }) async {
    final manifest = await _manifest(width, expectedPageCount);
    return MushafDownloadSnapshot(
      status: MushafDownloadStatus.notDownloaded,
      packageId: manifest.packageId,
      totalPages: manifest.pages.length,
      totalBytes: manifest.totalBytes,
    );
  }

  Future<OfflineMushafManifest> _manifest(
    int? width,
    int expectedPageCount,
  ) async {
    final payload = await _api.get(
      '${mushaf.apiPath}/offline-manifest',
      query: width == null ? null : <String, Object?>{'width': width},
      public: true,
    );
    final manifest = OfflineMushafManifest.fromJson(
      jsonMap(payload),
      expectedEdition: mushaf.code,
      localApiBase: _api.dio.options.extra['localDevelopment'] == true
          ? Uri.parse(_api.dio.options.baseUrl)
          : null,
    );
    if (manifest.pages.length != expectedPageCount) {
      throw const FormatException('The Mushaf package is not complete');
    }
    return manifest;
  }

  Future<void> _preparePackage(
    OfflineMushafManifest manifest,
    Directory packageDirectory,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.insert('offline_packages', <String, Object?>{
        'package_id': manifest.packageId,
        'package_type': 'mushaf_pages',
        'content_key': _mushafContentKey,
        'version': manifest.version,
        'width': manifest.width,
        'checksum_sha256': manifest.packageChecksum,
        'manifest': jsonEncode(manifest.raw),
        'status': 'downloading',
        'is_active': 0,
        'total_items': manifest.pages.length,
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
          'total_items': manifest.pages.length,
          'total_bytes': manifest.totalBytes,
          'last_error': null,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
      final items = transaction.batch();
      for (final page in manifest.pages) {
        final localPath = p.join(packageDirectory.path, page.fileName);
        enqueueOfflinePackageItem(
          items,
          packageId: manifest.packageId,
          itemKey: 'page:${page.number}',
          itemNumber: page.number,
          fileName: page.fileName,
          localPath: localPath,
          url: page.url.toString(),
          checksum: page.sha256,
          sizeBytes: page.bytes,
          metadata: jsonEncode(page.metadata),
          updatedAt: now,
        );
      }
      await items.commit(noResult: true);
    });
  }

  Future<void> _markPageReady(
    OfflineMushafManifest manifest,
    OfflineMushafPage page, {
    required int completedPages,
    required int completedBytes,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'offline_package_items',
        <String, Object?>{
          'status': 'ready',
          'downloaded_bytes': page.bytes,
          'updated_at': now,
        },
        where: 'package_id = ? AND item_key = ?',
        whereArgs: <Object?>[manifest.packageId, 'page:${page.number}'],
      );
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'completed_items': completedPages,
          'downloaded_bytes': completedBytes,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
    });
  }

  Future<void> _activate(OfflineMushafManifest manifest) async {
    final now = DateTime.now().toUtc();
    await _database.database.transaction((transaction) async {
      for (final page in manifest.pages) {
        await transaction.insert('cache_entries', <String, Object?>{
          'cache_key': mushaf.pageCacheKey(page.number),
          'payload': jsonEncode(page.metadata),
          'etag': null,
          'updated_at': now.toIso8601String(),
          'expires_at': now.add(const Duration(days: 3650)).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await transaction.update(
        'offline_packages',
        <String, Object?>{'is_active': 0},
        where: 'content_key = ?',
        whereArgs: <Object?>[_mushafContentKey],
      );
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'status': 'ready',
          'is_active': 1,
          'completed_items': manifest.pages.length,
          'downloaded_bytes': manifest.totalBytes,
          'last_error': null,
          'updated_at': now.toIso8601String(),
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

  MushafDownloadSnapshot _snapshotFromRow(Map<String, Object?> row) {
    final status = switch (row['status']) {
      'ready' => MushafDownloadStatus.ready,
      // A persisted download has no live worker after process restart. Expose
      // it as resumable instead of leaving the action disabled forever.
      'downloading' => MushafDownloadStatus.failed,
      'failed' => MushafDownloadStatus.failed,
      _ => MushafDownloadStatus.notDownloaded,
    };
    return MushafDownloadSnapshot(
      status: status,
      packageId: row['package_id'] as String?,
      completedPages: row['completed_items']! as int,
      totalPages: row['total_items']! as int,
      downloadedBytes: row['downloaded_bytes']! as int,
      totalBytes: row['total_bytes']! as int,
      error: row['last_error'] as String?,
    );
  }
}

Future<bool> verifyMushafAssetFile(File file, OfflineMushafPage page) async {
  if (!await file.exists() || await file.length() != page.bytes) return false;
  final header = await file
      .openRead(0, 12)
      .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
  if (header.length < 12 ||
      header[0] != 0x52 ||
      header[1] != 0x49 ||
      header[2] != 0x46 ||
      header[3] != 0x46 ||
      header[8] != 0x57 ||
      header[9] != 0x45 ||
      header[10] != 0x42 ||
      header[11] != 0x50) {
    return false;
  }
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == page.sha256;
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

Map<String, Object?> _metadataWithoutAssetUrl(Map<String, Object?> metadata) {
  final copied = jsonMap(jsonDecode(jsonEncode(metadata)));
  final assets = copied['assets'];
  if (assets is List) {
    copied['assets'] = assets
        .map((rawAsset) {
          final asset = jsonMap(rawAsset);
          asset.remove('url');
          return asset;
        })
        .toList(growable: false);
  }
  return copied;
}

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
