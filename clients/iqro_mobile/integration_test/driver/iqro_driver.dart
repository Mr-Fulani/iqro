// Runs on the Mac during `flutter drive` (ios/scripts/simulator_run.sh).
//
// When the test asks for a screenshot (IqroHarness.screenshot posts an
// `iqro.screenshot` event), this saves the simulator's whole screen, status
// bar included, with `xcrun simctl io screenshot`, then lets the test go on.
// At the end it reports the test result like the stock integration driver.
import 'dart:async';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:vm_service/vm_service.dart';

Future<void> main() async {
  final simulator = Platform.environment['IQRO_SIMULATOR'];
  final folder = Directory(
    Platform.environment['IQRO_SCREENSHOTS'] ?? 'build/simulator-screens',
  );
  await folder.create(recursive: true);
  final driver = await FlutterDriver.connect();
  final service = driver.serviceClient;
  final isolate = driver.appIsolate.id!;

  // The test waits for each answer, so every file is written before it ends.
  service.onExtensionEvent.listen((event) {
    if (event.extensionKind != 'iqro.screenshot') return;
    final name = event.extensionData?.data['name'] as String? ?? 'screen';
    unawaited(_save(service, isolate, simulator, folder, name));
  });
  try {
    await service.streamListen(EventStreams.kExtension);
  } on RPCError catch (error) {
    if (error.code != RPCErrorKind.kStreamAlreadySubscribed.code) rethrow;
  }

  // Prints the result and exits with 0 or 1.
  await integrationDriver(
    driver: driver,
    // The screenshots are files already; nothing else to write.
    responseDataCallback: null,
  );
}

Future<void> _save(
  VmService service,
  String isolate,
  String? simulator,
  Directory folder,
  String name,
) async {
  final path = '${folder.path}/$name.png';
  if (simulator == null) {
    stdout.writeln('IQRO DRIVER no IQRO_SIMULATOR, $name not saved');
  } else {
    final result = await Process.run('xcrun', <String>[
      'simctl',
      'io',
      simulator,
      'screenshot',
      '--type=png',
      '--mask=ignored',
      path,
    ]);
    if (result.exitCode == 0) {
      stdout.writeln('IQRO DRIVER saved $path');
    } else {
      stderr.writeln('IQRO DRIVER screenshot $name failed: ${result.stderr}');
    }
  }
  try {
    await service.callServiceExtension(
      'ext.iqro.screenshotSaved',
      isolateId: isolate,
    );
  } on Object catch (error) {
    stderr.writeln('IQRO DRIVER could not tell the test: $error');
  }
}
