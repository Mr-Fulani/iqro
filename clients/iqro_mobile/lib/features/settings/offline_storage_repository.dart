import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/local_database.dart';
import '../../core/storage/offline_package_queries.dart';

const _mushafPackageType = 'mushaf_pages';
const _audioPackageType = 'surah_audio';
const _knownPackageTypes = <String>{_mushafPackageType, _audioPackageType};
final _safePackageId = RegExp(r'^[a-zA-Z0-9._-]+$');

typedef OfflineStorageDirectoryProvider = Future<Directory> Function();

class OfflinePackageSummary {
  const OfflinePackageSummary({
    required this.packageId,
    required this.packageType,
    required this.contentKey,
    required this.status,
    required this.active,
    required this.completedItems,
    required this.totalItems,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.usedBytes,
    required this.manifest,
  });

  final String packageId;
  final String packageType;
  final String contentKey;
  final String status;
  final bool active;
  final int completedItems;
  final int totalItems;
  final int downloadedBytes;
  final int totalBytes;
  final int usedBytes;
  final Map<String, Object?> manifest;

  bool get isMushaf => packageType == _mushafPackageType;
  bool get isAudio => packageType == _audioPackageType;
  bool get isDownloading => status == 'downloading';

  String? get quality => isAudio ? manifest['quality']?.toString() : null;

  String? reciterNameFor(String locale) {
    final raw = manifest['reciter'];
    if (raw is! Map) return null;
    final reciter = Map<String, Object?>.from(raw);
    final preferred = reciter['name_$locale']?.toString().trim() ?? '';
    if (preferred.isNotEmpty) return preferred;
    final english = reciter['name_en']?.toString().trim() ?? '';
    if (english.isNotEmpty) return english;
    final arabic = reciter['name_ar']?.toString().trim() ?? '';
    return arabic.isEmpty ? null : arabic;
  }
}

class OfflineStorageRepository {
  OfflineStorageRepository({
    required LocalDatabase database,
    OfflineStorageDirectoryProvider? supportDirectory,
  }) : _database = database,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final LocalDatabase _database;
  final OfflineStorageDirectoryProvider _supportDirectory;

  Future<List<OfflinePackageSummary>> packages() async {
    final rows = await _database.database.query(
      'offline_packages',
      columns: offlinePackageSummaryColumns,
      orderBy: 'is_active DESC, updated_at DESC, package_id ASC',
    );
    if (rows.isEmpty) return const <OfflinePackageSummary>[];
    final support = await _supportDirectory();
    final result = <OfflinePackageSummary>[];
    for (final row in rows) {
      final packageId = row['package_id']?.toString() ?? '';
      final packageType = row['package_type']?.toString() ?? '';
      final manifest = packageType == _audioPackageType
          ? await readOfflineAudioSummary(_database.database, packageId)
          : const <String, Object?>{};
      var usedBytes = 0;
      final directory = _packageDirectory(support, packageType, packageId);
      if (directory != null) usedBytes = await _directoryBytes(directory);
      result.add(
        OfflinePackageSummary(
          packageId: packageId,
          packageType: packageType,
          contentKey: row['content_key']?.toString() ?? '',
          status: row['status']?.toString() ?? 'failed',
          active: row['is_active'] == 1,
          completedItems: (row['completed_items'] as num?)?.toInt() ?? 0,
          totalItems: (row['total_items'] as num?)?.toInt() ?? 0,
          downloadedBytes: (row['downloaded_bytes'] as num?)?.toInt() ?? 0,
          totalBytes: (row['total_bytes'] as num?)?.toInt() ?? 0,
          usedBytes: usedBytes,
          manifest: manifest,
        ),
      );
    }
    return List<OfflinePackageSummary>.unmodifiable(result);
  }

  Future<void> deletePackage(String packageId) async {
    if (!_safePackageId.hasMatch(packageId)) {
      throw const FormatException('Offline package id is invalid');
    }
    final rows = await _database.database.query(
      'offline_packages',
      columns: const ['package_type', 'status'],
      where: 'package_id = ?',
      whereArgs: <Object?>[packageId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.single;
    final packageType = row['package_type']?.toString() ?? '';
    final previousStatus = row['status']?.toString() ?? 'failed';
    if (!_knownPackageTypes.contains(packageType)) {
      throw const FormatException('Offline package type is invalid');
    }
    if (previousStatus == 'downloading') {
      throw StateError('An active offline download cannot be deleted');
    }
    final support = await _supportDirectory();
    final directory = _packageDirectory(support, packageType, packageId);
    if (directory == null) {
      throw const FormatException('Offline package path is invalid');
    }
    final itemRows = await _database.database.query(
      'offline_package_items',
      columns: const <String>['local_path'],
      where: 'package_id = ?',
      whereArgs: <Object?>[packageId],
    );
    final expectedDirectory = p.normalize(directory.absolute.path);
    for (final item in itemRows) {
      final localPath = p.normalize(item['local_path']?.toString() ?? '');
      if (localPath.isEmpty ||
          !p.equals(p.dirname(p.absolute(localPath)), expectedDirectory)) {
        throw const FormatException('Offline package contains an unsafe path');
      }
    }

    final claimed = await _database.database.update(
      'offline_packages',
      <String, Object?>{
        'status': 'deleting',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'package_id = ? AND status = ?',
      whereArgs: <Object?>[packageId, previousStatus],
    );
    if (claimed != 1) {
      throw StateError('Offline package changed before deletion');
    }
    try {
      await _deleteDirectoryContents(directory);
      await _database.database.transaction((transaction) async {
        await transaction.delete(
          'offline_package_items',
          where: 'package_id = ?',
          whereArgs: <Object?>[packageId],
        );
        await transaction.delete(
          'offline_packages',
          where: 'package_id = ?',
          whereArgs: <Object?>[packageId],
        );
      });
    } on Object {
      await _database.database.update(
        'offline_packages',
        <String, Object?>{
          'status': previousStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'package_id = ? AND status = ?',
        whereArgs: <Object?>[packageId, 'deleting'],
      );
      rethrow;
    }
  }

  Directory? _packageDirectory(
    Directory support,
    String packageType,
    String packageId,
  ) {
    if (!_safePackageId.hasMatch(packageId) ||
        !_knownPackageTypes.contains(packageType)) {
      return null;
    }
    final category = packageType == _mushafPackageType ? 'mushaf' : 'audio';
    final root = p.normalize(
      p.absolute(p.join(support.path, 'offline_packages')),
    );
    final path = p.normalize(p.absolute(p.join(root, category, packageId)));
    if (!p.isWithin(root, path)) return null;
    return Directory(path);
  }
}

Future<int> _directoryBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var total = 0;
  await for (final entity in directory.list(followLinks: false)) {
    if (await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.file) {
      total += await File(entity.path).length();
    }
  }
  return total;
}

Future<void> _deleteDirectoryContents(Directory directory) async {
  if (!await directory.exists()) return;
  final entities = await directory.list(followLinks: false).toList();
  if (entities.any((entity) => entity is Directory)) {
    throw const FileSystemException(
      'Offline package contains an unexpected directory',
    );
  }
  for (final entity in entities) {
    await entity.delete();
  }
  await directory.delete();
}
