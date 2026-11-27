// Runs on the Mac during `flutter drive` (ios/scripts/simulator_run.sh).
//
// Once connected it starts the screen recording (the app is up by then, so the
// video holds the app, not the install), hands the test its settings, and
// saves the simulator's whole screen, status bar included, whenever the test
// asks (IqroHarness.screenshot posts an `iqro.screenshot` event). At the end
// it reports the result like the stock integration driver. The recording is
// stopped by simulator_run.sh, after `flutter drive` has exited.
import 'dart:async';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:vm_service/vm_service.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final simulator = environment['IQRO_SIMULATOR'];
  final folder = Directory(
    environment['IQRO_SCREENSHOTS'] ?? 'build/simulator-screens',
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

  if (simulator != null && environment['NO_VIDEO'] != '1') {
    // Detached: it outlives this process, which integrationDriver ends with
    // exit(); simulator_run.sh stops it with SIGINT so the file is finished.
    final recorder = await Process.start('xcrun', <String>[
      'simctl',
      'io',
      simulator,
      'recordVideo',
      '--codec=h264',
      '--mask=ignored',
      '--force',
      '${folder.path}/video.mp4',
    ], mode: ProcessStartMode.detached);
    await File('${folder.path}/video.pid').writeAsString('${recorder.pid}');
    // simctl needs a moment before the first frame is captured.
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  // The test starts the app once this arrives.
  try {
    final locale = environment['IQRO_LOCALE'] ?? '';
    stdout.writeln('IQRO DRIVER ready, locale "$locale", simulator $simulator');
    await service.callServiceExtension(
      'ext.iqro.driverReady',
      isolateId: isolate,
      args: <String, String>{
        'locale': locale,
        'mode': environment['IQRO_MODE'] ?? '',
      },
    );
  } on Object catch (error) {
    stderr.writeln('IQRO DRIVER the test takes no screenshots: $error');
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
