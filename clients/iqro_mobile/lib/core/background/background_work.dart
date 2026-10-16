import 'dart:io';

import 'package:workmanager/workmanager.dart';

const iqroMaintenanceUniqueName = 'forum.iqro.app.periodic-maintenance-v1';
const iqroMaintenanceTaskName = 'iqro-periodic-maintenance';

@pragma('vm:entry-point')
void iqroBackgroundDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != iqroMaintenanceTaskName &&
        taskName != iqroMaintenanceUniqueName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    // Workmanager runs this callback in a separate Dart isolate. Process-local
    // account epochs cannot fence that isolate against a foreground logout or
    // account handoff. Until a transactional cross-isolate generation fence is
    // available, account-owned sync, auth refresh and notification scheduling
    // are intentionally restricted to the foreground isolate. Existing OS
    // reminders remain scheduled and foreground lifecycle maintenance still
    // refreshes account data.
    return true;
  });
}

Future<void> initializeBackgroundWork() async {
  final isAndroid = Platform.isAndroid;
  final isIOS = Platform.isIOS;
  if (!supportsIqroBackgroundWork(isAndroid: isAndroid, isIOS: isIOS)) return;
  final workmanager = Workmanager();
  await workmanager.initialize(iqroBackgroundDispatcher);
  // The maintenance callback deliberately does nothing yet (see the dispatcher),
  // so nothing is scheduled: an empty job every 6 hours only woke the app and
  // cost battery. Earlier releases scheduled it, so drop that registration too.
  // Scheduling returns once the cross-isolate account fence exists.
  await workmanager.cancelByUniqueName(iqroMaintenanceUniqueName);
}

bool supportsIqroBackgroundWork({
  required bool isAndroid,
  required bool isIOS,
}) => isAndroid || isIOS;
