import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/quran/quran_models.dart';
import '../utils/json_helpers.dart';
import 'local_database.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();

const mushafPagesDirectory = 'mushaf_pages';
const foundationAssetsDirectory = 'foundation_assets';

/// Location of a streamed Mushaf page image below [mushafPagesDirectory].
String mushafPageCachePath(
  String code,
  MushafPageData page,
  MushafAsset asset,
) {
  final checksum = asset.sha256.isNotEmpty ? asset.sha256 : page.checksumSha256;
  final safeVersion = page.contentVersion.replaceAll(
    RegExp('[^a-zA-Z0-9._-]'),
    '_',
  );
  final checksumPrefix = checksum.length >= 16
      ? checksum.substring(0, 16)
      : 'unversioned';
  return p.join(
    code,
    safeVersion,
    'page-${page.number.toString().padLeft(3, '0')}'
    '-w${asset.width}-$checksumPrefix.webp',
  );
}

/// Records a cache hit for least-recently-used eviction. Mobile file systems
/// do not keep reliable access times, so the modification time stands in for
/// it and is refreshed at most daily. Returns whether the stamp changed.
Future<bool> touchCachedFile(File file) async {
  try {
    final now = DateTime.now();
    if (now.difference(await file.lastModified()) < const Duration(days: 1)) {
      return false;
    }
    await file.setLastModified(now);
    return true;
  } on FileSystemException {
    return false;
  }
}

class CacheMaintenanceReport {
  const CacheMaintenanceReport({
    required this.deletedEntries,
    required this.deletedFiles,
    required this.freedBytes,
    required this.remainingBytes,
  });

  final int deletedEntries;
  final int deletedFiles;
  final int freedBytes;
  final int remainingBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'deleted_entries': deletedEntries,
    'deleted_files': deletedFiles,
    'freed_bytes': freedBytes,
    'remaining_bytes': remainingBytes,
  };
}

/// Bounds the streamed caches that reading online Mushafs leaves behind.
///
/// Expired JSON stays usable as an offline fallback, so it is only removed
/// long after expiry. Offline packages are explicit user downloads: their
/// files and the cache entries they rely on are never touched here.
class CacheMaintenance {
  CacheMaintenance({
    required LocalDatabase database,
    CacheDirectoryProvider? supportDirectory,
    DateTime Function()? clock,
    this.fileCacheLimitBytes = 200 * 1024 * 1024,
    this.expiredRetention = const Duration(days: 60),
    this.minimumInterval = const Duration(hours: 20),
    this.inFlightGrace = const Duration(hours: 1),
  }) : _database = database,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _clock = clock ?? DateTime.now;

  static const stateKey = 'cache_maintenance_v1';
  static const _pageBatch = 128;
  static const _deleteBatch = 200;

  final LocalDatabase _database;
  final CacheDirectoryProvider _supportDirectory;
  final DateTime Function() _clock;
  final int fileCacheLimitBytes;
  final Duration expiredRetention;
  final Duration minimumInterval;

  /// Files written or used this recently may belong to a request in flight.
  final Duration inFlightGrace;

