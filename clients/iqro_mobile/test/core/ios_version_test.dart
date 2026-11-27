import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/platform/ios_version.dart';

void main() {
  test('reads the iOS version from NSProcessInfo text', () {
    expect(iosVersion('Version 17.2 (Build 21C62)'), '17.2');
    expect(iosVersion('Version 26.1.1 (Build 23B85)'), '26.1.1');
    expect(iosVersion('Version 18 (Build 22A3354)'), '18');
    expect(iosVersion(''), 'unknown');
  });

  test('nothing asks device_info_plus for iOS details', () {
    // Its iOS code is not in the app (third_party/device_info_plus/README.md),
    // so iosInfo would throw MissingPluginException on an iPhone.
    final callers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) {
          final text = file.readAsStringSync();
          return text.contains('.iosInfo') || text.contains('.deviceInfo');
        })
        .map((file) => file.path)
        .toList();
    expect(callers, isEmpty);

    final pubspec = File(
      'third_party/device_info_plus/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, isNot(contains('ios:')));
    expect(pubspec, isNot(contains('macos:')));
  });

  test('the recitation model is packed for Android only', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('- assets/recitation_model/\n')));
    for (final file in const <String>[
      'model-int8.onnx',
      'expected.json',
      'mel_filters.bin',
    ]) {
      expect(
        pubspec,
        contains(
          '- path: assets/recitation_model/$file\n'
          '      platforms: [android]',
        ),
        reason: file,
      );
    }
  });
}
