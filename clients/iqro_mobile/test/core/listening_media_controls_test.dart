import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/listening_media_controls.dart';

const ListeningMediaLabels _labels = (
  previous: 'Предыдущая сура',
  next: 'Следующая сура',
  play: 'Воспроизвести',
  pause: 'Пауза',
  back10: 'Назад на 10 секунд',
  forward10: 'Вперёд на 10 секунд',
  speed: _speedLabel,
);

String _speedLabel(double speed) => 'Скорость $speed×';

ListeningMediaControls _layout({
  bool playing = true,
  bool canSkip = true,
  double speed = 1,
  int? androidSdk,
}) => listeningMediaControls(
  playing: playing,
  canSkip: canSkip,
  speed: speed,
  androidSdk: androidSdk,
  labels: _labels,
);

List<MediaAction> _actions(ListeningMediaControls layout) =>
    layout.controls.map((control) => control.action).toList();

void main() {
  test('the speed button steps through the player sheet speeds', () {
    expect(listeningMediaSpeeds, <double>[.75, 1, 1.25, 1.5, 2]);
    expect(nextListeningMediaSpeed(.75), 1);
    expect(nextListeningMediaSpeed(1.5), 2);
    expect(nextListeningMediaSpeed(2), .75);
    // A speed set elsewhere starts the cycle over from normal.
    expect(nextListeningMediaSpeed(1.1), 1);
  });

  test('Android before 13 fills its five buttons, speed on the stop key', () {
    final layout = _layout(androidSdk: 29, speed: 1.25);
    // The notification shows five actions at most: no room for forward 10 s.
    expect(_actions(layout), <MediaAction>[
      MediaAction.rewind,
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.stop,
    ]);
    expect(layout.compact, <int>[1, 2, 3]);
    final speed = layout.controls.last;
    expect(speed.androidIcon, 'drawable/iqro_media_speed_125');
    expect(speed.label, 'Скорость 1.25×');
    expect(layout.controls.first.androidIcon, 'drawable/iqro_media_replay_10');
    expect(speedOnStop(29), isTrue);
  });

  test('Android 13 and later put speed and back 10 s in the custom slots', () {
    final layout = _layout(androidSdk: 34, playing: false, speed: .75);
    expect(_actions(layout), <MediaAction>[
      MediaAction.skipToPrevious,
      MediaAction.play,
      MediaAction.skipToNext,
      MediaAction.custom,
      MediaAction.rewind,
      MediaAction.fastForward,
    ]);
    final speed = layout.controls[3];
    expect(speed.customAction?.name, listeningSpeedAction);
    expect(speed.androidIcon, 'drawable/iqro_media_speed_075');
    expect(speedOnStop(34), isFalse);
  });

  test('off Android the card has surahs and ten-second steps', () {
    final layout = _layout();
    expect(_actions(layout), <MediaAction>[
      MediaAction.skipToPrevious,
      MediaAction.rewind,
      MediaAction.pause,
      MediaAction.fastForward,
      MediaAction.skipToNext,
    ]);
    expect(speedOnStop(null), isFalse);
  });

  test('while another section owns the decoder only play stays', () {
    final layout = _layout(canSkip: false, playing: false, androidSdk: 29);
    expect(_actions(layout), <MediaAction>[MediaAction.play]);
    expect(layout.compact, <int>[0]);
  });

  test('every speed has its own icon', () {
    for (final speed in listeningMediaSpeeds) {
      final icon = _layout(androidSdk: 29, speed: speed).controls.last;
      final name = icon.androidIcon.replaceFirst('drawable/', '');
      expect(
        File(
          'android/app/src/main/res/drawable-xxxhdpi/$name.png',
        ).existsSync(),
        isTrue,
        reason: name,
      );
    }
    expect(
      _layout(androidSdk: 29, speed: 1.3).controls.last.androidIcon,
      'drawable/iqro_media_speed_125',
    );
  });
}
