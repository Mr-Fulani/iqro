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

/// A word read rightly had a ghunnah or a madd held too short: [kind] is
/// 0 ghunnah, 1 idgham with ghunnah, 2 madd muttasil.
class ModelRemark extends RecitationModelEvent {
  ModelRemark(this.word, this.kind);
  final int word;
  final int kind;
}

/// A word taken as read had a sound that was not the text's: the model
/// heard the class [heard] (0: nothing) where [expected] is written.
class ModelOtherwise extends RecitationModelEvent {
  ModelOtherwise(this.word, this.expected, this.heard);
  final int word;
  final int expected;
  final int heard;
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
        case FollowHeld(:final place, :final fromFrame, :final toFrame):
          if (_heldShort(place, fromFrame, toFrame)) {
            events.add(ModelRemark(place.word, place.kind));
          }
        case FollowOtherwise(:final word, :final expected, :final heard):
          events.add(ModelOtherwise(word, expected, heard));
      }
    }
    lastTiming = (
      heard: _stepped / 16000,
      modelMs: modelMs,
      restMs: watch.elapsedMilliseconds - modelMs,
    );
    return events;
  }

  /// Whether the sound of [place] was held too short: the model hears
  /// that stretch again, with what is around it, and its counts of the
  /// sound are read as the rule engine shipped with the model reads them
  /// (two counts or more short of what a right reading has).
  /// False when the model is unsure of a count it hears.
  bool _heldShort(TajweedPlace place, int fromFrame, int toFrame) {
    const before = 50;
    const after = 25;
    final from = math.max(0, fromFrame - before) * 2;
    final to = math.min(_mel.samples ~/ 160 ~/ 2 * 2, (toFrame + after) * 2);
    if (to - from < 20) return false;
    final lp = session.run(
      _mel.window(from, to, lead: tailFrames, tail: tailFrames),
      to - from + 2 * tailFrames,
    );
    if (lp == null) return false;
    final shift = tailFrames ~/ 2 - from ~/ 2;
    var counts = 0;
    var previous = 0;
    for (var t = fromFrame - 3 + shift; t < toFrame + 1 + shift; t++) {
      if (t < 0) continue;
      final row = t * recitationClasses;
      if (row + recitationClasses > lp.length) break;
      var top = 0;
      for (var c = 1; c < recitationClasses; c++) {
        if (lp[row + c] > lp[row + top]) top = c;
      }
      if (top == place.sound && previous != top) {
        counts += 1;
        if (lp[row + top] < -1.2) return false; // less than .3 sure
      }
      previous = top;
    }
    lastHeld = (place: place, counts: counts);
    // One count less is within what the model mishears of a right reading.
    return counts <= place.golden - 2;
  }

  /// For the harness: the last place looked at and the counts heard.
  ({TajweedPlace place, int counts})? lastHeld;
}
