import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppShell and Mushaf share one mini-player implementation', () async {
    final appShell = await File('lib/app/app_shell.dart').readAsString();
    final mushaf = await File(
      'lib/features/quran/mushaf_screen.dart',
    ).readAsString();
    final miniPlayer = await File(
      'lib/features/audio/mini_player.dart',
    ).readAsString();

    expect(appShell, contains('child: IqroMiniPlayer()'));
    expect(appShell, contains('const PositionedDirectional('));
    expect(
      appShell,
      isNot(contains('if (playerActive) const IqroMiniPlayer()')),
    );
    expect(mushaf, contains('IqroMiniPlayer()'));
    expect(mushaf, isNot(contains('_ReaderAudioPill')));
    expect(miniPlayer, isNot(contains('BackdropFilter')));
  });
}
