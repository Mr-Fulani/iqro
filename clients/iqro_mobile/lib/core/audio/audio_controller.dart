import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/audio/audio_models.dart';
import 'audio_playback_store.dart';

abstract interface class IqroAudioEngine {
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlayerException> get errorStream;
  bool get playing;
  ProcessingState get processingState;

  Future<Duration?> setAudioSource(AudioSource source);
  Future<void> clearAudioSources();
  Future<void> setSpeed(double speed);
  Future<void> setLoopMode(LoopMode mode);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioEngine implements IqroAudioEngine {
  JustAudioEngine([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<PlayerException> get errorStream => _player.errorStream;
  @override
  bool get playing => _player.playing;
  @override
  ProcessingState get processingState => _player.processingState;

  @override
  Future<Duration?> setAudioSource(AudioSource source) =>
      _player.setAudioSource(source);
  @override
  Future<void> clearAudioSources() async {
    await _player.setAudioSources(const <AudioSource>[], preload: false);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

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

@visibleForTesting
Uri validateIqroStreamingAudioUrl(String value) {
  final candidate = value.trim();
  final uri = Uri.tryParse(candidate);
  if (candidate.isEmpty ||
      candidate != value ||
      candidate.contains(RegExp(r'\s')) ||
      uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Audio URL must be an absolute HTTPS URL');
  }
  return uri;
}

Duration clampIqroAudioPosition(Duration position, Duration duration) {
  if (position.isNegative) return Duration.zero;
  if (duration > Duration.zero && position > duration) return duration;
  return position;
}

bool _isCorruptPlaybackSnapshotError(Object error) =>
    error is FormatException || error is TypeError || error is RangeError;

@visibleForTesting
MediaItem buildIqroStandaloneMediaItem({
  required String id,
  required String title,
  String album = 'IQRO',
  String contentType = 'standalone',
  String? artist,
  Uri? artUri,
  Duration? duration,
  Map<String, dynamic>? extras,
}) {
  final normalizedId = id.trim();
  final normalizedTitle = title.trim();
  if (normalizedId.isEmpty) {
    throw ArgumentError.value(id, 'id', 'Audio ID must not be empty');
  }
  if (normalizedTitle.isEmpty) {
    throw ArgumentError.value(title, 'title', 'Audio title must not be empty');
  }
  return MediaItem(
    id: normalizedId,
    album: album.trim().isEmpty ? 'IQRO' : album.trim(),
    title: normalizedTitle,
    artist: artist?.trim().isEmpty ?? true ? null : artist!.trim(),
    artUri: artUri,
    duration: duration == null || duration <= Duration.zero ? null : duration,
    extras: <String, dynamic>{...?extras, 'content_type': contentType},
  );
}

@visibleForTesting
UriAudioSource buildIqroStandaloneAudioSource({
  required Uri uri,
  required MediaItem mediaItem,
}) => AudioSource.uri(uri, tag: mediaItem);

@immutable
class IqroStandaloneAudioState {
  const IqroStandaloneAudioState({
    required this.uri,
    required this.mediaItem,
    this.loading = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatEnabled = false,
    this.error,
  });

  final Uri uri;
  final MediaItem mediaItem;
  final bool loading;
  final bool playing;
  final Duration position;
  final Duration duration;
  final bool repeatEnabled;
  final String? error;

  double get progress {
    if (duration <= Duration.zero) return 0;
    final normalized = clampIqroAudioPosition(position, duration);
    return normalized.inMicroseconds / duration.inMicroseconds;
  }

  Duration get remaining {
    final normalized = clampIqroAudioPosition(position, duration);
    if (duration <= Duration.zero || normalized >= duration) {
      return Duration.zero;
    }
    return duration - normalized;
  }

  IqroStandaloneAudioState copyWith({
    bool? loading,
    bool? playing,
    Duration? position,
    Duration? duration,
    bool? repeatEnabled,
    String? error,
    bool clearError = false,
  }) {
    return IqroStandaloneAudioState(
      uri: uri,
      mediaItem: mediaItem,
      loading: loading ?? this.loading,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatEnabled: repeatEnabled ?? this.repeatEnabled,
      error: clearError ? null : error ?? this.error,
    );
  }
}

typedef _StandaloneRequest = ({String mediaId, int intent, Object? owner});

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
    this.standalone,
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
  final IqroStandaloneAudioState? standalone;

  bool get active => track != null;
  bool get anyAudioActive => active || standalone != null;

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
    IqroStandaloneAudioState? standalone,
    bool clearError = false,
    bool clearSleepTimer = false,
    bool clearActiveAyah = false,
    bool clearRange = false,
    bool clearStandalone = false,
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
      standalone: clearStandalone ? null : standalone ?? this.standalone,
    );
  }
}

class AudioController extends StateNotifier<IqroAudioState> {
  AudioController({
    AudioPlayer? player,
    IqroAudioEngine? engine,
    AudioPlaybackStore? playbackStore,
  }) : assert(player == null || engine == null),
       _player = engine ?? JustAudioEngine(player),
       _playbackStore = playbackStore,
       super(const IqroAudioState()) {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        if (_disposed) return;
        final completed =
            playerState.processingState == ProcessingState.completed;
        final generation = _sourceGeneration;
        final intent = _sourceIntent;
        final standalone = state.standalone;
        if (standalone == null && !state.active) {
          if (playerState.playing) _rejectUnownedPlayback(intent);
          return;
        }
        if (standalone != null) {
          final mediaId = standalone.mediaItem.id;
          state = state.copyWith(
            standalone: standalone.copyWith(
              playing: playerState.playing && !completed,
              loading:
                  playerState.processingState == ProcessingState.loading ||
                  playerState.processingState == ProcessingState.buffering,
              position: completed && standalone.duration > Duration.zero
                  ? standalone.duration
                  : standalone.position,
            ),
          );
          if (completed && playerState.playing) {
            _pauseCompletedSource(
              generation: generation,
              intent: intent,
              standaloneMediaId: mediaId,
            );
          }
          return;
        }
        state = state.copyWith(
          playing: playerState.playing && !completed,
          buffering:
              playerState.processingState == ProcessingState.loading ||
              playerState.processingState == ProcessingState.buffering,
        );
        if (completed && playerState.playing) {
          _pauseCompletedSource(
            generation: generation,
            intent: intent,
            quranTrackId: state.track!.id,
          );
        }
        _schedulePersistence(immediate: completed || !playerState.playing);
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        if (_disposed) return;
        final standalone = state.standalone;
        if (standalone != null) {
          state = state.copyWith(
            standalone: standalone.copyWith(
              position: clampIqroAudioPosition(position, standalone.duration),
            ),
          );
          return;
        }
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
        if (_disposed) return;
        final standalone = state.standalone;
        if (standalone != null && duration != null && !duration.isNegative) {
          state = state.copyWith(
            standalone: standalone.copyWith(
              duration: duration,
              position: clampIqroAudioPosition(standalone.position, duration),
            ),
          );
          return;
        }
        if (duration != null && state.track?.duration == Duration.zero) {
          state = state.copyWith(duration: duration);
          _schedulePersistence();
        }
      }),
    );
    _subscriptions.add(
      _player.errorStream.listen((error) {
        if (_disposed) return;
        final standalone = state.standalone;
        if (standalone != null) {
          state = state.copyWith(
            standalone: standalone.copyWith(
              loading: false,
              playing: false,
              error: error.message,
            ),
          );
          return;
        }
        state = state.copyWith(
          playing: false,
          buffering: false,
          error: error.message,
        );
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

  final IqroAudioEngine _player;
  final AudioPlaybackStore? _playbackStore;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _sleepTimer;
  Timer? _persistenceTimer;
  var _disposed = false;
  var _restoreStarted = false;
  var _restoring = false;
  DateTime? _restoredSavedAt;
  Future<void> _sourceQueue = Future<void>.value();
  var _sourceGeneration = 0;
  var _sourceIntent = 0;
  var _activeSourceIntent = -1;
  var _sourceTransitionActive = false;
  _StandaloneRequest? _standaloneRequest;

  ({int intent, Future<void> interruption}) _beginSourceIntent({
    String? standaloneMediaId,
    Object? standaloneOwner,
  }) {
    final intent = ++_sourceIntent;
    if (standaloneMediaId != null) {
      _standaloneRequest = (
        mediaId: standaloneMediaId,
        intent: intent,
        owner: standaloneOwner,
      );
    }
    final interruption = state.anyAudioActive || _sourceTransitionActive
        ? _interruptCurrentSource()
        : Future<void>.value();
    return (intent: intent, interruption: interruption);
  }

  Future<void> _interruptCurrentSource() async {
    try {
      await _player.stop();
    } on Object {
      // A superseded load may report its own interruption; the latest intent
      // will either replace it or stop playback completely.
    }
  }

  Future<void> _serializeSource(Future<void> Function() operation) {
    final completer = Completer<void>();
    _sourceQueue = _sourceQueue.then((_) async {
      if (_disposed) {
        completer.complete();
        return;
      }
      try {
        await operation();
        completer.complete();
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _pauseCompletedSource({
    required int generation,
    required int intent,
    String? quranTrackId,
    String? standaloneMediaId,
  }) {
    unawaited(
      _serializeSource(() async {
        if (_disposed || intent != _sourceIntent) return;
        final ownsSource = standaloneMediaId != null
            ? _ownsStandalone(generation, standaloneMediaId)
            : quranTrackId != null && _ownsQuran(generation, quranTrackId);
        if (!ownsSource ||
            _player.processingState != ProcessingState.completed) {
          return;
        }
        await _player.pause();
      }).catchError((Object _) {}),
    );
  }

  void _rejectUnownedPlayback(int intent) {
    unawaited(
      _serializeSource(() async {
        if (_disposed || intent != _sourceIntent || state.anyAudioActive) {
          return;
        }
        if (_player.playing) await _player.pause();
        if (_disposed || intent != _sourceIntent || state.anyAudioActive) {
          return;
        }
        await _player.clearAudioSources();
      }).catchError((Object _) {}),
    );
  }

  Future<void> restore() async {
    await _restoreFromStore(force: false);
  }

  Future<void> restoreLatestIfIdle() async {
    await _restoreFromStore(force: true);
  }

  Future<void> _restoreFromStore({required bool force}) async {
    if ((!force && _restoreStarted) ||
        _restoring ||
        _playbackStore == null ||
        state.standalone != null ||
        (force &&
            (state.playing ||
                state.buffering ||
                state.standalone?.playing == true ||
                state.standalone?.loading == true))) {
      return;
    }
    _restoreStarted = true;
    _restoring = true;
    final restoreIntent = _sourceIntent;
    try {
      final snapshot = await _playbackStore.read();
      if (snapshot == null ||
          _disposed ||
          restoreIntent != _sourceIntent ||
          (!force && state.anyAudioActive) ||
          (force &&
              _restoredSavedAt != null &&
              !snapshot.savedAt.isAfter(_restoredSavedAt!))) {
        return;
      }
      final restoredStart = snapshot.rangeStartAyah == null
          ? null
          : snapshot.playback.segmentFor(snapshot.rangeStartAyah!);
      final restoredEnd = snapshot.rangeEndAyah == null
          ? restoredStart
          : snapshot.playback.segmentFor(snapshot.rangeEndAyah!);
      if ((snapshot.rangeStartAyah != null && restoredStart == null) ||
          (snapshot.rangeEndAyah != null && restoredEnd == null)) {
        throw const FormatException(
          'Saved Quran playback range has no audio timings',
        );
      }
      state = state.copyWith(
        speed: snapshot.speed,
        repeatEnabled: snapshot.repeatEnabled,
      );
      await _serializeSource(
        () => _loadPlayback(
          playback: snapshot.playback,
          reciter: snapshot.reciter,
          surahName: snapshot.surahName,
          startSegment: restoredStart,
          endSegment: restoredEnd,
          autoplay: false,
          intent: restoreIntent,
        ),
      );
      if (_disposed || restoreIntent != _sourceIntent) return;
      final generation = _sourceGeneration;
      final trackId = snapshot.playback.track.id;
      var restored = false;
      await _serializeSource(() async {
        if (restoreIntent != _sourceIntent ||
            !_ownsQuran(generation, trackId)) {
          return;
        }
        final playerPosition = state.playerPositionForLogical(
          snapshot.position,
        );
        await _player.seek(playerPosition);
        if (!_ownsQuran(generation, trackId)) return;
        final logicalPosition = state.logicalPositionForPlayer(playerPosition);
        state = state.copyWith(
          playing: false,
          buffering: false,
          position: logicalPosition,
          activeAyah: _segmentAt(state.segments, logicalPosition)?.ayah,
          clearActiveAyah: _segmentAt(state.segments, logicalPosition) == null,
          clearError: true,
        );
        restored = true;
      });
      if (restored) _restoredSavedAt = snapshot.savedAt;
    } on Object catch (error) {
      if (_disposed || restoreIntent != _sourceIntent) return;
      if (!_isCorruptPlaybackSnapshotError(error)) {
        // Loading a valid saved stream can fail temporarily (for example when
        // the device is offline). Keep the snapshot so a later restore can
        // retry instead of permanently losing the user's last position.
        if (!state.anyAudioActive) {
          state = state.copyWith(
            playing: false,
            buffering: false,
            error: error.toString(),
          );
        }
        return;
      }
      try {
        await _serializeSource(() async {
          if (_disposed || restoreIntent != _sourceIntent) return;
          await _playbackStore.clear();
          if (!_disposed && restoreIntent == _sourceIntent) {
            state = const IqroAudioState();
            _activeSourceIntent = -1;
          }
        });
      } on Object {
        // A broken local store must not prevent the app from starting.
      }
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
  }) {
    final normalizedPlayback = playback.normalized();
    if (endAyah != null && startAyah == null) {
      throw ArgumentError('An end ayah requires a start ayah');
    }
    if (startAyah != null && endAyah != null && startAyah > endAyah) {
      throw ArgumentError('The start ayah must not be after the end ayah');
    }
    final startSegment = startAyah == null
        ? null
        : normalizedPlayback.segmentFor(startAyah);
    final endSegment = endAyah == null
        ? startSegment
        : normalizedPlayback.segmentFor(endAyah);
    if (startAyah != null && startSegment == null) {
      throw StateError('Ayah $startAyah has no audio timing');
    }
    if (endAyah != null && endSegment == null) {
      throw StateError('Ayah $endAyah has no audio timing');
    }
    if (startSegment != null &&
        endSegment != null &&
        endSegment.end <= startSegment.start) {
      throw StateError('The selected ayah range has invalid audio timings');
    }
    final sourceIntent = _beginSourceIntent();
    return _serializeSource(
      () => _loadPlayback(
        playback: normalizedPlayback,
        reciter: reciter,
        surahName: surahName,
        startSegment: startSegment,
        endSegment: endSegment,
        autoplay: autoplay,
        intent: sourceIntent.intent,
        interruption: sourceIntent.interruption,
      ),
    );
  }

  Future<void> _loadPlayback({
    required SurahPlayback playback,
    required Reciter reciter,
    required String surahName,
    AudioSegment? startSegment,
    AudioSegment? endSegment,
    required bool autoplay,
    required int intent,
    Future<void>? interruption,
  }) async {
    if (_disposed || intent != _sourceIntent) return;
    final generation = ++_sourceGeneration;
    final track = playback.track;
    _sourceTransitionActive = true;
    try {
      await _persistCurrent();
      if (interruption != null) await interruption;
      if (_disposed ||
          intent != _sourceIntent ||
          generation != _sourceGeneration) {
        return;
      }
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
      if (_disposed ||
          intent != _sourceIntent ||
          generation != _sourceGeneration) {
        return;
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
        segments: playback.segments,
        position: startSegment?.start ?? Duration.zero,
        activeAyah: startSegment?.ayah,
        rangeStartAyah: startSegment?.ayah,
        rangeEndAyah: endSegment?.ayah,
      );
      _activeSourceIntent = intent;
      await _player.setAudioSource(
        buildIqroAudioSource(
          track: track,
          mediaItem: mediaItem,
          start: startSegment?.start,
          end: endSegment?.end,
        ),
      );
      if (!_ownsQuran(generation, track.id)) return;
      await _player.setSpeed(state.speed);
      if (!_ownsQuran(generation, track.id)) return;
      await _player.setLoopMode(
        state.repeatEnabled ? LoopMode.one : LoopMode.off,
      );
      if (!_ownsQuran(generation, track.id)) return;
      _schedulePersistence(immediate: true);
      if (autoplay) _startQuranPlayback(generation, track.id);
    } on Object catch (error) {
      if (_disposed || intent != _sourceIntent) return;
      if (_ownsQuran(generation, track.id)) {
        state = state.copyWith(
          playing: false,
          buffering: false,
          error: error.toString(),
        );
      }
      rethrow;
    } finally {
      _sourceTransitionActive = false;
    }
  }

  Future<void> toggle() async {
    final trackId = state.track?.id;
    if (trackId == null || state.standalone != null) return;
    final generation = _sourceGeneration;
    await _serializeSource(() async {
      if (!_ownsQuran(generation, trackId)) return;
      if (_player.processingState == ProcessingState.completed) {
        await _player.pause();
        if (!_ownsQuran(generation, trackId)) return;
        await _player.seek(Duration.zero);
        if (_ownsQuran(generation, trackId)) {
          _startQuranPlayback(generation, trackId);
        }
        return;
      }
      if (_player.playing) {
        await _player.pause();
        if (_ownsQuran(generation, trackId)) {
          _schedulePersistence(immediate: true);
        }
        return;
      }
      _startQuranPlayback(generation, trackId);
    });
  }

  void _startQuranPlayback(int generation, String trackId) {
    if (!_ownsQuran(generation, trackId)) return;
    unawaited(
      _player.play().catchError((Object error) {
        if (!_ownsQuran(generation, trackId)) return;
        state = state.copyWith(
          playing: false,
          buffering: false,
          error: error.toString(),
        );
      }),
    );
  }

  bool _ownsQuran(int generation, String trackId) =>
      !_disposed &&
      generation == _sourceGeneration &&
      _activeSourceIntent == _sourceIntent &&
      state.standalone == null &&
      state.track?.id == trackId;

  Future<void> loadStandalone({
    required String id,
    required String url,
    required String title,
    String album = 'IQRO',
    String contentType = 'standalone',
    String? artist,
    Uri? artUri,
    Duration? duration,
    Map<String, dynamic>? extras,
    bool autoplay = true,
    Object? owner,
  }) {
    final uri = validateIqroStreamingAudioUrl(url);
    final mediaItem = buildIqroStandaloneMediaItem(
      id: id,
      title: title,
      album: album,
      contentType: contentType,
      artist: artist,
      artUri: artUri,
      duration: duration,
      extras: extras,
    );
    final sourceIntent = _beginSourceIntent(
      standaloneMediaId: mediaItem.id,
      standaloneOwner: owner,
    );
    return _serializeSource(() async {
      if (_disposed || sourceIntent.intent != _sourceIntent) return;
      final generation = ++_sourceGeneration;
      _sourceTransitionActive = true;
      final repeatEnabled = state.standalone?.repeatEnabled ?? false;
      try {
        await _persistCurrent();
        await sourceIntent.interruption;
        if (_disposed ||
            sourceIntent.intent != _sourceIntent ||
            generation != _sourceGeneration) {
          return;
        }
        _sleepTimer?.cancel();
        _persistenceTimer?.cancel();
        if (_player.playing) await _player.pause();
        if (_disposed ||
            sourceIntent.intent != _sourceIntent ||
            generation != _sourceGeneration) {
          return;
        }

        final requestedDuration = duration == null || duration <= Duration.zero
            ? Duration.zero
            : duration;
        state = IqroAudioState(
          speed: state.speed,
          repeatEnabled: state.repeatEnabled,
          standalone: IqroStandaloneAudioState(
            uri: uri,
            mediaItem: mediaItem,
            loading: true,
            duration: requestedDuration,
            repeatEnabled: repeatEnabled,
          ),
        );
        _activeSourceIntent = sourceIntent.intent;
        final resolvedDuration = await _player.setAudioSource(
          buildIqroStandaloneAudioSource(uri: uri, mediaItem: mediaItem),
        );
        if (!_ownsStandalone(generation, mediaItem.id)) return;
        await _player.setSpeed(1);
        if (!_ownsStandalone(generation, mediaItem.id)) return;
        await _player.setLoopMode(repeatEnabled ? LoopMode.one : LoopMode.off);
        if (!_ownsStandalone(generation, mediaItem.id)) return;
        final normalizedDuration =
            resolvedDuration == null || resolvedDuration <= Duration.zero
            ? requestedDuration
            : resolvedDuration;
        state = state.copyWith(
          standalone: state.standalone!.copyWith(
            loading: false,
            duration: normalizedDuration,
            clearError: true,
          ),
        );
        if (autoplay) _startStandalonePlayback(generation, mediaItem.id);
      } on Object catch (error) {
        if (_disposed || sourceIntent.intent != _sourceIntent) return;
        if (_ownsStandalone(generation, mediaItem.id)) {
          state = state.copyWith(
            standalone: state.standalone!.copyWith(
              loading: false,
              playing: false,
              error: error.toString(),
            ),
          );
        }
        rethrow;
      } finally {
        _sourceTransitionActive = false;
      }
    });
  }

  Future<void> toggleStandalone(String mediaId, {Object? owner}) {
    final request = _matchingStandaloneRequest(mediaId, owner);
    if (request == null) return Future<void>.value();
    final generation = _sourceGeneration;
    return _serializeSource(() async {
      if (!_ownsStandaloneRequest(generation, request)) return;
      if (_player.processingState == ProcessingState.completed) {
        await _player.pause();
        if (!_ownsStandaloneRequest(generation, request)) return;
        await _player.seek(Duration.zero);
        if (_ownsStandaloneRequest(generation, request)) {
          _startStandalonePlayback(generation, mediaId);
        }
        return;
      }
      if (_player.playing) {
        await _player.pause();
        if (_ownsStandaloneRequest(generation, request)) {
          state = state.copyWith(
            standalone: state.standalone!.copyWith(playing: false),
          );
        }
        return;
      }
      _startStandalonePlayback(generation, mediaId);
    });
  }

  Future<void> seekStandalone(
    String mediaId,
    Duration position, {
    Object? owner,
  }) {
    final request = _matchingStandaloneRequest(mediaId, owner);
    if (request == null) return Future<void>.value();
    final generation = _sourceGeneration;
    return _serializeSource(() async {
      if (!_ownsStandaloneRequest(generation, request)) return;
      final standalone = state.standalone!;
      final target = clampIqroAudioPosition(position, standalone.duration);
      await _player.seek(target);
      if (_ownsStandaloneRequest(generation, request)) {
        state = state.copyWith(
          standalone: state.standalone!.copyWith(
            position: target,
            clearError: true,
          ),
        );
      }
    });
  }

  Future<void> toggleStandaloneRepeat(String mediaId, {Object? owner}) {
    final request = _matchingStandaloneRequest(mediaId, owner);
    if (request == null) return Future<void>.value();
    final generation = _sourceGeneration;
    return _serializeSource(() async {
      if (!_ownsStandaloneRequest(generation, request)) return;
      final enabled = !state.standalone!.repeatEnabled;
      await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
      if (_ownsStandaloneRequest(generation, request)) {
        state = state.copyWith(
          standalone: state.standalone!.copyWith(
            repeatEnabled: enabled,
            clearError: true,
          ),
        );
      }
    });
  }

  Future<void> stopStandalone(String mediaId, {Object? owner}) {
    final request = _standaloneRequest;
    if (request == null ||
        request.mediaId != mediaId ||
        request.intent != _sourceIntent ||
        !identical(request.owner, owner)) {
      return Future<void>.value();
    }
    final stopIntent = ++_sourceIntent;
    ++_sourceGeneration;
    final interruption = _interruptCurrentSource();
    return _serializeSource(() async {
      if (_disposed || stopIntent != _sourceIntent) return;
      await interruption;
      if (_disposed || stopIntent != _sourceIntent) return;
      await _player.clearAudioSources();
      if (_disposed || stopIntent != _sourceIntent) return;
      if (state.standalone?.mediaItem.id == mediaId) {
        state = IqroAudioState(
          speed: state.speed,
          repeatEnabled: state.repeatEnabled,
        );
        _activeSourceIntent = -1;
      }
      if (_standaloneRequest?.intent == request.intent) {
        _standaloneRequest = null;
      }
    });
  }

  void _startStandalonePlayback(int generation, String mediaId) {
    if (!_ownsStandalone(generation, mediaId)) return;
    state = state.copyWith(
      standalone: state.standalone!.copyWith(playing: true, clearError: true),
    );
    unawaited(
      _player.play().catchError((Object error) {
        if (!_ownsStandalone(generation, mediaId)) return;
        state = state.copyWith(
          standalone: state.standalone!.copyWith(
            loading: false,
            playing: false,
            error: error.toString(),
          ),
        );
      }),
    );
  }

  bool _ownsStandalone(int generation, String mediaId) =>
      !_disposed &&
      generation == _sourceGeneration &&
      _activeSourceIntent == _sourceIntent &&
      state.standalone?.mediaItem.id == mediaId;

  _StandaloneRequest? _matchingStandaloneRequest(
    String mediaId,
    Object? owner,
  ) {
    final request = _standaloneRequest;
    if (request == null ||
        request.mediaId != mediaId ||
        request.intent != _sourceIntent ||
        !identical(request.owner, owner)) {
      return null;
    }
    return request;
  }

  bool _ownsStandaloneRequest(int generation, _StandaloneRequest request) {
    final current = _standaloneRequest;
    return current != null &&
        current.intent == request.intent &&
        current.mediaId == request.mediaId &&
        identical(current.owner, request.owner) &&
        _ownsStandalone(generation, request.mediaId);
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

  Future<void> seek(Duration position) {
    final generation = _sourceGeneration;
    final trackId = state.track?.id;
    if (trackId == null || state.standalone != null) {
      return Future<void>.value();
    }
    return _serializeSource(() async {
      if (!_ownsQuran(generation, trackId)) return;
      await _player.seek(state.playerPositionForLogical(position));
    });
  }

  Future<void> seekInActiveRange(
    Duration relativePosition, {
    String? expectedTrackId,
    int? expectedStartAyah,
    int? expectedEndAyah,
  }) {
    final generation = _sourceGeneration;
    final trackId = state.track?.id;
    if (trackId == null || state.standalone != null) {
      return Future<void>.value();
    }
    if (expectedTrackId != null &&
        (trackId != expectedTrackId ||
            state.rangeStartAyah != expectedStartAyah ||
            state.rangeEndAyah != expectedEndAyah)) {
      return Future<void>.value();
    }
    return _serializeSource(() async {
      if (!_ownsQuran(generation, trackId)) return;
      if (expectedTrackId != null &&
          (state.track?.id != expectedTrackId ||
              state.rangeStartAyah != expectedStartAyah ||
              state.rangeEndAyah != expectedEndAyah)) {
        return;
      }
      final clamped = relativePosition.inMilliseconds.clamp(
        0,
        state.effectiveDuration.inMilliseconds,
      );
      await _player.seek(Duration(milliseconds: clamped.toInt()));
    });
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
      await seek(segment.start);
    }
  }

  Future<void> setAyahRange(
    int startAyah,
    int endAyah, {
    bool autoplay = true,
  }) {
    if (startAyah > endAyah) {
      throw ArgumentError('The start ayah must not be after the end ayah');
    }
    final start = state.segmentForAyah(startAyah);
    final end = state.segmentForAyah(endAyah);
    if (start == null || end == null) {
      throw StateError('The selected ayah range has no audio timings');
    }
    if (end.end <= start.start) {
      throw StateError('The selected ayah range has invalid audio timings');
    }
    final track = state.track;
    final reciter = state.reciter;
    if (track == null || reciter == null) {
      throw StateError('No audio track is loaded');
    }
    final surahName = state.surahName;
    final sourceIntent = _beginSourceIntent();
    return _serializeSource(
      () => _setAyahRange(
        start: start,
        end: end,
        track: track,
        reciter: reciter,
        surahName: surahName,
        autoplay: autoplay,
        intent: sourceIntent.intent,
        interruption: sourceIntent.interruption,
      ),
    );
  }

  Future<void> _setAyahRange({
    required AudioSegment start,
    required AudioSegment end,
    required AudioTrack track,
    required Reciter reciter,
    required String surahName,
    required bool autoplay,
    required int intent,
    required Future<void> interruption,
  }) async {
    if (_disposed || intent != _sourceIntent) return;
    final generation = ++_sourceGeneration;
    _sourceTransitionActive = true;
    try {
      await interruption;
      if (_disposed ||
          intent != _sourceIntent ||
          generation != _sourceGeneration) {
        return;
      }
      if (_player.playing) await _player.pause();
      if (_disposed ||
          intent != _sourceIntent ||
          generation != _sourceGeneration) {
        return;
      }
      state = state.copyWith(
        buffering: true,
        position: start.start,
        activeAyah: start.ayah,
        rangeStartAyah: start.ayah,
        rangeEndAyah: end.ayah,
        clearError: true,
      );
      _activeSourceIntent = intent;
      await _player.setAudioSource(
        buildIqroAudioSource(
          track: track,
          mediaItem: _mediaItemFor(
            track: track,
            reciter: reciter,
            surahName: surahName,
            startAyah: start.ayah,
            endAyah: end.ayah,
            clipStart: start.start,
            clipEnd: end.end,
          ),
          start: start.start,
          end: end.end,
        ),
      );
      if (!_ownsQuran(generation, track.id)) return;
      await _player.setSpeed(state.speed);
      if (!_ownsQuran(generation, track.id)) return;
      await _player.setLoopMode(
        state.repeatEnabled ? LoopMode.one : LoopMode.off,
      );
      if (!_ownsQuran(generation, track.id)) return;
      _schedulePersistence(immediate: true);
      if (autoplay) _startQuranPlayback(generation, track.id);
    } on Object catch (error) {
      if (_disposed || intent != _sourceIntent) return;
      if (_ownsQuran(generation, track.id)) {
        state = state.copyWith(
          playing: false,
          buffering: false,
          error: error.toString(),
        );
      }
      rethrow;
    } finally {
      _sourceTransitionActive = false;
    }
  }

  Future<void> setSpeed(double speed) {
    final generation = _sourceGeneration;
    final trackId = state.track?.id;
    if (trackId == null || state.standalone != null) {
      return Future<void>.value();
    }
    return _serializeSource(() async {
      if (!_ownsQuran(generation, trackId)) return;
      await _player.setSpeed(speed);
      if (!_ownsQuran(generation, trackId)) return;
      state = state.copyWith(speed: speed);
      _schedulePersistence(immediate: true);
    });
  }

  void updateReciterMetadata(Reciter reciter, {String? currentReciterId}) {
    if (_disposed || state.standalone != null) return;
    if (state.reciter?.id != (currentReciterId ?? reciter.id)) return;
    state = state.copyWith(reciter: reciter);
    _schedulePersistence(immediate: true);
  }

  Future<void> toggleRepeat() {
    final generation = _sourceGeneration;
    final trackId = state.track?.id;
    if (trackId == null || state.standalone != null) {
      return Future<void>.value();
    }
    return _serializeSource(() async {
      if (!_ownsQuran(generation, trackId)) return;
      final enabled = !state.repeatEnabled;
      await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
      if (!_ownsQuran(generation, trackId)) return;
      state = state.copyWith(repeatEnabled: enabled);
      _schedulePersistence(immediate: true);
    });
  }

  void setSleepTimer(Duration? duration) {
    if (_disposed || !state.active || state.standalone != null) return;
    _sleepTimer?.cancel();
    if (duration == null) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }
    state = state.copyWith(sleepTimerMinutes: duration.inMinutes);
    _sleepTimer = Timer(duration, () {
      unawaited(
        _serializeSource(() async {
          if (_disposed || !state.active || state.standalone != null) return;
          await _player.pause();
          if (_disposed || !state.active || state.standalone != null) return;
          state = state.copyWith(clearSleepTimer: true);
        }).catchError((Object _) {}),
      );
    });
  }

  Future<void> stop() {
    final intent = ++_sourceIntent;
    ++_sourceGeneration;
    final interruption = _interruptCurrentSource();
    return _serializeSource(() async {
      if (_disposed || intent != _sourceIntent) return;
      _sleepTimer?.cancel();
      _persistenceTimer?.cancel();
      await interruption;
      if (_disposed || intent != _sourceIntent) return;
      await _player.clearAudioSources();
      if (_disposed || intent != _sourceIntent) return;
      state = const IqroAudioState();
      _activeSourceIntent = -1;
      _standaloneRequest = null;
      await _playbackStore?.clear();
    });
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
  void dispose() {
    if (_disposed) return;
    _persistenceTimer?.cancel();
    final persistence = _persistCurrent();
    _disposed = true;
    ++_sourceGeneration;
    ++_sourceIntent;
    _sleepTimer?.cancel();
    final playerDisposal = _player.dispose().catchError((Object _) {});
    unawaited(
      _disposeResources(persistence, playerDisposal).catchError((Object _) {}),
    );
    super.dispose();
  }

  Future<void> _disposeResources(
    Future<void> persistence,
    Future<void> playerDisposal,
  ) async {
    await persistence;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await playerDisposal;
  }
}
