import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/network/api_client.dart';
import '../../core/network/public_asset_uri.dart';
import '../../core/platform/backup_exclusion.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/offline_package_items.dart';
import '../../core/storage/offline_package_queries.dart';
import '../../core/storage/offline_storage_quota.dart';
import '../../core/utils/json_helpers.dart';
import '../settings/offline_storage_repository.dart';

const salahCoursePackageType = 'salah_course';
const _approvedSalahAssetHosts = <String>{'media.iqro.forum'};
const _maxImageBytes = 4 * 1024 * 1024;
final _safeId = RegExp(r'^[a-zA-Z0-9._-]+$');
final _safeImageName = RegExp(r'^[a-zA-Z0-9._-]+\.webp$');

enum SalahOfflineStatus { notDownloaded, downloading, ready, outdated, failed }

class SalahOfflineSnapshot {
  const SalahOfflineSnapshot({
    required this.status,
    this.packageId,
    this.version,
    this.checksum,
    this.completedItems = 0,
    this.totalItems = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  const SalahOfflineSnapshot.empty()
    : this(status: SalahOfflineStatus.notDownloaded);

  final SalahOfflineStatus status;
  final String? packageId;

  /// Course version and package checksum of the stored pictures.
  final String? version;
  final String? checksum;
  final int completedItems;
  final int totalItems;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  double get progress => totalBytes <= 0
      ? 0
      : (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
}

class OfflineSalahImage {
  const OfflineSalahImage({
    required this.key,
    required this.url,
    required this.fileName,
    required this.bytes,
    required this.sha256,
  });

  final String key;
  final Uri url;
  final String fileName;
  final int bytes;
  final String sha256;
}

/// The pictures of one course in one language
/// (`GET /salah/courses/<slug>/offline-manifest`).
class OfflineSalahManifest {
  const OfflineSalahManifest({
    required this.slug,
    required this.language,
    required this.version,
    required this.packageChecksum,
    required this.sourceChecksum,
    required this.totalBytes,
    required this.images,
    required this.raw,
  });

  factory OfflineSalahManifest.fromJson(
    Map<String, Object?> json, {
    required String slug,
    required String language,
    Uri? localApiBase,
  }) {
    final rawItems = json['items'];
    final version = json['version']?.toString() ?? '';
    final packageChecksum = json['package_checksum_sha256']?.toString() ?? '';
    final sourceChecksum = json['source_checksum_sha256']?.toString() ?? '';
    final totalBytes = (json['total_bytes'] as num?)?.toInt() ?? 0;
    if (json['schema_version'] != 1 ||
        json['package_type'] != salahCoursePackageType ||
        json['package_id'] != '$slug:$language' ||
        !_safeId.hasMatch(salahPackageId(slug, language)) ||
        version.isEmpty ||
        !_isSha256(packageChecksum) ||
        !_isSha256(sourceChecksum) ||
        rawItems is! List ||
        rawItems.isEmpty) {
      throw const FormatException('Offline salah manifest is invalid');
    }
    final images = rawItems
        .whereType<Map>()
        .map(
          (item) => _parseImage(Map<String, Object?>.from(item), localApiBase),
        )
        .toList(growable: false);
    if (images.length != rawItems.length ||
        images.map((image) => image.key).toSet().length != images.length ||
        images.map((image) => image.fileName).toSet().length != images.length ||
        totalBytes != images.fold<int>(0, (sum, image) => sum + image.bytes)) {
      throw const FormatException('Offline salah coverage is incomplete');
    }
    final manifest = OfflineSalahManifest(
      slug: slug,
      language: language,
      version: version,
      packageChecksum: packageChecksum,
      sourceChecksum: sourceChecksum,
      totalBytes: totalBytes,
      images: images,
      raw: json,
    );
    if (manifest.computedChecksum != packageChecksum) {
      throw const FormatException('Offline salah manifest checksum failed');
    }
    return manifest;
  }

  final String slug;
  final String language;
  final String version;
  final String packageChecksum;
  final String sourceChecksum;
  final int totalBytes;
  final List<OfflineSalahImage> images;
  final Map<String, Object?> raw;

  String get packageId => salahPackageId(slug, language);

  /// The server digest leaves the URLs out, so a CDN move keeps it.
  String get computedChecksum {
    final payload = <String, Object?>{
      'schema_version': 1,
      'package_type': salahCoursePackageType,
      'package_id': '$slug:$language',
      'version': version,
      'source_checksum_sha256': sourceChecksum,
      'items': images
          .map(
            (image) => <String, Object?>{
              'key': image.key,
              'sha256': image.sha256,
              'bytes': image.bytes,
            },
          )
          .toList(growable: false),
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalJson(payload))))
        .toString();
  }

  static OfflineSalahImage _parseImage(
    Map<String, Object?> json,
    Uri? localApiBase,
  ) {
    final key = json['key']?.toString() ?? '';
    final asset = jsonMap(json['asset']);
    final rawUrl = asset['url']?.toString() ?? '';
    final url = localApiBase == null
        ? Uri.tryParse(rawUrl)
        : localApiBase.resolve(rawUrl);
    final fileName = asset['file_name']?.toString() ?? '';
    final bytes = (asset['bytes'] as num?)?.toInt() ?? 0;
    final checksum = asset['sha256']?.toString() ?? '';
    if (key.isEmpty ||
        url == null ||
        !isApprovedPublicAssetUri(
          url,
          allowedHosts: _approvedSalahAssetHosts,
          localApiBase: localApiBase,
        ) ||
        !url.path.toLowerCase().endsWith('.webp') ||
        !_safeImageName.hasMatch(fileName) ||
        url.pathSegments.lastOrNull != fileName ||
        asset['content_type'] != 'image/webp' ||
        bytes <= 0 ||
        bytes > _maxImageBytes ||
        !_isSha256(checksum)) {
      throw const FormatException('Offline salah image is invalid');
    }
    return OfflineSalahImage(
      key: key,
      url: url,
      fileName: fileName,
      bytes: bytes,
      sha256: checksum,
    );
  }
}

abstract interface class SalahOfflineGateway {
  /// Set in local development, where media is served by the API itself.
  Uri? get localApiBase;

