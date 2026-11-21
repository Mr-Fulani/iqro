import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/recitation_follow.dart';
import 'package:iqro_mobile/features/quran/recitation_model/follow_core.dart';
import 'package:iqro_mobile/features/quran/recitation_model/model_listener.dart';
import 'package:iqro_mobile/features/quran/recitation_model/pipeline.dart';

/// Frames of the model: a sound on every [every]th, nothing on the rest.
Float32List _frames(int count, {int? every}) {
  final lp = Float32List(count * recitationClasses)
    ..fillRange(0, count * recitationClasses, -20);
  for (var t = 0; t < count; t++) {
    final sound = every != null && t % every == 0;
    lp[t * recitationClasses + (sound ? 1 + t % 28 : 0)] = -.01;
  }
  return lp;
}

void main() {
  const long = 9000; // longer than recitationDeafAfter

  test('a loud reader whose word is not taken is not told to read louder', () {
    final ear = modelEar(heard: 'كلمة', sinceMs: long, sounds: 40);
    expect(ear.deaf, isFalse);
    expect(ear.trouble, RecitationTrouble.unrecognised);
  });

  test('a reader the model hears nothing of is told so', () {
    final ear = modelEar(heard: '', sinceMs: long, sounds: 0);
    expect(ear.deaf, isTrue);
    expect(ear.trouble, isNull);
    // A sound now and then is a room's noise, not reading.
    expect(modelEar(heard: '', sinceMs: long, sounds: 3).deaf, isTrue);
  });

  test('while words are taken the line shows them, however loud', () {
    for (final sounds in <int>[0, 40]) {
      final ear = modelEar(heard: 'كلمة', sinceMs: 500, sounds: sounds);
      expect(ear.deaf, isFalse);
      expect(ear.trouble, isNull);
      expect(ear.heard, 'كلمة');
    }
  });

  test('the sounds heard lately are counted in the last eight seconds', () {
    // Reading: a sound every tenth of a second.
    final reading = _frames(600, every: 5);
    expect(
      soundsHeard(reading, 600, recitationEarFrames),
      greaterThan(recitationSpokenSounds),
    );
    // Silence, though the reader read before it.
    final silent = Float32List(1000 * recitationClasses)
      ..setAll(0, reading)
      ..setAll(600 * recitationClasses, _frames(400));
    expect(soundsHeard(silent, 1000, recitationEarFrames), 0);
    // A sound held is one sound.
    final held = _frames(100);
    for (var t = 10; t < 60; t++) {
      held[t * recitationClasses] = -20;
      held[t * recitationClasses + 7] = -.01;
    }
    expect(soundsHeard(held, 100, recitationEarFrames), 1);
    // What the model is not sure of (a room's noise) is no reading.
    final unsure = _frames(600);
    for (var t = 0; t < 600; t += 5) {
      unsure[t * recitationClasses] = -1.5;
      unsure[t * recitationClasses + 9] = -1.2;
    }
    expect(soundsHeard(unsure, 600, recitationEarFrames), 0);
  });
}