  /// Returns null when the previous run is recent enough.
  Future<CacheMaintenanceReport?> run({bool force = false}) async {
    final now = _clock().toUtc();
    if (!force && !await _isDue(now)) return null;
    final db = _database.database;
    // Built here rather than in a migration so that a large existing cache
    // never delays opening the database on a cold start.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS cache_entries_expires_idx '
      'ON cache_entries(expires_at)',
    );
    final protectedPrefixes = await _protectedKeyPrefixes();
    var deletedEntries = await _deleteExpiredEntries(now, protectedPrefixes);
    final activeVersions = await _activeFoundationVersions();
    deletedEntries += await _deleteRetiredFoundationPages(
      activeVersions,
      protectedPrefixes,
    );
    final support = await _supportDirectory();
    final assetsRoot = p.normalize(
      p.join(support.path, foundationAssetsDirectory),
    );
    final pagesRoot = p.normalize(p.join(support.path, mushafPagesDirectory));
    final assets = await _foundationAssets(assetsRoot, activeVersions);
    deletedEntries += assets.deleted;
    final referenced = <String>{
      ...assets.referenced,
      ...await _mushafPageReferences(pagesRoot),
    };
    final sweep = await _sweepInIsolate(
      CacheSweepRequest(
        roots: <String>[pagesRoot, assetsRoot],
        referenced: referenced,
        protectedPaths: await _offlinePackagePaths(),
        limitBytes: fileCacheLimitBytes,
        now: now,
        grace: inFlightGrace,
      ),
    );
    final report = CacheMaintenanceReport(
      deletedEntries: deletedEntries,
      deletedFiles: sweep.deletedFiles,
      freedBytes: sweep.freedBytes,
      remainingBytes: sweep.remainingBytes,
    );
    await _database.writeDeviceState(stateKey, <String, Object?>{
      'last_run_at': now.toIso8601String(),
      ...report.toJson(),
    });
    return report;
  }

  Future<bool> _isDue(DateTime now) async {
    final state = await _database.readDeviceState(stateKey);
    final last = DateTime.tryParse(state?['last_run_at']?.toString() ?? '');
    return last == null ||
        last.isAfter(now) ||
        now.difference(last) >= minimumInterval;
  }

  Future<Set<String>> _protectedKeyPrefixes() async {
    final rows = await _database.database.query(
      'offline_packages',
      columns: const <String>['package_type', 'content_key'],
    );
    // The catalog authorizes a downloaded edition on a cold offline start.
    final prefixes = <String>{'mushaf-renditions:'};
    for (final row in rows) {
      final contentKey = row['content_key']?.toString() ?? '';
      if (contentKey.isEmpty) continue;
      switch (row['package_type']) {
        case 'mushaf_pages':
          prefixes.add('$contentKey:page:');
        case 'surah_audio' when contentKey.startsWith('recitation:'):
          prefixes
            ..add('audio:reciters:')
            ..add('audio:recitations:')
            ..add('audio:playback:${contentKey.substring(11)}:');
        // The course document stays readable offline with its pictures.
        case 'salah_course' when contentKey.startsWith('salah:'):
          prefixes.add('$contentKey:');
      }
    }
    return prefixes;
  }

  Future<int> _deleteExpiredEntries(
    DateTime now,
    Set<String> protectedPrefixes,
  ) async {
    final cutoff = now.subtract(expiredRetention).toIso8601String();
    final rows = await _database.database.query(
      'cache_entries',
      columns: const <String>['cache_key'],
      where: 'expires_at < ?',
      whereArgs: <Object?>[cutoff],
    );
    final keys = rows
        .map((row) => row['cache_key']! as String)
        .where((key) => !_isProtected(key, protectedPrefixes))
        .toList(growable: false);
    var deleted = 0;
    for (var start = 0; start < keys.length; start += _deleteBatch) {
      final chunk = keys.sublist(
        start,
        (start + _deleteBatch).clamp(0, keys.length),
      );
      // Re-checked in the statement: the entry may have been refreshed since.
      deleted += await _database.database.delete(
        'cache_entries',
        where:
            'cache_key IN (${List.filled(chunk.length, '?').join(',')}) '
            'AND expires_at < ?',
        whereArgs: <Object?>[...chunk, cutoff],
      );
    }
    return deleted;
  }

  Future<Set<String>> _activeFoundationVersions() async {
    final rows = await _database.database.query(
      'cache_entries',
      columns: const <String>['payload'],
      where: 'cache_key >= ? AND cache_key < ?',
      whereArgs: const <Object?>['mushaf-renditions:', 'mushaf-renditions;'],
    );
    final versions = <String>{};
    for (final row in rows) {
      try {
        final catalog = jsonDecode(row['payload']! as String);
        if (catalog is! List) continue;
        for (final item in catalog.whereType<Map>()) {
          final checksum = item['source_checksum_sha256'];
          if (item.containsKey('source_id') &&
              checksum is String &&
              _sha256.hasMatch(checksum)) {
            versions.add(checksum);
          }
        }
      } on FormatException {
        // A damaged catalog proves nothing about which versions are current.
      }
    }
    return versions;
  }

  /// Foundation page and page-index keys name their edition version.
  Future<int> _deleteRetiredFoundationPages(
    Set<String> activeVersions,
    Set<String> protectedPrefixes,
  ) async {
    if (activeVersions.isEmpty) return 0;
    final rows = await _database.database.query(
      'cache_entries',
      columns: const <String>['cache_key'],
      where: 'cache_key >= ? AND cache_key < ?',
      whereArgs: const <Object?>[
        'mushaf-rendition:qf-',
        'mushaf-rendition:qf.',
      ],
    );
    final keys = <String>[];
    for (final row in rows) {
      final key = row['cache_key']! as String;
      final version = _foundationKeyVersion.firstMatch(key)?.group(1);
      if (version != null &&
          !activeVersions.contains(version) &&
          !_isProtected(key, protectedPrefixes)) {
        keys.add(key);
      }
    }
    var deleted = 0;
    for (var start = 0; start < keys.length; start += _deleteBatch) {
      final chunk = keys.sublist(
        start,
        (start + _deleteBatch).clamp(0, keys.length),
      );
      deleted += await _database.database.delete(
        'cache_entries',
        where: 'cache_key IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
    }
    return deleted;
  }

  Future<({int deleted, Set<String> referenced})> _foundationAssets(
    String root,
    Set<String> activeVersions,
  ) async {
    final rows = await _database.database.query(
      'cache_entries',
      columns: const <String>['cache_key', 'payload', 'updated_at'],
      where: 'cache_key >= ? AND cache_key < ?',
      whereArgs: const <Object?>['foundation-asset:', 'foundation-asset;'],
    );
    final scan = await _scanFoundationAssetsInIsolate(
      root,
      activeVersions,
      <(String, String, String)>[
        for (final row in rows)
          (
            row['cache_key']! as String,
            row['payload']! as String,
            row['updated_at']! as String,
          ),
      ],
    );
    if (scan.retired.isEmpty) return (deleted: 0, referenced: scan.referenced);
    final batch = _database.database.batch();
    for (final (key, updatedAt) in scan.retired) {
      // An asset re-downloaded for the active version meanwhile is kept.
      batch.delete(
        'cache_entries',
        where: 'cache_key = ? AND updated_at = ?',
        whereArgs: <Object?>[key, updatedAt],
      );
    }
    final results = await batch.commit();
    return (
      deleted: results.whereType<int>().fold<int>(0, (sum, n) => sum + n),
      referenced: scan.referenced,
    );
  }

  Future<Set<String>> _mushafPageReferences(String root) async {
    final references = <String>{};
    var after = 'mushaf-rendition:';
    while (true) {
      final rows = await _database.database.query(
        'cache_entries',
        columns: const <String>['cache_key', 'payload'],
        where:
            'cache_key > ? AND cache_key < ? AND cache_key LIKE ? '
            'AND cache_key NOT LIKE ?',
        whereArgs: <Object?>[
          after,
          'mushaf-rendition;',
          'mushaf-rendition:%:page:%',
          'mushaf-rendition:qf-%',
        ],
        orderBy: 'cache_key',
        limit: _pageBatch,
      );
      if (rows.isEmpty) break;
      after = rows.last['cache_key']! as String;
      references.addAll(
        await _pageReferencesInIsolate(root, <(String, String)>[
          for (final row in rows)
            (row['cache_key']! as String, row['payload']! as String),
        ]),
      );
      if (rows.length < _pageBatch) break;
    }
    return references;
  }

  Future<Set<String>> _offlinePackagePaths() async {
    final rows = await _database.database.query(
      'offline_package_items',
      columns: const <String>['local_path'],
    );
    return <String>{
      for (final row in rows)
        if ((row['local_path']?.toString() ?? '').isNotEmpty)
          p.normalize(row['local_path']! as String),
    };
  }
}

