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
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = 14\.0;').allMatches(project).length,
      9,
    );
    expect(
      RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = forum\.iqro\.app;',
      ).allMatches(project).length,
      3,
    );
    expect(project, contains('TARGETED_DEVICE_FAMILY = "1,2";'));
  });

  test('iOS permission copy covers every supported locale', () {
    for (final locale in const <String>['en', 'ru', 'ar', 'tr']) {
      final copy = File(
        'ios/Runner/$locale.lproj/InfoPlist.strings',
      ).readAsStringSync();
      expect(copy, contains('"CFBundleDisplayName" = "IQRO";'));
      expect(copy, contains('"NSLocationWhenInUseUsageDescription"'));
    }

    final podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile, contains("platform :ios, '14.0'"));
    expect(podfile, contains('BYPASS_PERMISSION_LOCATION_ALWAYS=1'));
  });
}
