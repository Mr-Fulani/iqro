import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android prayer widget is generated and fully wired', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final provider = File(
      'android/app/src/main/res/xml/prayer_times_home_widget.xml',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/forum/iqro/app/PrayerTimesHomeWidget.kt',
    ).readAsStringSync();

    expect(gradle, contains('androidx.glance:glance-appwidget:1.2.0'));
    expect(gradle, contains('kotlin.plugin.compose'));
    expect(manifest, contains('PrayerTimesHomeWidgetReceiver'));
    expect(manifest, contains('HomeWidgetScheduledUpdateReceiver'));
    expect(manifest, contains('android:pathPrefix="/prayer"'));
    expect(provider, contains('android:targetCellWidth="4"'));
    expect(provider, contains('android:updatePeriodMillis="21600000"'));
    expect(kotlin, contains('home_widget.PrayerTimes'));
    expect(kotlin, contains('iqro://open/prayer?homeWidget'));
    expect(kotlin, isNot(contains('Color(0xFFE2B665, textAlign')));
  });

  test('iOS prayer widget target shares only its explicit App Group', () {
    final runnerEntitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final widgetEntitlements = File(
      'ios/PrayerTimesHomeWidget.entitlements',
    ).readAsStringSync();
    final widget = File(
      'ios/PrayerTimesHomeWidget/Widget.swift',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    for (final entitlements in <String>[
      runnerEntitlements,
      widgetEntitlements,
    ]) {
      expect(entitlements, contains('group.forum.iqro.app'));
    }
    expect(widget, contains('.supportedFamilies([.systemMedium])'));
    expect(widget, contains('iqro://open/prayer?homeWidget'));
    expect(project, contains('PrayerTimesHomeWidget.appex'));
    expect(
      RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = forum\.iqro\.app\.PrayerTimesHomeWidget;',
      ).allMatches(project),
      hasLength(3),
    );
    expect(
      RegExp(
        r'CURRENT_PROJECT_VERSION = "\$\(FLUTTER_BUILD_NUMBER\)";',
      ).allMatches(project).length,
      greaterThanOrEqualTo(6),
    );
  });
}