  Future<Object?> manifest(String slug, String language);

  Future<void> download(
    Uri url,
    File destination, {
    required int expectedBytes,
    void Function(int received, int total)? onProgress,
  });
}

class ApiSalahOfflineGateway implements SalahOfflineGateway {
  ApiSalahOfflineGateway(this._api);

  final ApiClient _api;

  @override
  Uri? get localApiBase => _api.dio.options.extra['localDevelopment'] == true
      ? Uri.parse(_api.dio.options.baseUrl)
      : null;

  @override
  Future<Object?> manifest(String slug, String language) => _api.get(
    '/salah/courses/${Uri.encodeComponent(slug)}/offline-manifest',
    query: <String, Object?>{'language': language},
    public: true,
  );

  @override
  Future<void> download(
    Uri url,
    File destination, {
    required int expectedBytes,
    void Function(int received, int total)? onProgress,
  }) => _api.downloadPublicFile(
    url,
    destination,
    allowedHosts: _approvedSalahAssetHosts,
    expectedBytes: expectedBytes,
    maxBytes: _maxImageBytes,
    onProgress: onProgress,
  );
}

typedef SalahOfflineDirectoryProvider = Future<Directory> Function();

/// Course pictures as an offline package; the audio stays streamed.
///
/// One package per course and language keeps its id across versions: an
/// update downloads only the changed pictures into the same directory and
/// removes the ones the new version no longer uses. Pictures are found by
/// their SHA-256, so a step shows its file whatever version stored it.
class SalahOfflineRepository {
  SalahOfflineRepository({
    required SalahOfflineGateway gateway,
    required LocalDatabase database,
    SalahOfflineDirectoryProvider? supportDirectory,
  }) : _gateway = gateway,
       _database = database,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final SalahOfflineGateway _gateway;
  final LocalDatabase _database;
  final SalahOfflineDirectoryProvider _supportDirectory;

  /// The stored state, without a network request.
  Future<SalahOfflineSnapshot> snapshot(String slug, String language) async {
    final rows = await _database.database.query(
      'offline_packages',
      columns: <String>[
        ...offlinePackageSummaryColumns,
        'version',
        'checksum_sha256',
      ],
      where: 'package_id = ?',
      whereArgs: <Object?>[salahPackageId(slug, language)],
      limit: 1,
    );
    if (rows.isEmpty) return const SalahOfflineSnapshot.empty();
    final row = rows.single;
    return SalahOfflineSnapshot(
      status: switch (row['status']) {
        'ready' => SalahOfflineStatus.ready,
        // A persisted download has no live worker after a restart.
        'downloading' => SalahOfflineStatus.failed,
        'failed' => SalahOfflineStatus.failed,
        _ => SalahOfflineStatus.notDownloaded,
      },
      packageId: row['package_id'] as String?,
      version: row['version'] as String?,
      checksum: row['checksum_sha256'] as String?,
      completedItems: row['completed_items']! as int,
      totalItems: row['total_items']! as int,
      downloadedBytes: row['downloaded_bytes']! as int,
      totalBytes: row['total_bytes']! as int,
      error: row['last_error'] as String?,
    );
  }

