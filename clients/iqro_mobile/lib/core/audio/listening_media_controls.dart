import 'package:audio_service/audio_service.dart';

/// The speeds the media card steps through, as the player's speed sheet lists
/// them.
const listeningMediaSpeeds = <double>[.75, 1, 1.25, 1.5, 2];

/// The speed after [speed]; an unknown speed starts over from normal.
double nextListeningMediaSpeed(double speed) {
  final index = listeningMediaSpeeds.indexOf(speed);
  if (index < 0) return 1;
  return listeningMediaSpeeds[(index + 1) % listeningMediaSpeeds.length];
}

/// How far the back and forward buttons jump.
const listeningSeekStep = Duration(seconds: 10);

/// The custom action of the speed button on Android 13 and later.
const listeningSpeedAction = 'forum.iqro.app.audio.speed';

/// The first Android whose media controls come from the session, with only
/// previous, play and next plus two custom actions on the card.
const androidSessionControlsSdk = 33;

typedef ListeningMediaLabels = ({
  String previous,
  String next,
  String play,
  String pause,
  String back10,
  String forward10,
  String Function(double speed) speed,
});

typedef ListeningMediaControls = ({
  List<MediaControl> controls,
  List<int> compact,
});

String _speedIcon(double speed) {
  final closest = listeningMediaSpeeds.reduce(
    (best, value) =>
        (value - speed).abs() < (best - speed).abs() ? value : best,
  );
  final code = (closest * 100).round().toString().padLeft(3, '0');
  return 'drawable/iqro_media_speed_$code';
}

/// The buttons of the Audio tab's media card, lock screen and Now Playing.
///
/// Android before 13 draws the notification's own actions, at most five of
/// them and three when folded: back 10 s, previous surah, play/pause, next
/// surah and speed. Forward 10 s has no room: the seek bar jumps ahead. A
/// speed button there can only send a media key, so it rides on the stop key
/// ([speedOnStop]); stopping is pausing in this app anyway. Android 13 and
/// later draw previous, play and next themselves and fill two more slots with
/// the first custom actions, the same speed and back 10 s. iOS maps the
/// commands to Now Playing and changes the speed through its own rate command.
ListeningMediaControls listeningMediaControls({
  required bool playing,
  required bool canSkip,
  required double speed,
  required int? androidSdk,
  required ListeningMediaLabels labels,
}) {
  final playPause = playing
      ? MediaControl.pause.copyWith(label: labels.pause)
      : MediaControl.play.copyWith(label: labels.play);
  final back = MediaControl.rewind.copyWith(
    androidIcon: 'drawable/iqro_media_replay_10',
    label: labels.back10,
  );
  final forward = MediaControl.fastForward.copyWith(
    androidIcon: 'drawable/iqro_media_forward_10',
    label: labels.forward10,
  );
  // Another section owns the decoder: the card only resumes the Audio tab.
  if (!canSkip) {
    return (controls: <MediaControl>[playPause], compact: const <int>[0]);
  }
  final previous = MediaControl.skipToPrevious.copyWith(label: labels.previous);
  final next = MediaControl.skipToNext.copyWith(label: labels.next);
  final sdk = androidSdk;
  if (sdk == null) {
    return (
      controls: <MediaControl>[previous, back, playPause, forward, next],
      compact: const <int>[0, 2, 4],
    );
  }
  if (sdk >= androidSessionControlsSdk) {
    return (
      controls: <MediaControl>[
        previous,
        playPause,
        next,
        MediaControl.custom(
          androidIcon: _speedIcon(speed),
          label: labels.speed(speed),
          name: listeningSpeedAction,
        ),
        back,
        forward,
      ],
      compact: const <int>[0, 1, 2],
    );
  }
  return (
    controls: <MediaControl>[
      back,
      previous,
      playPause,
      next,
      MediaControl.stop.copyWith(
        androidIcon: _speedIcon(speed),
        label: labels.speed(speed),
      ),
    ],
    compact: const <int>[1, 2, 3],
  );
}

/// Whether the stop key changes the speed: the legacy Android card, where the
/// speed button can only send it.
bool speedOnStop(int? androidSdk) =>
    androidSdk != null && androidSdk < androidSessionControlsSdk;
