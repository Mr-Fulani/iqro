import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/background/background_work.dart';

void main() {
  test(
    'background maintenance is enabled only on supported mobile targets',
    () {
      expect(supportsIqroBackgroundWork(isAndroid: true, isIOS: false), isTrue);
      expect(supportsIqroBackgroundWork(isAndroid: false, isIOS: true), isTrue);
      expect(
        supportsIqroBackgroundWork(isAndroid: false, isIOS: false),
        isFalse,
      );
    },
  );

  test('iOS native configuration is aligned with the Dart contract', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>$iqroMaintenanceUniqueName</string>'));
    expect(plist, contains('<string>audio</string>'));
    expect(plist, contains('<string>fetch</string>'));
    expect(plist, contains('<key>CFBundleAllowMixedLocalizations</key>'));
    expect(
      plist,
      contains('<key>CFBundleAllowMixedLocalizations</key>\n\t<true/>'),
    );
    expect(plist, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
    expect(plist, isNot(contains('NSLocationAlways')));
    // iOS closes the app when it asks for a permission without its text:
    // "Save Image" in the share sheet, and the microphone and speech
    // recognition of the recitation check. Debug builds read Info-Debug.plist.
    for (final file in const <String>['Info.plist', 'Info-Debug.plist']) {
      final copy = File('ios/Runner/$file').readAsStringSync();
      for (final key in const <String>[
        'NSPhotoLibraryAddUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSSpeechRecognitionUsageDescription',
        'NSLocationWhenInUseUsageDescription',
      ]) {
        expect(copy, contains('<key>$key</key>'), reason: '$file: $key');
      }
      // The location also gives the qibla direction, not only prayer times.
      expect(copy, contains('qibla direction'), reason: file);
    }

    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('WorkmanagerPlugin.registerLaunchHandlers()'));
    expect(
      appDelegate,
      contains('WorkmanagerPlugin.setPluginRegistrantCallback'),
    );
    expect(appDelegate, contains(iqroMaintenanceUniqueName));

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0')));
    expect(
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = 15\.0;').allMatches(project).length,
      9,
    );
    expect(
      RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = forum\.iqro\.app;',
      ).allMatches(project).length,
      3,
    );
    // iPhone only (the owner's decision of 27.11.2026); on an iPad it runs
    // in compatibility mode, which the iOS simulators workflow checks.
    expect(
      RegExp(r'TARGETED_DEVICE_FAMILY = 1;').allMatches(project).length,
      6,
    );
    expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    // The adhan may sound in Focus: Time Sensitive notifications.
    expect(
      File('ios/Runner/Runner.entitlements').readAsStringSync(),
      contains(
        '<key>com.apple.developer.usernotifications.time-sensitive</key>\n\t\t<true/>',
      ),
    );
  });

  test('iOS permission copy covers every supported locale', () {
    for (final locale in const <String>['en', 'ru', 'ar', 'tr']) {
      final copy = File(
        'ios/Runner/$locale.lproj/InfoPlist.strings',
      ).readAsStringSync();
      expect(copy, contains('"CFBundleDisplayName" = "IQRO";'));
      expect(copy, contains('"NSLocationWhenInUseUsageDescription"'));
      expect(copy, contains('"NSPhotoLibraryAddUsageDescription"'));
      expect(copy, contains('"NSMicrophoneUsageDescription"'));
      expect(copy, contains('"NSSpeechRecognitionUsageDescription"'));
    }
    const qibla = <String, String>{
      'en': 'qibla',
      'ru': 'Киблы',
      'ar': 'القبلة',
      'tr': 'kıble',
    };
    for (final MapEntry(key: locale, value: word) in qibla.entries) {
      final location = File('ios/Runner/$locale.lproj/InfoPlist.strings')
          .readAsLinesSync()
          .singleWhere(
            (line) => line.startsWith('"NSLocationWhenInUseUsageDescription"'),
          );
      expect(location, contains(word), reason: locale);
    }

    final podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile, contains("platform :ios, '15.0'"));
    expect(podfile, contains('BYPASS_PERMISSION_LOCATION_ALWAYS=1'));
  });
}
