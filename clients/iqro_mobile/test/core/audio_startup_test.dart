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

  group('the audio session', () {
    test('is set back before each play', () async {
      final playingAtRestore = <bool>[];
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final engine = JustAudioEngine(player, null, () async {
        playingAtRestore.add(player.playing);
      });

      unawaited(engine.play());
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isTrue);
      await engine.pause();
      unawaited(engine.play());
      await Future<void>.delayed(Duration.zero);
      expect(playingAtRestore, <bool>[false, false]);
      expect(player.playing, isTrue);
    });

    test('is set back after the platform has started', () async {
      final starting = Completer<void>();
      final order = <String>[];
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final engine = JustAudioEngine(
        player,
        starting.future.then((_) => order.add('started')),
        () async => order.add('restored'),
      );

      unawaited(engine.play());
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      starting.complete();
      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['started', 'restored']);
      expect(player.playing, isTrue);
    });

    test('a pause while it is set back drops the play', () async {
      final restoring = Completer<void>();
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final engine = JustAudioEngine(player, null, () => restoring.future);

      unawaited(engine.play());
      await engine.pause();
      restoring.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
    });
  });
}
