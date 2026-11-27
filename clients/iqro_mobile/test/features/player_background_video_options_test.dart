import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/player_screen.dart';

void main() {
  test('the player background video mixes on Android only', () {
    // On iOS a mixing video makes the whole audio session mixable, and the
    // lock screen loses the recitation's controls.
    expect(
      playerBackgroundVideoOptions(TargetPlatform.android).mixWithOthers,
      isTrue,
    );
    expect(
      playerBackgroundVideoOptions(TargetPlatform.iOS).mixWithOthers,
      isFalse,
    );
  });
}
