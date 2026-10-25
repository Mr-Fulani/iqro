import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/audio/premium_reciter_portrait.dart';

/// Android's media card belongs to the Audio tab, even while another section
/// uses the app's shared decoder. Contextual audio never publishes its item.
/// A reciter without a portrait shows the app's default figure, from a local
/// file so the lock screen has it offline too.
class ListeningMediaService extends BaseAudioHandler with SeekHandler {
  ListeningMediaService({this.defaultArtwork});

  final Uri? defaultArtwork;

  static ListeningMediaService? current;

  Object? _owner;
  Future<void> Function()? _play;
  Future<void> Function()? _pause;
  Future<void> Function(Duration)? _seek;
  Future<void> Function()? _skipToNext;
  Future<void> Function()? _skipToPrevious;

  static Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    final artwork = File('${directory.path}/iqro-reciter-default-v1.webp');
    if (!await artwork.exists()) {
      final data = await rootBundle.load(defaultReciterPortraitAsset);
      await artwork.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    // The brand seal shown before the default figure.
    final legacy = File('${directory.path}/iqro-media-seal-v1.png');
    if (await legacy.exists()) await legacy.delete();
    current = await AudioService.init<ListeningMediaService>(
      builder: () => ListeningMediaService(defaultArtwork: artwork.uri),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'forum.iqro.app.audio',
        androidNotificationChannelName: 'IQRO Quran audio',
        androidNotificationIcon: 'drawable/iqro_status_icon',
        androidStopForegroundOnPause: false,
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
  }) {
    _owner = owner;
    _play = play;
    _pause = pause;
    _seek = seek;
    _skipToNext = skipToNext;
    _skipToPrevious = skipToPrevious;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _play = null;
    _pause = null;
    _seek = null;
    _skipToNext = null;
    _skipToPrevious = null;
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
    final controls = item == null
        ? const <MediaControl>[]
        : canSkip
        ? <MediaControl>[
            MediaControl.skipToPrevious,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ]
        : <MediaControl>[playing ? MediaControl.pause : MediaControl.play];
    final previousState = playbackState.value;
    if (previousState.processingState == processingState &&
        previousState.controls.length == controls.length &&
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
        controls: controls,
        androidCompactActionIndices: item == null
            ? null
            : canSkip
            ? const <int>[0, 1, 2]
            : const <int>[0],
        systemActions: item == null
            ? const <MediaAction>{}
            : const <MediaAction>{MediaAction.seek},
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
  Future<void> stop() async => await _pause?.call();
}
