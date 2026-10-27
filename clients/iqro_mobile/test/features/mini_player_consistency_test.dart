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

    expect(
      appShell,
      matches(
        RegExp(
          r'children: <Widget>\[\s*AppUpdateCard\(\),\s*'
          r'AnalyticsConsentCard\(\),\s*IqroMiniPlayer\(\),\s*\]',
        ),
      ),
    );
    expect(appShell, contains('const PositionedDirectional('));
    expect(
      appShell,
      isNot(contains('if (playerActive) const IqroMiniPlayer()')),
    );
    expect(
      mushaf,
      matches(
        RegExp(
          r'IqroMiniPlayer\(\s*allowCollapse: false,\s*mushafControls: true,',
        ),
      ),
    );
    expect(mushaf, isNot(contains('_ReaderAudioPill')));
    expect(miniPlayer, isNot(contains('BackdropFilter')));
  });
}
