import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a play pressed before the audio platform has started', () {
    test('waits for it', () async {
      final starting = Completer<void>();
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final engine = JustAudioEngine(player, starting.future);

      unawaited(engine.play());
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      starting.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isTrue);
    });

    test('is dropped by a pause that came meanwhile', () async {
      final starting = Completer<void>();
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final engine = JustAudioEngine(player, starting.future);

      unawaited(engine.play());
      await engine.pause();
      starting.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      // Later presses no longer wait.
      unawaited(engine.play());
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isTrue);
    });
  });
}
