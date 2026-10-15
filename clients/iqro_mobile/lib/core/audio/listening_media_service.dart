import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Android's media card belongs to the Audio tab, even while another section
/// uses the app's shared decoder. Contextual audio never publishes its item.
class ListeningMediaService extends BaseAudioHandler with SeekHandler {
  ListeningMediaService({this.defaultArtwork});

  final Uri? defaultArtwork;

  static ListeningMediaService? current;

  Object? _owner;
  Future<void> Function()? _play;
  Future<void> Function()? _pause;
  Future<void> Function(Duration)? _seek;

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
  }) {
    _owner = owner;
    _play = play;
    _pause = pause;
    _seek = seek;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _play = null;
    _pause = null;
    _seek = null;
    publish(item: null);
  }

  void publish({
    required MediaItem? item,
    bool playing = false,
    bool buffering = false,
    Duration position = Duration.zero,
    double speed = 1,
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
    final previousState = playbackState.value;
    if (previousState.processingState == processingState &&
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
        controls: item == null
            ? const <MediaControl>[]
            : <MediaControl>[playing ? MediaControl.pause : MediaControl.play],
        androidCompactActionIndices: item == null ? null : const <int>[0],
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
  Future<void> stop() async => await _pause?.call();
}
