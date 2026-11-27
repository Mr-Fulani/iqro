import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Offline packages live in `offline_packages/<category>/<package id>/` inside
/// the app's support folder. The database keeps each file's path relative to
/// that folder: on iOS the folder's absolute path can change when the app is
/// updated, while the files inside it stay.
const offlinePackagesDirectory = 'offline_packages';

/// The folder of each package type inside [offlinePackagesDirectory].
const offlinePackageCategories = <String, String>{
  'surah_audio': 'audio',
  'mushaf_pages': 'mushaf',
  'salah_course': 'salah',
};

/// The path saved for a file of an offline package.
String offlinePackageItemPath(
  String category,
  String packageId,
  String fileName,
) => p.posix.join(offlinePackagesDirectory, category, packageId, fileName);

/// The file a saved path stands for inside [supportPath], or null for a path
/// outside the package folders. Paths saved by earlier versions are absolute;
/// on iOS the app's folder may have moved since, and then the package part of
/// the path is joined to the current folder.
String? resolveOfflinePackageItemPath(String supportPath, String storedPath) {
  if (storedPath.isEmpty) return null;
  final root = p.normalize(
    p.absolute(p.join(supportPath, offlinePackagesDirectory)),
  );
  var path = p.normalize(p.absolute(p.join(supportPath, storedPath)));
  if (p.isAbsolute(storedPath) && !p.isWithin(root, path)) {
    final relative = _packagePart(path);
    if (relative == null) return null;
    path = p.normalize(p.absolute(p.join(supportPath, relative)));
  }
  // <root>/<category>/<package id>/<file name>, as the downloads write it.
  if (!p.isWithin(root, path) ||
      p.split(p.relative(path, from: root)).length != 3) {
    return null;
  }
  return path;
}

/// `offline_packages/<category>/<package id>/<file name>`: the last four
/// parts of an absolute path saved by an earlier version.
String? _packagePart(String absolutePath) {
  final parts = p.split(absolutePath);
  if (parts.length < 5 || parts[parts.length - 4] != offlinePackagesDirectory) {
    return null;
  }
  return p.posix.joinAll(parts.sublist(parts.length - 4));
}

/// Saves the absolute paths of earlier versions as relative ones. A path is
/// changed only when it ends in exactly the file's own package path, built
/// from its row; any other stays and still resolves as before. Files are not
/// touched, so a download keeps working whether or not its row changed.
Future<void> relativizeOfflinePackageItemPaths(
  DatabaseExecutor database,
) async {
  final rows = await database.rawQuery('''
    SELECT item.package_id, item.item_key, item.file_name, item.local_path,
           package.package_type
    FROM offline_package_items AS item
    INNER JOIN offline_packages AS package
      ON package.package_id = item.package_id
    WHERE substr(item.local_path, 1, 1) = '/'
  ''');
  if (rows.isEmpty) return;
  final batch = database.batch();
  for (final row in rows) {
    final category = offlinePackageCategories[row['package_type']];
    final packageId = row['package_id'] as String;
    final fileName = row['file_name'] as String;
    final storedPath = row['local_path'] as String;
    if (category == null) continue;
    final relative = offlinePackageItemPath(category, packageId, fileName);
    if (!p.posix.normalize(storedPath).endsWith('/$relative')) continue;
    batch.update(
      'offline_package_items',
      <String, Object?>{'local_path': relative},
      where: 'package_id = ? AND item_key = ?',
      whereArgs: <Object?>[packageId, row['item_key']],
    );
  }
  await batch.commit(noResult: true);
}
