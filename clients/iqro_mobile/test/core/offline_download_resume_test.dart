import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/offline_download_resume.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void leaveScreen() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void returnToScreen() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test(
    'a file cut off while the app is away goes on when it is back',
    () async {
      var attempts = 0;
      final result = retryOfflineFileAfterBackground(() async {
        attempts += 1;
        if (attempts == 1) {
          // The screen locks and iOS suspends the app mid-download.
          leaveScreen();
          throw const SocketException('Software caused connection abort');
        }
        return 'done';
      });

      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
      returnToScreen();

      expect(await result, 'done');
      expect(attempts, 2);
    },
  );

  test('a file that failed after the app was away is tried again', () async {
    var attempts = 0;
    final result = await retryOfflineFileAfterBackground(() async {
      attempts += 1;
      if (attempts == 1) {
        leaveScreen();
        returnToScreen();
        throw const SocketException('Connection reset by peer');
      }
      return 'done';
    });

    expect(result, 'done');
    expect(attempts, 2);
  });

  test('a failure with the app on the screen is not retried', () async {
    var attempts = 0;
    await expectLater(
      retryOfflineFileAfterBackground<void>(() async {
        attempts += 1;
        throw const SocketException('Network is unreachable');
      }),
      throwsA(isA<SocketException>()),
    );
    expect(attempts, 1);
  });
}
