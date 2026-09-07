import 'dart:convert';

import 'package:sqflite/sqflite.dart';

// Full 604-page manifests exceed Android's CursorWindow. Status/list queries
// must not read that blob; per-page metadata lives in offline_package_items.
const offlinePackageSummaryColumns = <String>[
  'package_id',
  'package_type',
  'content_key',
  'status',
  'is_active',
  'completed_items',
  'total_items',
  'downloaded_bytes',
  'total_bytes',
  'last_error',
];

/// Audio summaries still need reciter/quality from existing manifests. Read in
/// bounded chunks so old installations need neither migration nor redownload.
Future<Map<String, Object?>> readOfflineAudioSummary(
  DatabaseExecutor database,
  String packageId,
) async {
  const chunkSize = 64 * 1024;
  final encoded = StringBuffer();
  for (var offset = 1; ; offset += chunkSize) {
    final rows = await database.rawQuery(
      'SELECT substr(manifest, ?, ?) AS chunk FROM offline_packages '
      'WHERE package_id = ?',
      <Object?>[offset, chunkSize, packageId],
    );
    if (rows.isEmpty) return const {};
    final chunk = rows.single['chunk'] as String? ?? '';
    encoded.write(chunk);
    if (chunk.runes.length < chunkSize) break;
  }
  try {
    final manifest = jsonDecode(encoded.toString());
    if (manifest is! Map) return const {};
    return <String, Object?>{
      'quality': manifest['quality'],
      'reciter': manifest['reciter'],
    };
  } on FormatException {
    return const {};
  }
}
