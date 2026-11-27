import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The silent sound of a vibrating reminder on iOS: there a notification
/// without a sound does not vibrate, while one with a silent sound vibrates
/// as the phone's sound settings say. iOS looks for notification sounds in
/// the app's Library/Sounds folder before its bundle, so the file is copied
/// there from the assets; the adhan files are in the bundle (ios/Runner).
const reminderVibrationSound = 'reminder_vibrate.caf';
const reminderVibrationAsset = 'assets/sounds/$reminderVibrationSound';

/// Puts the silent sound in Library/Sounds and returns its name; a copy of
/// another size, from another build, is replaced. Null when that fails: iOS
/// plays a sound it cannot find as the default one, so the reminder then
/// stays silent instead.
Future<String?> installReminderVibrationSound({
  Future<Directory> Function()? libraryDirectory,
  AssetBundle? bundle,
}) async {
  try {
    final library = await (libraryDirectory ?? getLibraryDirectory)();
    final file = File(p.join(library.path, 'Sounds', reminderVibrationSound));
    final data = await (bundle ?? rootBundle).load(reminderVibrationAsset);
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.partial');
      await partial.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await partial.rename(file.path);
    }
    return reminderVibrationSound;
  } on Object {
    return null;
  }
}
