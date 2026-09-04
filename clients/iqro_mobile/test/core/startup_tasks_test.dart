import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/startup/startup_tasks.dart';

void main() {
  test(
    'critical startup initializes dependencies and audio concurrently',
    () async {
      final dependenciesReady = Completer<String>();
      final audioReady = Completer<void>();
      var dependenciesStarted = false;
      var audioStarted = false;

      final startup = initializeCriticalStartup<String>(
        initializeDependencies: () {
          dependenciesStarted = true;
          return dependenciesReady.future;
        },
        initializeAudioPlatform: () {
          audioStarted = true;
          return audioReady.future;
        },
      );

      expect(dependenciesStarted, isTrue);
      expect(audioStarted, isTrue);
      var completed = false;
      unawaited(startup.then((_) => completed = true));
      dependenciesReady.complete('ready');
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      audioReady.complete();

      await expectLater(startup, completion('ready'));
    },
  );

  test('critical startup propagates initialization failures', () async {
    await expectLater(
      initializeCriticalStartup<String>(
        initializeDependencies: () async => 'ready',
        initializeAudioPlatform: () async => throw StateError('audio failed'),
      ),
      throwsStateError,
    );
  });
}
