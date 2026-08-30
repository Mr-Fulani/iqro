import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/audio/audio_models.dart';

class IqroAudioState {
  const IqroAudioState({
    this.track,
    this.reciter,
    this.surahName = '',
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.repeatEnabled = false,
    this.sleepTimerMinutes,
    this.error,
  });

  final AudioTrack? track;
  final Reciter? reciter;
  final String surahName;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double speed;
  final bool repeatEnabled;
  final int? sleepTimerMinutes;
  final String? error;

  bool get active => track != null;

  IqroAudioState copyWith({
    AudioTrack? track,
    Reciter? reciter,
    String? surahName,
    bool? playing,
    bool? buffering,
    Duration? position,
    Duration? duration,
    double? speed,
    bool? repeatEnabled,
    int? sleepTimerMinutes,
    String? error,
    bool clearError = false,
    bool clearSleepTimer = false,
  }) {
    return IqroAudioState(
      track: track ?? this.track,
      reciter: reciter ?? this.reciter,
      surahName: surahName ?? this.surahName,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      repeatEnabled: repeatEnabled ?? this.repeatEnabled,
      sleepTimerMinutes: clearSleepTimer
          ? null
          : sleepTimerMinutes ?? this.sleepTimerMinutes,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AudioController extends StateNotifier<IqroAudioState> {
  AudioController({AudioPlayer? player})
    : _player = player ?? AudioPlayer(),
      super(const IqroAudioState()) {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        state = state.copyWith(
          playing: playerState.playing,
          buffering:
              playerState.processingState == ProcessingState.loading ||
              playerState.processingState == ProcessingState.buffering,
        );
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        state = state.copyWith(position: position);
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (duration != null) state = state.copyWith(duration: duration);
      }),
    );
  }

  final AudioPlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _sleepTimer;

  Future<void> load({
    required AudioTrack track,
    required Reciter reciter,
    required String surahName,
    bool autoplay = true,
  }) async {
    try {
      if (state.reciter?.id != null && state.reciter?.id != reciter.id) {
        await _player.stop();
      }
      state = IqroAudioState(
        track: track,
        reciter: reciter,
        surahName: surahName,
        buffering: true,
        duration: track.duration,
        speed: state.speed,
        repeatEnabled: state.repeatEnabled,
        sleepTimerMinutes: state.sleepTimerMinutes,
      );
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(track.url),
          tag: MediaItem(
            id: track.id,
            album: 'IQRO · Quran',
            title: surahName,
            artist: reciter.nameEn,
            duration: track.duration == Duration.zero ? null : track.duration,
            artUri: reciter.portraitUrl == null
                ? null
                : Uri.tryParse(reciter.portraitUrl!),
          ),
        ),
      );
      await _player.setSpeed(state.speed);
      await _player.setLoopMode(
        state.repeatEnabled ? LoopMode.one : LoopMode.off,
      );
      if (autoplay) await _player.play();
    } on Object catch (error) {
      state = state.copyWith(
        playing: false,
        buffering: false,
        error: error.toString(),
      );
    }
  }

  Future<void> toggle() => _player.playing ? _player.pause() : _player.play();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  Future<void> toggleRepeat() async {
    final enabled = !state.repeatEnabled;
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    state = state.copyWith(repeatEnabled: enabled);
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }
    state = state.copyWith(sleepTimerMinutes: duration.inMinutes);
    _sleepTimer = Timer(duration, () async {
      await _player.pause();
      state = state.copyWith(clearSleepTimer: true);
    });
  }

  Future<void> stop() async {
    _sleepTimer?.cancel();
    await _player.stop();
    state = const IqroAudioState();
  }

  @override
  Future<void> dispose() async {
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    super.dispose();
  }
}
