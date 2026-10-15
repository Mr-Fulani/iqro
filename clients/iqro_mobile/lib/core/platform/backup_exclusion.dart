import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps re-downloadable content out of iCloud backups (iOS Data Storage
/// Guidelines). Android's auto backup does not include these folders.
class BackupExclusion {
  static const channel = MethodChannel('forum.iqro.app/backup_exclusion');
  static final _excluded = <String>{};

  /// Marks an existing root directory; the flag covers everything inside it.
  static Future<void> exclude(Directory directory) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final path = directory.absolute.path;
    if (_excluded.contains(path)) return;
    try {
      await channel.invokeMethod<void>('excludeFromBackup', path);
      _excluded.add(path);
    } on MissingPluginException {
      // Test hosts and engines without the channel retry on the next call.
    } on PlatformException {
      // Exclusion is best effort and must never block a download.
    }
  }

  @visibleForTesting
  static void resetForTesting() => _excluded.clear();
}
