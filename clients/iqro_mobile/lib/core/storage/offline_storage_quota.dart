import 'local_database.dart';

const offlineStorageQuotaBytes = 3 * 1024 * 1024 * 1024;

class OfflineStorageQuotaExceeded implements Exception {
  const OfflineStorageQuotaExceeded({
    required this.requiredBytes,
    required this.availableBytes,
  });

  final int requiredBytes;
  final int availableBytes;
}

Future<int> reservedOfflineStorageBytes(
  LocalDatabase database, {
  String? excludingPackageId,
}) async {
  final rows = await database.database.rawQuery(
    '''
    SELECT COALESCE(SUM(
      CASE
        WHEN total_bytes > downloaded_bytes THEN total_bytes
        ELSE downloaded_bytes
      END
    ), 0) AS reserved_bytes
    FROM offline_packages
    WHERE (? IS NULL OR package_id <> ?)
    ''',
    <Object?>[excludingPackageId, excludingPackageId],
  );
  return (rows.single['reserved_bytes'] as num?)?.toInt() ?? 0;
}

Future<void> ensureOfflineStorageCapacity(
  LocalDatabase database, {
  required String packageId,
  required int packageBytes,
}) async {
  if (packageBytes <= 0 || packageBytes > offlineStorageQuotaBytes) {
    throw OfflineStorageQuotaExceeded(
      requiredBytes: packageBytes,
      availableBytes: offlineStorageQuotaBytes,
    );
  }
  final reserved = await reservedOfflineStorageBytes(
    database,
    excludingPackageId: packageId,
  );
  final available = (offlineStorageQuotaBytes - reserved).clamp(
    0,
    offlineStorageQuotaBytes,
  );
  if (packageBytes > available) {
    throw OfflineStorageQuotaExceeded(
      requiredBytes: packageBytes,
      availableBytes: available,
    );
  }
}
