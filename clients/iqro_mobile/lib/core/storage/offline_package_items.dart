import 'package:sqflite/sqflite.dart';

/// Queue inside the package transaction so a resumed download keeps its state.
/// Android 7–9 can ship SQLite without UPSERT (ON CONFLICT DO UPDATE).
/// INSERT OR REPLACE is not equivalent: it deletes the existing row.
void enqueueOfflinePackageItem(
  Batch batch, {
  required String packageId,
  required String itemKey,
  required int itemNumber,
  required String fileName,
  required String localPath,
  required String url,
  required String checksum,
  required int sizeBytes,
  required String metadata,
  required String updatedAt,
}) {
  batch.insert('offline_package_items', <String, Object?>{
    'package_id': packageId,
    'item_key': itemKey,
    'item_number': itemNumber,
    'file_name': fileName,
    'local_path': localPath,
    'url': url,
    'checksum_sha256': checksum,
    'size_bytes': sizeBytes,
    'metadata': metadata,
    'status': 'pending',
    'downloaded_bytes': 0,
    'updated_at': updatedAt,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.rawUpdate(
    '''
    UPDATE offline_package_items SET
      file_name = ?, local_path = ?, url = ?, metadata = ?, updated_at = ?,
      status = CASE WHEN checksum_sha256 = ? AND size_bytes = ?
        THEN status ELSE 'pending' END,
      downloaded_bytes = CASE WHEN checksum_sha256 = ? AND size_bytes = ?
        THEN downloaded_bytes ELSE 0 END,
      checksum_sha256 = ?, size_bytes = ?
    WHERE package_id = ? AND item_key = ?
    ''',
    <Object?>[
      fileName,
      localPath,
      url,
      metadata,
      updatedAt,
      checksum,
      sizeBytes,
      checksum,
      sizeBytes,
      checksum,
      sizeBytes,
      packageId,
      itemKey,
    ],
  );
}
