import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../../app/app_dependencies.dart';

const iqroMaintenanceUniqueName = 'forum.iqro.app.periodic-maintenance-v1';
const iqroMaintenanceTaskName = 'iqro-periodic-maintenance';
const iqroMaintenanceFrequency = Duration(hours: 6);

@pragma('vm:entry-point')
void iqroBackgroundDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != iqroMaintenanceTaskName &&
        taskName != iqroMaintenanceUniqueName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }
    AppDependencies? dependencies;
    try {
      dependencies = await AppDependencies.initialize();
      final report = await dependencies.maintenance.run();
      return !report.shouldRetry;
    } on Object {
      return false;
    } finally {
      if (dependencies != null) await dependencies.database.close();
    }
  });
}

Future<void> initializeBackgroundWork() async {
  final isAndroid = Platform.isAndroid;
  final isIOS = Platform.isIOS;
  if (!supportsIqroBackgroundWork(isAndroid: isAndroid, isIOS: isIOS)) return;
  final workmanager = Workmanager();
  await workmanager.initialize(iqroBackgroundDispatcher);
  if (isIOS) {
    await workmanager.registerPeriodicTask(
      iqroMaintenanceUniqueName,
      iqroMaintenanceTaskName,
      frequency: iqroMaintenanceFrequency,
      initialDelay: iqroMaintenanceFrequency,
    );
    return;
  }
  await workmanager.registerPeriodicTask(
    iqroMaintenanceUniqueName,
    iqroMaintenanceTaskName,
    frequency: iqroMaintenanceFrequency,
    flexInterval: const Duration(hours: 1),
    initialDelay: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
      requiresStorageNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    tag: 'iqro-maintenance',
  );
}

bool supportsIqroBackgroundWork({
  required bool isAndroid,
  required bool isIOS,
}) => isAndroid || isIOS;
