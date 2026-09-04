import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppShell and Mushaf share one mini-player implementation', () async {
    final appShell = await File('lib/app/app_shell.dart').readAsString();
    final mushaf = await File(
      'lib/features/quran/mushaf_screen.dart',
    ).readAsString();

    expect(appShell, contains('const IqroMiniPlayer()'));
    expect(mushaf, contains('const IqroMiniPlayer()'));
    expect(mushaf, isNot(contains('_ReaderAudioPill')));
  });
}
