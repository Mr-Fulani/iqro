import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/salah/salah_3d.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';

import 'salah_models_test.dart' show salahFixture;

// The same cases as services/web/lib/salah-3d.test.ts: both clients show the
// scene on the same steps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SalahMedia picture(String key, [Object? scene]) =>
      SalahMedia.fromJson(key, <String, Object?>{
        'url': 'https://media.iqro.forum/$key.webp',
        'width': 720,
        'height': 720,
        'scene': ?scene,
      });
  Map<String, Object?> still(String pose, [String view = 'full']) =>
      <String, Object?>{'pose': pose, 'view': view};
  SalahStep step(String slug, [String? media]) => SalahStep(
    slug: 'lesson.$slug',
    kind: 'action',
    title: slug,
    instruction: '',
    media: media,
  );

  test('a step shows the scene pose its picture is a still of', () {
    final media = <SalahMedia>[
      picture('position-qiyam', still('qiyam')),
      picture('position-ruku', still('ruku')),
      picture('position-sujud', still('sujud')),
      picture('position-jalsa', still('jalsa')),
      picture('position-taslim', still('salam')),
      picture('position-qunut'),
      picture('position-hand', still('tashahhud', 'hand')),
      picture('position-newer', still('prostration-on-a-chair')),
      picture('position-broken', <String, Object?>{'pose': 'ruku'}),
    ];
    final steps = <SalahStep>[
      step('intention', 'position-qiyam'),
      step('ruku', 'position-ruku'),
      step('sujud-1', 'position-sujud'),
      step('jalsa', 'position-jalsa'),
      step('sujud-2', 'position-sujud'),
      step('qunut', 'position-qunut'),
      step('pointing', 'position-hand'),
      step('newer', 'position-newer'),
      step('broken', 'position-broken'),
      step('taslim', 'position-taslim'),
      step('intro'),
    ];
    final document = SalahCourseDocument.fromJson(salahFixture());
    final course = SalahCourseDocument(
      schemaVersion: document.schemaVersion,
      course: document.course,
      sections: document.sections,
      lessons: document.lessons,
      formulas: document.formulas,
      media: <String, SalahMedia>{for (final item in media) item.key: item},
    );
    expect(salahStepScenes(course, steps), <SalahMediaScene?>[
      const SalahMediaScene(pose: 'qiyam'),
      const SalahMediaScene(pose: 'ruku'),
      const SalahMediaScene(pose: 'sujud'),
      const SalahMediaScene(pose: 'jalsa'),
      // the second prostration rises from the sitting between the two
      const SalahMediaScene(pose: 'sujud2'),
      null,
      const SalahMediaScene(pose: 'tashahhud', view: 'hand'),
      // a pose this build does not know, or a malformed scene, stays a picture
      null,
      null,
      const SalahMediaScene(pose: 'salam'),
      null,
    ]);
  });

  test('the controller cycles speeds and keeps the stills after a failure', () {
    final three = Salah3DController();
    expect(three.speed, 1);
    three.cycleSpeed();
    expect(three.speed, .75);
    three.cycleSpeed();
    expect(three.speed, .5);
    three.cycleSpeed();
    expect(three.speed, 1);

    three.markReady();
    expect(three.ready, isTrue);
    three.stepChanged();
    expect(three.ready, isFalse);
    three.fail();
    three.markReady();
    expect(three.failed, isTrue);
    expect(three.ready, isFalse);
    three.dispose();
  });

  test('a step plays its pose once; replay and every new step play it from '
      'the start', () {
    // As in services/web/lib/salah-3d.test.ts.
    final three = Salah3DController();
    ({bool playing, bool ended, int run}) state() =>
        (playing: three.playing, ended: three.ended, run: three.replayCount);
    expect(state(), (playing: true, ended: false, run: 0));
    expect(three.moving, isTrue);
    three.markEnded();
    expect(state(), (playing: true, ended: true, run: 0));
    expect(three.moving, isFalse);
    // play after the end is a replay
    three.togglePlaying();
    expect(state(), (playing: true, ended: false, run: 1));
    three
      ..markEnded()
      ..replay();
    expect(state(), (playing: true, ended: false, run: 2));
    // a pause holds the movement where it is, play goes on from there
    three.togglePlaying();
    expect(state(), (playing: false, ended: false, run: 2));
    expect(three.moving, isFalse);
    three.togglePlaying();
    expect(state(), (playing: true, ended: false, run: 2));
    // the next step plays its own pose, paused or ended before; its own
    // view starts it, so no replay is asked for
    three
      ..togglePlaying()
      ..stepChanged();
    expect(state(), (playing: true, ended: false, run: 2));
    three
      ..markEnded()
      ..stepChanged();
    expect(state(), (playing: true, ended: false, run: 2));
    three.dispose();
  });

  test('the offline page and its scripts are bundled', () async {
    final page = await rootBundle.loadString('assets/salah3d/index.html');
    for (final script in <String>[
      'three.min.js',
      'salah-scene.js',
      'salah-embed.js',
    ]) {
      expect(page, contains('<script src="$script"></script>'));
      expect(
        (await rootBundle.load('assets/salah3d/$script')).lengthInBytes,
        greaterThan(0),
      );
    }
    final scene = await rootBundle.loadString('assets/salah3d/salah-scene.js');
    expect(
      scene,
      startsWith('/* Generated by services/web/scripts/salah3d-app-assets.ts'),
    );
    expect(
      await rootBundle.loadString('assets/salah3d/LICENSE-three.txt'),
      contains('MIT'),
    );
  });
}
