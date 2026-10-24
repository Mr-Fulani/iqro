import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:video_player/video_player.dart';

/// A video that plays without a platform: tests move it by hand.
class FakeVideoController extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  FakeVideoController(this.uri, {this.fails = false})
    : super(const VideoPlayerValue.uninitialized());

  final Uri uri;

  /// [initialize] throws, as without a network.
  final bool fails;
  final seeks = <Duration>[];
  var disposed = false;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    if (fails) throw Exception('offline');
    value = value.copyWith(
      duration: const Duration(milliseconds: 588000),
      size: const Size(1280, 720),
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    if (value.position == value.duration) await seekTo(Duration.zero);
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  /// Playback moved on to [position].
  void playTo(Duration position) => value = value.copyWith(position: position);

  void finish() => value = value.copyWith(
    position: value.duration,
    isPlaying: false,
    isCompleted: true,
  );

  void breakDown() => value = value.copyWith(errorDescription: 'network');

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Makes [FakeVideoController]s and keeps them in order.
class FakeVideoFactory {
  FakeVideoFactory({this.fails = false});

  bool fails;
  final made = <FakeVideoController>[];

  FakeVideoController get last => made.last;

  VideoPlayerController call(Uri uri) {
    final controller = FakeVideoController(uri, fails: fails);
    made.add(controller);
    return controller;
  }
}

class RecordingAudioController extends StateNotifier<IqroAudioState>
    implements AudioController {
  RecordingAudioController() : super(const IqroAudioState());

  var lessonVideoPauses = 0;

  @override
  Future<void> pauseForLessonVideo() async {
    lessonVideoPauses += 1;
  }

  /// A tajweed lesson stops its clips when it closes.
  @override
  Future<void> stopStandaloneOf(Object owner) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