bool _isProtected(String key, Set<String> prefixes) =>
    prefixes.any(key.startsWith);

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _foundationKeyVersion = RegExp(
  r'^mushaf-rendition:qf-\d+:(?:page:\d+|page-index):([0-9a-f]{64})(?::|$)',
);
final _rasterPageKey = RegExp(r'^mushaf-rendition:([a-z0-9-]+):page:\d+$');

// Top-level so the isolate closures capture only their sendable arguments.
Future<CacheSweepResult> _sweepInIsolate(CacheSweepRequest request) =>
    Isolate.run(() => sweepCacheFiles(request));

Future<Set<String>> _pageReferencesInIsolate(
  String root,
  List<(String, String)> rows,
) => Isolate.run(() => _pageReferences(root, rows));

Future<({List<(String, String)> retired, Set<String> referenced})>
_scanFoundationAssetsInIsolate(
  String root,
  Set<String> activeVersions,
  List<(String, String, String)> rows,
) => Isolate.run(() => _foundationAssetScan(root, activeVersions, rows));

Set<String> _pageReferences(String root, List<(String, String)> rows) {
  final references = <String>{};
  for (final (key, payload) in rows) {
    final code = _rasterPageKey.firstMatch(key)?.group(1);
    if (code == null) continue;
    try {
      final page = MushafPageData.fromJson(jsonMap(jsonDecode(payload)));
      for (final asset in page.assets) {
        references.add(
          p.normalize(p.join(root, mushafPageCachePath(code, page, asset))),
        );
      }
    } on Object {
      // Unreadable metadata cannot keep a file alive.
    }
  }
  return references;
}

