import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/platform/backup_exclusion.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final native = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    BackupExclusion.resetForTesting();
    native.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackupExclusion.channel,
      (call) async {
        native.add(call);
        return null;
      },
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackupExclusion.channel,
      null,
    );
  });

  test('iOS marks the root directory once by absolute path', () async {
    final root = Directory('support/offline_packages');
    await BackupExclusion.exclude(root);
    await BackupExclusion.exclude(root);
    expect(native, hasLength(1));
    expect(native.single.method, 'excludeFromBackup');
    expect(native.single.arguments, root.absolute.path);
  });

  test('Android is a no-op', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await BackupExclusion.exclude(Directory('/support/offline_packages'));
    expect(native, isEmpty);
  });

  test('native failure never blocks and is retried later', () async {
    final root = Directory('/support/mushaf_pages');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackupExclusion.channel,
      (call) async {
        native.add(call);
        throw PlatformException(code: 'exclude_failed');
      },
    );
    await BackupExclusion.exclude(root);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackupExclusion.channel,
      null,
    );
    await BackupExclusion.exclude(root);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackupExclusion.channel,
      (call) async {
        native.add(call);
        return null;
      },
    );
    await BackupExclusion.exclude(root);
    await BackupExclusion.exclude(root);
    expect(native, hasLength(2));
  });
}
