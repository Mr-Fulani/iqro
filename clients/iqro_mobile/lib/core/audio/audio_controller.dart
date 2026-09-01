import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/audio/audio_models.dart';
import 'audio_playback_store.dart';

@visibleForTesting
AudioSource buildIqroAudioSource({
  required AudioTrack track,
  required MediaItem mediaItem,
  Duration? start,
  Duration? end,
}) {
  final source = AudioSource.uri(Uri.parse(track.url), tag: mediaItem);
  if (start == null && end == null) return source;
  final clippedDuration = start != null && end != null && end >= start
      ? end - start
      : null;
  return ClippingAudioSource(
    child: source,
    start: start,
    end: end,
    tag: mediaItem,
    duration: clippedDuration,
  );
}

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
    this.segments = const <AudioSegment>[],
    this.activeAyah,
    this.rangeStartAyah,
    this.rangeEndAyah,
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
  final List<AudioSegment> segments;
  final int? activeAyah;
  final int? rangeStartAyah;
  final int? rangeEndAyah;
  final String? error;

  bool get active => track != null;

  AudioSegment? segmentForAyah(int? ayah) {
    if (ayah == null) return null;
    for (final segment in segments) {
      if (segment.ayah == ayah) return segment;
    }
    return null;
  }

  Duration get rangeStartPosition =>
      segmentForAyah(rangeStartAyah)?.start ?? Duration.zero;

  Duration get rangeEndPosition =>
      segmentForAyah(rangeEndAyah)?.end ?? duration;

  Duration get effectiveDuration {
    final value = rangeEndPosition - rangeStartPosition;
    return value.isNegative ? Duration.zero : value;
  }

  Duration get relativePosition {
    final milliseconds = (position - rangeStartPosition).inMilliseconds.clamp(
      0,
      effectiveDuration.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds.toInt());
  }

  bool get hasActiveRange => rangeStartAyah != null && rangeEndAyah != null;

  Duration logicalPositionForPlayer(Duration playerPosition) =>
      hasActiveRange ? rangeStartPosition + playerPosition : playerPosition;

  Duration playerPositionForLogical(Duration logicalPosition) {
    if (!hasActiveRange) return logicalPosition;
    final milliseconds = (logicalPosition - rangeStartPosition).inMilliseconds
        .clamp(0, effectiveDuration.inMilliseconds);
    return Duration(milliseconds: milliseconds.toInt());
  }

  int? get displayedAyah => activeAyah ?? rangeEndAyah ?? rangeStartAyah;

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
    List<AudioSegment>? segments,
    int? activeAyah,
    int? rangeStartAyah,
    int? rangeEndAyah,
    String? error,
    bool clearError = false,
    bool clearSleepTimer = false,
    bool clearActiveAyah = false,
    bool clearRange = false,
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
      segments: segments ?? this.segments,
      activeAyah: clearActiveAyah ? null : activeAyah ?? this.activeAyah,
      rangeStartAyah: clearRange ? null : rangeStartAyah ?? this.rangeStartAyah,
      rangeEndAyah: clearRange ? null : rangeEndAyah ?? this.rangeEndAyah,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AudioController extends StateNotifier<IqroAudioState> {
  AudioController({AudioPlayer? player, AudioPlaybackStore? playbackStore})
    : _player = player ?? AudioPlayer(),
      _playbackStore = playbackStore,
      super(const IqroAudioState()) {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        final completed =
            playerState.processingState == ProcessingState.completed;
        state = state.copyWith(
          playing: playerState.playing && !completed,
          buffering:
              playerState.processingState == ProcessingState.loading ||
              playerState.processingState == ProcessingState.buffering,
        );
        if (completed && playerState.playing) {
          unawaited(_player.pause());
        }
        _schedulePersistence(immediate: completed || !playerState.playing);
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        final logicalPosition = state.logicalPositionForPlayer(position);
        final beforeRange =
            state.hasActiveRange && logicalPosition < state.rangeStartPosition;
        final completedRange =
            state.hasActiveRange && logicalPosition >= state.rangeEndPosition;
        final activeSegment = beforeRange || completedRange
            ? null
            : _segmentAt(state.segments, logicalPosition);
        final completedRangeAyah = completedRange ? state.rangeEndAyah : null;
        state = state.copyWith(
          position: logicalPosition,
          activeAyah: activeSegment?.ayah ?? completedRangeAyah,
          clearActiveAyah: activeSegment == null && completedRangeAyah == null,
        );
        _schedulePersistence();
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (duration != null && state.track?.duration == Duration.zero) {
          state = state.copyWith(duration: duration);
          _schedulePersistence();
        }
      }),
    );
  }

  AudioSegment? _segmentAt(List<AudioSegment> segments, Duration position) {
    var low = 0;
    var high = segments.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final segment = segments[middle];
      if (position < segment.start) {
        high = middle - 1;
      } else if (position >= segment.end) {
        low = middle + 1;
      } else {
        return segment;
      }
    }
    return null;
  }

  final AudioPlayer _player;
  final AudioPlaybackStore? _playbackStore;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _sleepTimer;
  Timer? _persistenceTimer;
  var _disposed = false;
  var _restoreStarted = false;
  var _restoring = false;

  Future<void> restore() async {
    if (_restoreStarted || _playbackStore == null) return;
    _restoreStarted = true;
    _restoring = true;
    try {
      final snapshot = await _playbackStore.read();
      if (snapshot == null || _disposed || state.active) return;
      state = state.copyWith(
        speed: snapshot.speed,
        repeatEnabled: snapshot.repeatEnabled,
      );
      await loadPlayback(
        playback: snapshot.playback,
        reciter: snapshot.reciter,
        surahName: snapshot.surahName,
        startAyah: snapshot.rangeStartAyah,
        endAyah: snapshot.rangeEndAyah,
        autoplay: false,
      );
      if (_disposed) return;
      final playerPosition = state.playerPositionForLogical(snapshot.position);
      await _player.seek(playerPosition);
      if (_disposed) return;
      final logicalPosition = state.logicalPositionForPlayer(playerPosition);
      state = state.copyWith(
        playing: false,
        buffering: false,
        position: logicalPosition,
        activeAyah: _segmentAt(state.segments, logicalPosition)?.ayah,
        clearActiveAyah: _segmentAt(state.segments, logicalPosition) == null,
        clearError: true,
      );
    } on Object {
      try {
        await _playbackStore.clear();
      } on Object {
        // A broken local store must not prevent the app from starting.
      }
      if (!_disposed) state = const IqroAudioState();
    } finally {
      _restoring = false;
    }
  }

  Future<void> load({
    required AudioTrack track,
    required Reciter reciter,
    required String surahName,
    bool autoplay = true,
  }) async {
    await loadPlayback(
      playback: SurahPlayback(track: track, segments: const <AudioSegment>[]),
      reciter: reciter,
      surahName: surahName,
      autoplay: autoplay,
    );
  }

  Future<void> loadPlayback({
    required SurahPlayback playback,
    required Reciter reciter,
    required String surahName,
    int? startAyah,
    int? endAyah,
    bool autoplay = true,
  }) async {
    final track = playback.track;
    final startSegment = startAyah == null
        ? null
        : playback.segmentFor(startAyah);
    final endSegment = endAyah == null
        ? startSegment
        : playback.segmentFor(endAyah);
    if (startAyah != null && startSegment == null) {
      throw StateError('Ayah $startAyah has no audio timing');
    }
    if (endAyah != null && endSegment == null) {
      throw StateError('Ayah $endAyah has no audio timing');
    }
    try {
      final mediaItem = _mediaItemFor(
        track: track,
        reciter: reciter,
        surahName: surahName,
        startAyah: startSegment?.ayah,
        endAyah: endSegment?.ayah,
        clipStart: startSegment?.start,
        clipEnd: endSegment?.end,
      );
      if (_player.playing) await _player.pause();
      state = IqroAudioState(
        track: track,
        reciter: reciter,
        surahName: surahName,
        buffering: true,
        duration: track.duration,
        speed: state.speed,
        repeatEnabled: state.repeatEnabled,
        sleepTimerMinutes: state.sleepTimerMinutes,
        segments: playback.segments,
        position: startSegment?.start ?? Duration.zero,
        activeAyah: startSegment?.ayah,
        rangeStartAyah: startSegment?.ayah,
        rangeEndAyah: endSegment?.ayah,
      );
      await _player.setAudioSource(
        buildIqroAudioSource(
          track: track,
          mediaItem: mediaItem,
          start: startSegment?.start,
          end: endSegment?.end,
        ),
      );
      await _player.setSpeed(state.speed);
      await _player.setLoopMode(
        state.repeatEnabled ? LoopMode.one : LoopMode.off,
      );
      _schedulePersistence(immediate: true);
      if (autoplay) _startPlayback();
    } on Object catch (error) {
      state = state.copyWith(
        playing: false,
        buffering: false,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> toggle() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.pause();
      await _player.seek(Duration.zero);
      _startPlayback();
      return;
    }
    if (_player.playing) {
      await _player.pause();
      _schedulePersistence(immediate: true);
      return;
    }
    _startPlayback();
  }

  void _startPlayback() {
    unawaited(
      _player.play().catchError((Object error) {
        if (_disposed) return;
        state = state.copyWith(
          playing: false,
          buffering: false,
          error: error.toString(),
        );
      }),
    );
  }

  MediaItem _mediaItemFor({
    required AudioTrack track,
    required Reciter reciter,
    required String surahName,
    int? startAyah,
    int? endAyah,
    Duration? clipStart,
    Duration? clipEnd,
  }) {
    final clipDuration =
        clipStart != null && clipEnd != null && clipEnd > clipStart
        ? clipEnd - clipStart
        : null;
    final rangeLabel = startAyah == null
        ? ''
        : startAyah == endAyah || endAyah == null
        ? ' · $startAyah'
        : ' · $startAyah–$endAyah';
    return MediaItem(
      id: startAyah == null
          ? track.id
          : '${track.id}:$startAyah-${endAyah ?? startAyah}',
      album: 'IQRO · Quran',
      title: '$surahName$rangeLabel',
      artist: reciter.nameEn,
      duration:
          clipDuration ??
          (track.duration == Duration.zero ? null : track.duration),
      artUri: reciter.portraitUrl == null
          ? null
          : Uri.tryParse(reciter.portraitUrl!),
    );
  }

  Future<void> seek(Duration position) =>
      _player.seek(state.playerPositionForLogical(position));

  Future<void> seekInActiveRange(Duration relativePosition) {
    final clamped = relativePosition.inMilliseconds.clamp(
      0,
      state.effectiveDuration.inMilliseconds,
    );
    return _player.seek(Duration(milliseconds: clamped.toInt()));
  }

  Future<void> skipAyah(int delta) async {
    if (state.segments.isEmpty) {
      return seekInActiveRange(
        state.relativePosition + Duration(seconds: 30 * delta),
      );
    }
    final start = state.rangeStartAyah ?? state.segments.first.ayah;
    final end = state.rangeEndAyah ?? state.segments.last.ayah;
    final current = state.displayedAyah ?? start;
    final target = (current + delta).clamp(start, end);
    final segment = state.segmentForAyah(target);
    if (segment != null) {
      await _player.seek(state.playerPositionForLogical(segment.start));
    }
  }

  Future<void> setAyahRange(
    int startAyah,
    int endAyah, {
    bool autoplay = true,
  }) async {
    if (startAyah > endAyah) {
      throw ArgumentError('The start ayah must not be after the end ayah');
    }
    final start = state.segmentForAyah(startAyah);
    final end = state.segmentForAyah(endAyah);
    if (start == null || end == null) {
      throw StateError('The selected ayah range has no audio timings');
    }
    final track = state.track;
    final reciter = state.reciter;
    if (track == null || reciter == null) {
      throw StateError('No audio track is loaded');
    }
    if (_player.playing) await _player.pause();
    state = state.copyWith(
      buffering: true,
      position: start.start,
      activeAyah: start.ayah,
      rangeStartAyah: start.ayah,
      rangeEndAyah: end.ayah,
      clearError: true,
    );
    await _player.setAudioSource(
      buildIqroAudioSource(
        track: track,
        mediaItem: _mediaItemFor(
          track: track,
          reciter: reciter,
          surahName: state.surahName,
          startAyah: start.ayah,
          endAyah: end.ayah,
          clipStart: start.start,
          clipEnd: end.end,
        ),
        start: start.start,
        end: end.end,
      ),
    );
    await _player.setSpeed(state.speed);
    await _player.setLoopMode(
      state.repeatEnabled ? LoopMode.one : LoopMode.off,
    );
    _schedulePersistence(immediate: true);
    if (autoplay) _startPlayback();
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    state = state.copyWith(speed: speed);
    _schedulePersistence(immediate: true);
  }

  void updateReciterMetadata(Reciter reciter, {String? currentReciterId}) {
    if (state.reciter?.id != (currentReciterId ?? reciter.id)) return;
    state = state.copyWith(reciter: reciter);
    _schedulePersistence(immediate: true);
  }

  Future<void> toggleRepeat() async {
    final enabled = !state.repeatEnabled;
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
    state = state.copyWith(repeatEnabled: enabled);
    _schedulePersistence(immediate: true);
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
    _persistenceTimer?.cancel();
    await _player.stop();
    state = const IqroAudioState();
    await _playbackStore?.clear();
  }

  void _schedulePersistence({bool immediate = false}) {
    if (_disposed || _restoring || _playbackStore == null || !state.active) {
      return;
    }
    _persistenceTimer?.cancel();
    if (immediate) {
      unawaited(_persistCurrent());
      return;
    }
    _persistenceTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_persistCurrent()),
    );
  }

  Future<void> _persistCurrent() async {
    final store = _playbackStore;
    final track = state.track;
    final reciter = state.reciter;
    if (store == null || track == null || reciter == null) return;
    final snapshot = AudioPlaybackSnapshot(
      playback: SurahPlayback(track: track, segments: state.segments),
      reciter: reciter,
      surahName: state.surahName,
      position: state.position,
      speed: state.speed,
      repeatEnabled: state.repeatEnabled,
      rangeStartAyah: state.rangeStartAyah,
      rangeEndAyah: state.rangeEndAyah,
      savedAt: DateTime.now().toUtc(),
    );
    try {
      await store.write(snapshot);
    } on Object {
      // Playback must continue even if local state persistence is unavailable.
    }
  }

  @override
  Future<void> dispose() async {
    _persistenceTimer?.cancel();
    await _persistCurrent();
    _disposed = true;
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    super.dispose();
  }
}