({List<(String, String)> retired, Set<String> referenced}) _foundationAssetScan(
  String root,
  Set<String> activeVersions,
  List<(String, String, String)> rows,
) {
  final retired = <(String, String)>[];
  final referenced = <String>{};
  for (final (key, payload, updatedAt) in rows) {
    try {
      final value = jsonMap(jsonDecode(payload));
      final version = value['content_version'];
      if (version is String &&
          activeVersions.isNotEmpty &&
          !activeVersions.contains(version)) {
        retired.add((key, updatedAt));
        continue;
      }
      // Matched by file name: the absolute container path can change across
      // app updates on iOS while the checksum-named file stays the same.
      final path = value['path'];
      if (path is String && path.isNotEmpty) {
        referenced.add(p.normalize(p.join(root, p.basename(path))));
      }
    } on Object {
      // Unreadable metadata cannot keep a file alive.
    }
  }
  return (retired: retired, referenced: referenced);
}

@immutable
class CacheSweepRequest {
  const CacheSweepRequest({
    required this.roots,
    required this.referenced,
    required this.protectedPaths,
    required this.limitBytes,
    required this.now,
    required this.grace,
  });

  final List<String> roots;
  final Set<String> referenced;
  final Set<String> protectedPaths;
  final int limitBytes;
  final DateTime now;
  final Duration grace;
}

@immutable
class CacheSweepResult {
  const CacheSweepResult({
    required this.deletedFiles,
    required this.freedBytes,
    required this.remainingBytes,
  });

  final int deletedFiles;
  final int freedBytes;
  final int remainingBytes;
}

/// Deletes files no cache entry references, then the least recently used
/// ones until the rest fits [CacheSweepRequest.limitBytes]. Synchronous I/O:
/// meant to run on a background isolate.
@visibleForTesting
CacheSweepResult sweepCacheFiles(CacheSweepRequest request) {
  final files = <({String path, int size, DateTime used})>[];
  final directories = <({String path, DateTime modified})>[];
  for (final rootPath in request.roots) {
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        try {
          directories.add((
            path: entity.path,
            modified: entity.statSync().modified,
          ));
        } on FileSystemException {
          // Skipped: a directory that vanished needs no cleanup.
        }
        continue;
      }
      if (entity is! File) continue;
      final path = p.normalize(entity.path);
      if (request.protectedPaths.contains(path)) continue;
      try {
        final stat = entity.statSync();
        files.add((path: path, size: stat.size, used: stat.modified));
      } on FileSystemException {
        continue;
      }
    }
  }

  final recentSince = request.now.subtract(request.grace);
  final evicted = <({String path, int size, DateTime used})>[];
  final kept = <({String path, int size, DateTime used})>[];
  for (final file in files) {
    if (!file.used.isAfter(recentSince) &&
        !request.referenced.contains(file.path)) {
      evicted.add(file);
    } else {
      kept.add(file);
    }
  }
  var keptBytes = kept.fold<int>(0, (sum, file) => sum + file.size);
  if (keptBytes > request.limitBytes) {
    final leastRecent =
        kept.where((file) => !file.used.isAfter(recentSince)).toList()
          ..sort((a, b) => a.used.compareTo(b.used));
    for (final file in leastRecent) {
      if (keptBytes <= request.limitBytes) break;
      evicted.add(file);
      keptBytes -= file.size;
    }
  }

  var deletedFiles = 0;
  var freedBytes = 0;
  for (final file in evicted) {
    try {
      File(file.path).deleteSync();
      deletedFiles += 1;
      freedBytes += file.size;
    } on FileSystemException {
      continue;
    }
  }
  // Deepest first, so emptied version directories go before their parents.
  // A fresh empty directory may be waiting for a download in flight; the
  // stamp is read before this sweep's own deletions changed it.
  directories.sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final entry in directories) {
    final directory = Directory(entry.path);
    try {
      if (!entry.modified.isAfter(recentSince) &&
          directory.listSync().isEmpty) {
        directory.deleteSync();
      }
    } on FileSystemException {
      continue;
    }
  }
  final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);
  return CacheSweepResult(
    deletedFiles: deletedFiles,
    freedBytes: freedBytes,
    remainingBytes: totalBytes - freedBytes,
  );
}
