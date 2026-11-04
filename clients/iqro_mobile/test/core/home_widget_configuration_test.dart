import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/plan/plan_widget_service.dart';

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

  test('prayer widget bridge names its receiver in full', () {
    // A suffixed application id (forum.iqro.app.test) keeps the receiver in
    // forum.iqro.app, so a short androidName resolves to a missing class.
    final schema = File('home_widget/prayer_times.dart').readAsStringSync();
    final bridge = File(
      'lib/core/widgets/prayer_times.home_widget.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    const receiver = 'forum.iqro.app.PrayerTimesHomeWidgetReceiver';

    expect(schema, contains("packageName: 'forum.iqro.app'"));
    expect(bridge, isNot(contains('androidName:')));
    expect(
      "qualifiedAndroidName: '$receiver'".allMatches(bridge),
      hasLength(4),
    );
    expect(manifest, contains('android:name="$receiver"'));
  });

  test(
    'Android plan widget is found in every build and never starts blank',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final provider = File(
        'android/app/src/main/res/xml/reading_plan_home_widget.xml',
      ).readAsStringSync();
      final kotlin = File(
        'android/app/src/main/kotlin/forum/iqro/app/ReadingPlanHomeWidget.kt',
      ).readAsStringSync();

      // The test build adds .test to the application id but not to the class.
      expect(
        planWidgetReceiver,
        'forum.iqro.app.ReadingPlanHomeWidgetReceiver',
      );
      expect(kotlin, contains('package forum.iqro.app\n'));
      expect(kotlin, contains('class ReadingPlanHomeWidgetReceiver'));
      expect(manifest, contains('android:name="$planWidgetReceiver"'));
      expect(provider, contains('@layout/reading_plan_widget_initial'));
      expect(provider, isNot(contains('glance_default_loading_layout')));
    },
  );

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
    // The reading plan widget shows the palm stage photograph from its catalog.
    expect(
      project,
      contains(
        '5E3B9D72C8F14A06B2D7E931 /* Assets.xcassets */,\n\t\t\t);\n'
        '\t\t\tpath = PrayerTimesHomeWidget;',
      ),
    );
    expect(
      project,
      contains('4D2A8C61B7E03F95A1C6D820 /* Assets.xcassets in Resources */,'),
    );
    expect(
      widget,
      contains(r'Image("reading_plan_palm_bg_\(data.palmStage)")'),
    );
    for (var stage = 0; stage <= 5; stage++) {
      final art = 'reading_plan_palm_bg_$stage';
      expect(
        File(
          'ios/PrayerTimesHomeWidget/Assets.xcassets/$art.imageset/$art.jpg',
        ).existsSync(),
        isTrue,
        reason: art,
      );
      expect(
        File('android/app/src/main/res/drawable-nodpi/$art.webp').existsSync(),
        isTrue,
        reason: art,
      );
    }
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
