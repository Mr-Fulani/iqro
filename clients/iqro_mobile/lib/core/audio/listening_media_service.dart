import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'listening_media_controls.dart';

/// Android's media card belongs to the Audio tab, even while another section
/// uses the app's shared decoder. Contextual audio never publishes its item.
class ListeningMediaService extends BaseAudioHandler with SeekHandler {
  ListeningMediaService({this.defaultArtwork, this.androidSdk});

  final Uri? defaultArtwork;

  /// The Android release the card is drawn for; null off Android. It decides
  /// which buttons fit (see [listeningMediaControls]).
  final int? androidSdk;

  static ListeningMediaService? current;

  Object? _owner;
  Future<void> Function()? _play;
  Future<void> Function()? _pause;
  Future<void> Function(Duration)? _seek;
  Future<void> Function()? _skipToNext;
  Future<void> Function()? _skipToPrevious;
  Future<void> Function(double)? _setSpeed;
  ListeningMediaLabels Function()? _labels;

  static Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    final artwork = File('${directory.path}/iqro-media-seal-v1.png');
    if (!await artwork.exists()) {
      final data = await rootBundle.load('assets/brand/iqro-media-logo.png');
      await artwork.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    final androidSdk = Platform.isAndroid
        ? (await DeviceInfoPlugin().androidInfo).version.sdkInt
        : null;
    current = await AudioService.init<ListeningMediaService>(
      builder: () => ListeningMediaService(
        defaultArtwork: artwork.uri,
        androidSdk: androidSdk,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'forum.iqro.app.audio',
        androidNotificationChannelName: 'IQRO Quran audio',
        androidNotificationIcon: 'drawable/iqro_status_icon',
        androidStopForegroundOnPause: false,
        // iOS Now Playing shows these as its skip buttons.
        fastForwardInterval: listeningSeekStep,
        rewindInterval: listeningSeekStep,
      ),
    );
  }

  void bind(
    Object owner, {
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function(Duration) seek,
    Future<void> Function()? skipToNext,
    Future<void> Function()? skipToPrevious,
    Future<void> Function(double)? setSpeed,
    ListeningMediaLabels Function()? labels,
  }) {
    _owner = owner;
    _play = play;
    _pause = pause;
    _seek = seek;
    _skipToNext = skipToNext;
    _skipToPrevious = skipToPrevious;
    _setSpeed = setSpeed;
    _labels = labels;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _play = null;
    _pause = null;
    _seek = null;
    _skipToNext = null;
    _skipToPrevious = null;
    _setSpeed = null;
    _labels = null;
    publish(item: null);
  }

  void publish({
    required MediaItem? item,
    bool playing = false,
    bool buffering = false,
    Duration position = Duration.zero,
    double speed = 1,
    bool canSkip = false,
  }) {
    if (item != null && item.artUri == null && defaultArtwork != null) {
      item = item.copyWith(artUri: defaultArtwork);
    }
    final previousItem = mediaItem.value;
    if (previousItem?.id != item?.id ||
        previousItem?.title != item?.title ||
        previousItem?.artist != item?.artist ||
        previousItem?.artUri != item?.artUri ||
        previousItem?.duration != item?.duration) {
      mediaItem.add(item);
    }
    final processingState = item == null
        ? AudioProcessingState.idle
        : buffering
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready;
    // The surah buttons only while the Audio tab owns the decoder: they
    // switch surahs of its queue, never ayahs or another section's audio.
    final layout = item == null
        ? (controls: const <MediaControl>[], compact: const <int>[])
        : listeningMediaControls(
            playing: playing,
            canSkip: canSkip,
            speed: speed,
            androidSdk: androidSdk,
            labels: _labels?.call() ?? _englishLabels,
          );
    final previousState = playbackState.value;
    if (previousState.processingState == processingState &&
        listEquals(previousState.controls, layout.controls) &&
        previousState.playing == (item != null && playing) &&
        previousState.speed == speed &&
        (previousState.position - position).abs() <
            const Duration(seconds: 2)) {
      return;
    }
    playbackState.add(
      PlaybackState(
        processingState: processingState,
        playing: item != null && playing,
        controls: layout.controls,
        androidCompactActionIndices: item == null ? null : layout.compact,
        // A draggable seek bar, and the rate command of iOS Now Playing.
        systemActions: item == null
            ? const <MediaAction>{}
            : const <MediaAction>{MediaAction.seek, MediaAction.setSpeed},
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  @override
  Future<void> play() async => await _play?.call();

  @override
  Future<void> pause() async => await _pause?.call();

  @override
  Future<void> seek(Duration position) async => await _seek?.call(position);

  @override
  Future<void> skipToNext() async => await _skipToNext?.call();

  @override
  Future<void> skipToPrevious() async => await _skipToPrevious?.call();

  @override
  Future<void> rewind() => _seekBy(-listeningSeekStep);

  @override
  Future<void> fastForward() => _seekBy(listeningSeekStep);

  /// A jump from where the card shows the sound, kept inside the track.
  Future<void> _seekBy(Duration offset) async {
    final duration = mediaItem.value?.duration;
    var target = playbackState.value.position + offset;
    if (target.isNegative) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _seek?.call(target);
  }

  @override
  Future<void> setSpeed(double speed) async => await _setSpeed?.call(speed);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == listeningSpeedAction) await _cycleSpeed();
  }

  /// The legacy card's speed button sends the stop key; anything else that
  /// stops only pauses, as before.
  @override
  Future<void> stop() async {
    if (speedOnStop(androidSdk) && _setSpeed != null) {
      await _cycleSpeed();
    } else {
      await _pause?.call();
    }
  }

  /// Swiping the card away pauses; it never stands for the speed button.
  @override
  Future<void> onNotificationDeleted() async => await _pause?.call();

  Future<void>? _speedChange;

  /// One press, one step: a press that arrives while the last change is still
  /// applying is the same press delivered twice.
  Future<void> _cycleSpeed() async {
    final setSpeed = _setSpeed;
    if (setSpeed == null || _speedChange != null) return;
    final change = setSpeed(nextListeningMediaSpeed(playbackState.value.speed));
    _speedChange = change;
    try {
      await change;
    } finally {
      _speedChange = null;
    }
  }
}

const ListeningMediaLabels _englishLabels = (
  previous: 'Previous surah',
  next: 'Next surah',
  play: 'Play',
  pause: 'Pause',
  back10: 'Back 10 seconds',
  forward10: 'Forward 10 seconds',
  speed: _englishSpeed,
);

String _englishSpeed(double speed) => 'Speed ${speed}x';
