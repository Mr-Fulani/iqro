// Renders the palm stages for the Android and iOS home-screen widgets from the
// same PalmPainter the app uses, so all of them always show the same art.
//
//   flutter test tool/render_palm_widget_art.dart
//
// Set PALM_PREVIEW=<dir> to also write every stage and mood for review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/plan/palm_growth.dart';
import 'package:iqro_mobile/features/plan/palm_growth_view.dart';

const _size = 192;

void main() {
  testWidgets('render palm widget art', (tester) async {
    await tester.runAsync(() async {
      for (final stage in PalmStage.values) {
        // The home widget has no moods: today's state is shown in numbers.
        final name = 'reading_plan_palm_${stage.index}';
        final android = 'android/app/src/main/res/drawable-nodpi/$name.png';
        await _write(android, stage, PalmMood.growing, celestial: false);
        File(android).copySync(
          'ios/PrayerTimesHomeWidget/Assets.xcassets/$name.imageset/$name.png',
        );
      }
      final preview = Platform.environment['PALM_PREVIEW'];
      if (preview == null) return;
      for (final stage in PalmStage.values) {
        for (final mood in PalmMood.values) {
          await _write(
            '$preview/${stage.name}_${mood.name}.png',
            stage,
            mood,
            celestial: true,
          );
        }
      }
    });
  });
}

Future<void> _write(
  String path,
  PalmStage stage,
  PalmMood mood, {
  required bool celestial,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PalmPainter(
    stage: stage,
    mood: mood,
    celestial: celestial,
  ).paint(canvas, const Size.square(_size + 0.0));
  final image = await recorder.endRecording().toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}
