import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/account_scoped_maintenance.dart';
import 'package:iqro_mobile/core/audio/audio_playback_sync_service.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/background/background_maintenance_service.dart';
import 'package:iqro_mobile/core/sync/sync_service.dart';

void main() {
  const accountA = (userId: 'account-a', epoch: 1);
  const accountB = (userId: 'account-b', epoch: 2);

  test(
    'a delayed previous-account cancellation is contained and does not throttle the next account',
    () async {
      final coordinator = AccountScopedMaintenanceCoordinator(
        clock: () => DateTime.utc(2035),
      );
      final accountAFlight = Completer<BackgroundMaintenanceReport>();
      final started = <MaintenanceAccountKey>[];
      final unexpected = <Object>[];
      var active = accountA;

      final first = coordinator.run(
        key: accountA,
        maintenance: () {
          started.add(accountA);
          return accountAFlight.future;
        },
        isCurrent: (key) => active == key,
        restoreAudio: () async {},
        reportUnexpected: (error, stackTrace) => unexpected.add(error),
      );

      active = accountB;
      final second = coordinator.run(
        key: accountB,
        maintenance: () async {
          started.add(accountB);
          return _report;
        },
        isCurrent: (key) => active == key,
        restoreAudio: () async {},
        reportUnexpected: (error, stackTrace) => unexpected.add(error),
      );

      await second;
      accountAFlight.completeError(const AccountScopeChanged());
      await expectLater(first, completes);

      expect(started, <MaintenanceAccountKey>[accountA, accountB]);
      expect(unexpected, isEmpty);
    },
  );

  test('the throttle applies only to the same account generation', () async {
    final coordinator = AccountScopedMaintenanceCoordinator(
      clock: () => DateTime.utc(2035),
    );
    var calls = 0;

    Future<void> request(MaintenanceAccountKey key) => coordinator.run(
      key: key,
      maintenance: () async {
        calls += 1;
        return _report;
      },
      isCurrent: (_) => true,
      restoreAudio: () async {},
      reportUnexpected: (error, stackTrace) => fail('$error\n$stackTrace'),
    );

    await request(accountA);
    await request(accountA);
    await request((userId: accountA.userId, epoch: accountA.epoch + 1));

    expect(calls, 2);
  });
}

const _report = BackgroundMaintenanceReport(
  sync: SyncReport(status: SyncStatus.idle),
  audio: AudioPlaybackSyncReport(AudioPlaybackSyncStatus.idle),
  remindersScheduled: 0,
);
