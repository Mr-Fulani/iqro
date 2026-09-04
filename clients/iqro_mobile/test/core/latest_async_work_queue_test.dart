import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/utils/latest_async_work_queue.dart';

void main() {
  test('keeps only the latest value while work is in flight', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final processed = <int>[];
    final queue = LatestAsyncWorkQueue<int>((value) async {
      processed.add(value);
      if (value == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    });

    queue.add(1);
    await firstStarted.future;
    queue.add(2);
    queue.add(3);
    releaseFirst.complete();
    await queue.idle;

    expect(processed, <int>[1, 3]);
  });

  test('continues with the latest value after a worker error', () async {
    final errors = <Object>[];
    final processed = <int>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final queue = LatestAsyncWorkQueue<int>((value) async {
      processed.add(value);
      if (value == 1) {
        firstStarted.complete();
        await releaseFirst.future;
        throw StateError('failed');
      }
    }, onError: (error, stackTrace) => errors.add(error));

    queue.add(1);
    await firstStarted.future;
    queue.add(2);
    releaseFirst.complete();
    await queue.idle;

    expect(processed, <int>[1, 2]);
    expect(errors, hasLength(1));
  });

  test('clearPending and close discard superseded work', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final processed = <int>[];
    final queue = LatestAsyncWorkQueue<int>((value) async {
      processed.add(value);
      if (value == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    });

    queue.add(1);
    await firstStarted.future;
    queue.add(2);
    queue.clearPending();
    queue.add(3);
    queue.close();
    releaseFirst.complete();
    await queue.idle;
    queue.add(4);

    expect(processed, <int>[1]);
  });

  test('close can drain the final pending value', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final processed = <int>[];
    final queue = LatestAsyncWorkQueue<int>((value) async {
      processed.add(value);
      if (value == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    });

    queue.add(1);
    await firstStarted.future;
    queue.add(2);
    queue.close(discardPending: false);
    queue.add(3);
    releaseFirst.complete();
    await queue.idle;

    expect(processed, <int>[1, 2]);
  });
}
