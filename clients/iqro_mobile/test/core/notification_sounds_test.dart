import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/notifications/reminder_sounds.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iOS notification sounds', () {
    // iOS plays the default sound instead of a file it cannot find, cannot
    // read or that lasts 30 seconds or more, and says nothing about it.
    for (final adhan in ReminderAdhan.values) {
      if (adhan == ReminderAdhan.none) continue;
      test('the ${adhan.name} adhan is a short CAF in the app bundle', () {
        final name = reminderNotificationDetails(
          ReminderSignal.sound,
          adhan,
        ).iOS!.sound!;
        expect(name, 'adhan_${adhan.name}.caf');
        final file = File('ios/Runner/$name');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(_cafSeconds(file.readAsBytesSync()), inExclusiveRange(1, 30));

        final project = File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();
        final resources = RegExp(
          r'/\* Begin PBXResourcesBuildPhase section \*/([\s\S]*?)'
          r'/\* End PBXResourcesBuildPhase section \*/',
        ).firstMatch(project)![1]!;
        expect(resources, contains('/* $name in Resources */'));

        // Android plays the same call from its raw resources.
        expect(
          File(
            'android/app/src/main/res/raw/adhan_${adhan.name}.mp3',
          ).existsSync(),
          isTrue,
        );
      });
    }

    test('the vibrating reminder has a short silent sound in the assets', () {
      final file = File(reminderVibrationAsset);
      expect(file.existsSync(), isTrue);
      final bytes = file.readAsBytesSync();
      expect(_cafSeconds(bytes), inExclusiveRange(0, 30));
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- $reminderVibrationAsset'),
      );
    });
  });

  group('a reminder on iOS', () {
    test('vibrates with the silent sound', () {
      final ios = reminderNotificationDetails(
        ReminderSignal.vibration,
        ReminderAdhan.none,
        vibrationSound: reminderVibrationSound,
      ).iOS!;
      expect(ios.sound, reminderVibrationSound);
      expect(ios.presentSound, isTrue);
    });

    test('stays silent when the silent sound is missing', () {
      // A missing file would ring with the default sound instead.
      final ios = reminderNotificationDetails(
        ReminderSignal.vibration,
        ReminderAdhan.none,
      ).iOS!;
      expect(ios.sound, isNull);
      expect(ios.presentSound, isFalse);
    });

    test('with sound or silent is as before', () {
      final sound = reminderNotificationDetails(
        ReminderSignal.sound,
        ReminderAdhan.none,
        vibrationSound: reminderVibrationSound,
      ).iOS!;
      expect(sound.sound, isNull);
      expect(sound.presentSound, isTrue);
      final silent = reminderNotificationDetails(
        ReminderSignal.silent,
        ReminderAdhan.none,
        vibrationSound: reminderVibrationSound,
      ).iOS!;
      expect(silent.sound, isNull);
      expect(silent.presentSound, isFalse);
    });

    test('keeps its Android channel and vibration', () {
      final android = reminderNotificationDetails(
        ReminderSignal.vibration,
        ReminderAdhan.none,
        vibrationSound: reminderVibrationSound,
      ).android!;
      expect(android.channelId, 'iqro_reminders_vibration');
      expect(android.playSound, isFalse);
      expect(android.enableVibration, isTrue);
    });
  });

  group('the silent sound', () {
    late Directory library;
    setUp(() async {
      library = await Directory.systemTemp.createTemp('iqro-library-');
    });
    tearDown(() => library.delete(recursive: true));

    test('is copied into Library/Sounds and kept up to date', () async {
      final asset = File(reminderVibrationAsset).readAsBytesSync();
      final bundle = _Bundle(asset);
      final copied = File(
        p.join(library.path, 'Sounds', reminderVibrationSound),
      );
      Future<String?> install() => installReminderVibrationSound(
        libraryDirectory: () async => library,
        bundle: bundle,
      );

      expect(await install(), reminderVibrationSound);
      expect(copied.readAsBytesSync(), asset);
      final copiedAt = copied.lastModifiedSync();
      expect(await install(), reminderVibrationSound);
      expect(copied.lastModifiedSync(), copiedAt);

      // A copy left by another build is replaced.
      copied.writeAsBytesSync(const <int>[1, 2, 3]);
      expect(await install(), reminderVibrationSound);
      expect(copied.readAsBytesSync(), asset);
    });

    test('that cannot be copied is not used', () async {
      expect(
        await installReminderVibrationSound(
          libraryDirectory: () async => library,
          bundle: _Bundle(null),
        ),
        isNull,
      );
    });
  });
}

/// Seconds of sound in a CAF file, read from its `desc` chunk and its `pakt`
/// chunk (compressed sound) or its `data` chunk (linear PCM).
double _cafSeconds(Uint8List bytes) {
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'caff');
  final data = ByteData.sublistView(bytes);
  double? sampleRate;
  int? bytesPerPacket;
  int? framesPerPacket;
  int? validFrames;
  int? soundBytes;
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getInt64(offset + 4);
    final body = offset + 12;
    switch (type) {
      case 'desc':
        sampleRate = data.getFloat64(body);
        bytesPerPacket = data.getUint32(body + 16);
        framesPerPacket = data.getUint32(body + 20);
      case 'pakt':
        validFrames = data.getInt64(body + 8);
      case 'data':
        // An unknown size runs to the end; the edit count comes first.
        soundBytes = (size < 0 ? bytes.length - body : size) - 4;
    }
    if (size < 0) break;
    offset = body + size;
  }
  if (validFrames != null) return validFrames / sampleRate!;
  return soundBytes! / bytesPerPacket! * framesPerPacket! / sampleRate!;
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.bytes);

  final Uint8List? bytes;
  var loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads += 1;
    final value = bytes;
    if (value == null) throw StateError('No asset $key');
    return ByteData.sublistView(value);
  }
}