  /// The stored state against the published manifest: a stored package of
  /// another version or checksum is [SalahOfflineStatus.outdated], and the
  /// sizes are those of the current pictures.
  Future<SalahOfflineSnapshot> check(String slug, String language) async {
    final manifest = await _manifest(slug, language);
    final stored = await snapshot(slug, language);
    final changed =
        stored.version != manifest.version ||
        stored.checksum != manifest.packageChecksum;
    return SalahOfflineSnapshot(
      status: stored.status == SalahOfflineStatus.ready && changed
          ? SalahOfflineStatus.outdated
          : stored.status,
      packageId: manifest.packageId,
      version: stored.version,
      checksum: stored.checksum,
      completedItems: changed ? 0 : stored.completedItems,
      totalItems: manifest.images.length,
      downloadedBytes: changed ? 0 : stored.downloadedBytes,
      totalBytes: manifest.totalBytes,
      error: stored.error,
    );
  }

  Future<SalahOfflineSnapshot> install(
    String slug,
    String language, {
    void Function(SalahOfflineSnapshot progress)? onProgress,
  }) async {
    final manifest = await _manifest(slug, language);
    await ensureOfflineStorageCapacity(
      _database,
      packageId: manifest.packageId,
      packageBytes: manifest.totalBytes,
    );
    final support = await _supportDirectory();
    final packageDirectory = Directory(
      p.join(support.path, 'offline_packages', 'salah', manifest.packageId),
    );
    await packageDirectory.create(recursive: true);
    await BackupExclusion.exclude(
      Directory(p.join(support.path, 'offline_packages')),
    );
    await _preparePackage(manifest, packageDirectory);

    SalahOfflineSnapshot progress(int completed, int bytes) =>
        SalahOfflineSnapshot(
          status: SalahOfflineStatus.downloading,
          packageId: manifest.packageId,
          version: manifest.version,
          checksum: manifest.packageChecksum,
          completedItems: completed,
          totalItems: manifest.images.length,
          downloadedBytes: bytes,
          totalBytes: manifest.totalBytes,
        );

    var completedItems = 0;
    var completedBytes = 0;
    try {
      for (final image in manifest.images) {
        final destination = File(p.join(packageDirectory.path, image.fileName));
        if (!await verifySalahImageFile(destination, image)) {
          final partial = File('${destination.path}.part');
          await _gateway.download(
            image.url,
            partial,
            expectedBytes: image.bytes,
            onProgress: (received, total) => onProgress?.call(
              progress(completedItems, completedBytes + received),
            ),
          );
          if (!await verifySalahImageFile(partial, image)) {
            await partial.writeAsBytes(const <int>[], flush: true);
            throw const FormatException(
              'Downloaded salah image failed its integrity check',
            );
          }
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
        }
        completedItems += 1;
        completedBytes += image.bytes;
        await _markImageReady(
          manifest,
          image,
          completedItems: completedItems,
          completedBytes: completedBytes,
        );
        onProgress?.call(progress(completedItems, completedBytes));
      }
      await _activate(manifest);
      await _removeUnusedFiles(manifest, packageDirectory);
      final ready = SalahOfflineSnapshot(
        status: SalahOfflineStatus.ready,
        packageId: manifest.packageId,
        version: manifest.version,
        checksum: manifest.packageChecksum,
        completedItems: completedItems,
        totalItems: manifest.images.length,
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

  /// Removes the pictures with the same checks as the storage screen.
  Future<void> delete(String slug, String language) => OfflineStorageRepository(
    database: _database,
    supportDirectory: _supportDirectory,
  ).deletePackage(salahPackageId(slug, language));

  /// Verified local pictures of the course by SHA-256. A picture whose file
  /// is gone or has another size is left out and loads from the network.
  Future<Map<String, String>> localImages(String slug, String language) async {
    final rows = await _database.database.rawQuery(
      '''
      SELECT item.local_path, item.size_bytes, item.checksum_sha256
      FROM offline_package_items AS item
      INNER JOIN offline_packages AS package
        ON package.package_id = item.package_id
      WHERE package.package_id = ?
        AND package.package_type = ?
        AND item.status = 'ready'
      ''',
      <Object?>[salahPackageId(slug, language), salahCoursePackageType],
    );
    final images = <String, String>{};
    for (final row in rows) {
      final file = File(row['local_path']! as String);
      if (await file.exists() && await file.length() == row['size_bytes']) {
        images[row['checksum_sha256']! as String] = file.path;
      }
    }
    return images;
  }

  Future<OfflineSalahManifest> _manifest(String slug, String language) async {
    final payload = await _gateway.manifest(slug, language);
    return OfflineSalahManifest.fromJson(
      jsonMap(payload),
      slug: slug,
      language: language,
      localApiBase: _gateway.localApiBase,
    );
  }

  Future<void> _preparePackage(
    OfflineSalahManifest manifest,
    Directory packageDirectory,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.insert('offline_packages', <String, Object?>{
        'package_id': manifest.packageId,
        'package_type': salahCoursePackageType,
        'content_key': salahContentKey(manifest.slug, manifest.language),
        'version': manifest.version,
        'width': null,
        'checksum_sha256': manifest.packageChecksum,
        'manifest': jsonEncode(manifest.raw),
        'status': 'downloading',
        'is_active': 0,
        'total_items': manifest.images.length,
        'completed_items': 0,
        'total_bytes': manifest.totalBytes,
        'downloaded_bytes': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // The id stays across versions, so the row takes the new one now; the
      // pictures it shares with the old version stay ready.
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'version': manifest.version,
          'checksum_sha256': manifest.packageChecksum,
          'manifest': jsonEncode(manifest.raw),
          'status': 'downloading',
          'total_items': manifest.images.length,
          'total_bytes': manifest.totalBytes,
          'last_error': null,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
      final keys = <String>[
        for (final image in manifest.images) _itemKey(image),
      ];
      await transaction.delete(
        'offline_package_items',
        where:
            'package_id = ? AND item_key NOT IN '
            '(${List.filled(keys.length, '?').join(',')})',
        whereArgs: <Object?>[manifest.packageId, ...keys],
      );
      final items = transaction.batch();
      for (final (index, image) in manifest.images.indexed) {
        enqueueOfflinePackageItem(
          items,
          packageId: manifest.packageId,
          itemKey: _itemKey(image),
          itemNumber: index + 1,
          fileName: image.fileName,
          localPath: p.join(packageDirectory.path, image.fileName),
          url: image.url.toString(),
          checksum: image.sha256,
          sizeBytes: image.bytes,
          metadata: jsonEncode(<String, Object?>{'key': image.key}),
          updatedAt: now,
        );
      }
      await items.commit(noResult: true);
    });
  }

  Future<void> _markImageReady(
    OfflineSalahManifest manifest,
    OfflineSalahImage image, {
    required int completedItems,
    required int completedBytes,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'offline_package_items',
        <String, Object?>{
          'status': 'ready',
          'downloaded_bytes': image.bytes,
          'updated_at': now,
        },
        where: 'package_id = ? AND item_key = ?',
        whereArgs: <Object?>[manifest.packageId, _itemKey(image)],
      );
      await transaction.update(
        'offline_packages',
        <String, Object?>{
          'completed_items': completedItems,
          'downloaded_bytes': completedBytes,
          'updated_at': now,
        },
        where: 'package_id = ?',
        whereArgs: <Object?>[manifest.packageId],
      );
    });
  }

  Future<void> _activate(OfflineSalahManifest manifest) async {
    await _database.database.update(
      'offline_packages',
      <String, Object?>{
        'status': 'ready',
        'is_active': 1,
        'completed_items': manifest.images.length,
        'downloaded_bytes': manifest.totalBytes,
        'last_error': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'package_id = ?',
      whereArgs: <Object?>[manifest.packageId],
    );
  }

  /// Pictures of an earlier version and abandoned partial files.
  Future<void> _removeUnusedFiles(
    OfflineSalahManifest manifest,
    Directory packageDirectory,
  ) async {
    final used = <String>{for (final image in manifest.images) image.fileName};
    await for (final entity in packageDirectory.list(followLinks: false)) {
      if (entity is File && !used.contains(p.basename(entity.path))) {
        await entity.delete();
      }
    }
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
}

/// The server names the package `<slug>:<language>`; the local id must be a
/// safe directory name.
String salahPackageId(String slug, String language) => 'salah-$slug-$language';

/// Shares the prefix of the course document cache keys, which cache
/// maintenance keeps while the pictures are stored.
String salahContentKey(String slug, String language) => 'salah:$slug:$language';

Future<bool> verifySalahImageFile(File file, OfflineSalahImage image) async {
  if (!await file.exists() || await file.length() != image.bytes) return false;
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
  return digest.toString() == image.sha256;
}

String _itemKey(OfflineSalahImage image) => 'image:${image.key}';
bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

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
