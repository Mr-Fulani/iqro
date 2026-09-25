import 'package:audio_service/audio_service.dart';

/// Android's media card belongs to the Audio tab, even while another section
/// uses the app's shared decoder. Contextual audio never publishes its item.
class ListeningMediaService extends BaseAudioHandler with SeekHandler {
  ListeningMediaService();

  static ListeningMediaService? current;

  Object? _owner;
  Future<void> Function()? _play;
  Future<void> Function()? _pause;
  Future<void> Function(Duration)? _seek;

  static Future<void> initialize() async {
    current = await AudioService.init<ListeningMediaService>(
      builder: ListeningMediaService.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'forum.iqro.app.audio',
        androidNotificationChannelName: 'IQRO Quran audio',
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
