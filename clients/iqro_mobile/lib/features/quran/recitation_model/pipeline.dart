import 'dart:math' as math;
import 'dart:typed_data';

import 'follow_core.dart';
import 'mel.dart';
import 'model_session.dart';

/// What the model follower tells the screen.
sealed class RecitationModelEvent {}

/// The lens goes to [word] of the passage; red when it was left out or
/// said as another.
class ModelPlace extends RecitationModelEvent {
  ModelPlace(this.word, {required this.wrong});
  final int word;
  final bool wrong;
}

/// Tajweed remarks on an ayah read through: (kind, word of the passage).
class ModelRemarks extends RecitationModelEvent {
  ModelRemarks(this.remarks);
  final List<(int, int)> remarks;
}

/// One step, for the trial's measurements: the sound heard when it began
/// (seconds since the microphone was on), what the model and the rest took.
typedef ModelStepTiming = ({double heard, int modelMs, int restMs});

/// Microphone sound in, lens places out: each step puts the last
/// [windowFrames] of sound through the model and the follower.
class RecitationPipeline {
  RecitationPipeline({
    required this.session,
    required Float32List melFilters,
    required this.ayahs,
  }) : _mel = StreamingMel(melFilters),
       core = RecitationFollowCore(RecitationPassage(ayahs));

  /// Mel frames (100 a second) of sound a step looks at, and of silence
  /// put after them: the model hears the last word sooner with it
  /// (docs/recitation-on-device-spike).
  static const windowFrames = 260;
  static const tailFrames = 40;

  /// The least new sound worth a step.
  static const minStepSamples = 1600;

  /// The longest ayah whose tajweed is looked at, in model frames.
  static const longestAyah = 12 * recitationFrameRate;

  final RecitationModelSession session;
  final List<ExpectedAyah> ayahs;
  final StreamingMel _mel;
  final RecitationFollowCore core;
  var _stepped = 0;

  /// The model's frames of the last [historyFrames], each as the latest
  /// step heard it: a word may be longer than one step's sound (a madd of
  /// six counts), and the follower reads all of it.
  static const historyFrames = 500;
  static const edgeFrames = 25;
  final _history = Float32List(historyFrames * recitationClasses);
  var _historyFirst = 0;
  var _historyEnd = 0;
  ModelStepTiming? lastTiming;

  void add(Int16List pcm) => _mel.add(pcm);

  bool get due => _mel.samples - _stepped >= minStepSamples;

  void moveTo(int word) => core.moveTo(word);

  List<RecitationModelEvent> step() {
    final events = <RecitationModelEvent>[];
    final watch = Stopwatch()..start();
    _stepped = _mel.samples;
    final to = _mel.samples ~/ 160 ~/ 2 * 2;
    final from = math.max(0, to - windowFrames);
    if (to - from < 20) return events;
    final lp = session.run(
      _mel.window(from, to, tail: tailFrames),
      to - from + tailFrames,
    );
    final modelMs = watch.elapsedMilliseconds;
    if (lp == null) return events;
    final first = from ~/ 2;
    final end = first + (to - from) ~/ 2;
    // What slid out of the history's reach is dropped; the new frames
    // replace what an earlier step heard of them.
    final newFirst = end > historyFrames ? end - historyFrames : 0;
    if (newFirst > _historyFirst && _historyEnd > newFirst) {
      _history.setRange(
        0,
        (_historyEnd - newFirst) * recitationClasses,
        _history,
        (newFirst - _historyFirst) * recitationClasses,
      );
    }
    _historyFirst = newFirst;
    // The first frames of a step's sound have nothing before them for the
    // model to go by: what an earlier step heard of them stands.
    final edge = first > 0 && _historyEnd > first + edgeFrames ? edgeFrames : 0;
    _history.setRange(
      (first + edge - newFirst) * recitationClasses,
      (end - newFirst) * recitationClasses,
      lp,
      edge * recitationClasses,
    );
    _historyEnd = end;
    final found = core.step(
      Float32List.sublistView(
        _history,
        0,
        (end - newFirst) * recitationClasses,
      ),
      end - newFirst,
      newFirst,
    );
    for (final event in found) {
      switch (event) {
        case FollowPlace(:final word):
          events.add(ModelPlace(word, wrong: false));
        case FollowMiss(:final word):
          events.add(ModelPlace(word, wrong: true));
        case FollowAyahRead(:final ayah, :final fromFrame, :final toFrame):
          final remarks = _tajweed(ayah, fromFrame, toFrame);
          events.add(ModelRemarks(remarks));
      }
    }
    lastTiming = (
      heard: _stepped / 16000,
      modelMs: modelMs,
      restMs: watch.elapsedMilliseconds - modelMs,
    );
    return events;
  }

  List<(int, int)> _tajweed(int ayah, int fromFrame, int toFrame) {
    final from = math.max(0, fromFrame - 10) * 2;
    final to = math.min(_mel.samples ~/ 160 ~/ 2 * 2, (toFrame + 15) * 2);
    if (to - from > longestAyah * 2 || to - from < 20) return const [];
    final lp = session.run(
      _mel.window(from, to, lead: tailFrames, tail: tailFrames),
      to - from + 2 * tailFrames,
    );
    if (lp == null) return const [];
    final firstWord = core.passage.ayahOf.indexOf(ayah);
    return <(int, int)>[
      for (final remark in tajweedRemarks(
        lp,
        (to - from) ~/ 2 + tailFrames,
        ayahs[ayah],
      ))
        (remark.kind, firstWord + remark.word),
    ];
  }
}
