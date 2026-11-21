import 'dart:math' as math;
import 'dart:typed_data';

import 'follow_core.dart';
import 'mel.dart';
import 'model_session.dart';

/// What the model follower tells the screen: the place is [word] of
/// the passage; red when it was left out or read wrongly.
class ModelPlace {
  ModelPlace(
    this.word, {
    required this.wrong,
    this.why = FollowWhy.unknown,
    this.expected = 0,
    this.heard = 0,
  });
  final int word;
  final bool wrong;

  /// With [wrong]: why ([FollowMiss]).
  final FollowWhy why;
  final int expected;
  final int heard;
}

/// One step, for the harness's measurements: the sound heard when it began
/// (seconds since the microphone was on), what the model and the rest took.
typedef ModelStepTiming = ({double heard, int modelMs, int restMs});

/// Microphone sound in, places out: each step puts the last
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

  /// How loud each hundredth of a second of the last half minute was
  /// (the mean square of its samples), the newest last.
  static const _loudnessKept = 3000;
  final _loudness = Float32List(_loudnessKept);
  var _loudnessCount = 0;
  var _square = 0.0;
  var _squared = 0;

  void add(Int16List pcm) {
    _mel.add(pcm);
    for (final sample in pcm) {
      _square += sample * sample;
      _squared += 1;
      if (_squared == 160) {
        _loudness[_loudnessCount % _loudnessKept] = _square / 160;
        _loudnessCount += 1;
        _square = 0;
        _squared = 0;
      }
    }
  }

  void _hush(Float32List lp, int first, int end) =>
      hushSilence(lp, first, end, _loudness, _loudnessCount);

  bool get due => _mel.samples - _stepped >= minStepSamples;

  void moveTo(int word) => core.moveTo(word);

  List<ModelPlace> step() {
    final events = <ModelPlace>[];
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
    _hush(lp, first, end);
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
        case FollowMiss(:final word, :final why, :final expected, :final heard):
          events.add(
            ModelPlace(
              word,
              wrong: true,
              why: why,
              expected: expected,
              heard: heard,
            ),
          );
        case FollowHeld(:final place, :final fromFrame, :final toFrame):
          if (_heldShort(place, fromFrame, toFrame)) {
            // Held far too short: the word is to be read again, and what
            // this step heard after it does not count.
            core.sayAgain(place.word);
            events.add(
              ModelPlace(
                place.word,
                wrong: true,
                why: switch (place.kind) {
                  2 || 4 => FollowWhy.madd,
                  3 => FollowWhy.shaddah,
                  5 => FollowWhy.izhar,
                  _ => FollowWhy.ghunnah,
                },
              ),
            );
            lastTiming = (
              heard: _stepped / 16000,
              modelMs: modelMs,
              restMs: watch.elapsedMilliseconds - modelMs,
            );
            return events;
          }
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
  /// (a madd of half its counts or less, a ghunnah of one count or none).
  /// False when the model is unsure of a count it hears.
  bool _heldShort(TajweedPlace place, int fromFrame, int toFrame) {
    // The table's own places are many (every long vowel): their counts
    // are read from what the model has heard already, not heard again.
    if (place.kind >= 3) {
      if (!enabledPlaces.contains(place.kind)) return false;
      var counts = 0;
      var previous = 0;
      for (var t = fromFrame - 3; t < toFrame + 1; t++) {
        if (t < _historyFirst || t >= _historyEnd) continue;
        final row = (t - _historyFirst) * recitationClasses;
        var top = 0;
        for (var c = 1; c < recitationClasses; c++) {
          if (_history[row + c] > _history[row + top]) top = c;
        }
        if (top == place.sound && previous != top) {
          counts += 1;
          if (_history[row + top] < -1.2) return false; // less than .3 sure
        }
        previous = top;
      }
      lastHeld = (place: place, counts: counts);
      return switch (place.kind) {
        // A letter with a shaddah said once (none heard is not that: the
        // letter was not heard here at all).
        3 => counts == 1,
        // A natural madd of one count, or none.
        4 => counts <= 1,
        // A clear nun held as a ghunnah is.
        _ => counts >= 3,
      };
    }
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
    // A madd muttasil of half its counts; a ghunnah all but left out (of a
    // right one the model now and then hears two counts of four).
    return counts <= place.golden - (place.kind == 2 ? 2 : 3);
  }

  /// The model's frames heard so far.
  int get frames => _historyEnd;

  /// Sounds the model has heard for sure since the frame [since], in the
  /// last eight seconds at most, whatever they are: whether the reader is
  /// heard at all.
  int soundsSince(int since) => soundsHeard(
    _history,
    _historyEnd - _historyFirst,
    math.min(recitationEarFrames, math.max(0, _historyEnd - since)),
  );

  /// For the harness: the last place looked at and the counts heard.
  ({TajweedPlace place, int counts})? lastHeld;
}

/// The places of the table's own kinds (3 shaddah, 4 natural madd, 5 clear
/// nun) that stop the place: each is on only if a right reading is not
/// stopped by it more often than before (docs/recitation-on-device-spike).
Set<int> enabledPlaces = <int>{5};

/// The frames the line under the text goes by: eight seconds.
const recitationEarFrames = 8 * recitationFrameRate;

/// How many sounds the model writes in the last [last] of the [frames]
/// frames of [lp]: a sound begins on a frame where it is heard most and
/// the frame before had another, or none.
int soundsHeard(Float32List lp, int frames, int last) {
  var sounds = 0;
  var previous = 0;
  for (var t = frames > last ? frames - last : 0; t < frames; t++) {
    final row = t * recitationClasses;
    var top = 0;
    for (var c = 1; c < recitationClasses; c++) {
      if (lp[row + c] > lp[row + top]) top = c;
    }
    // (A room's noise is written as a sound now and then, seldom for
    // sure.)
    if (top != 0 && top != previous && lp[row + top] >= -.36) sounds += 1;
    previous = top;
  }
  return sounds;
}

/// Writes silence over the model's frames [first]..[end] ([lp] begins
/// with frame [first]) wherever the reader said nothing: no hundredth of
/// a second within three tenths of the frame is within 20 dB of how loud
/// the reader's voice is (the loudest fifth of what [loudness] keeps, a
/// ring of the mean squares of the last [count] hundredths). After two
/// seconds of silence the model makes up sounds, and a reader who waits
/// before the next ayah would be told of a mistake. Only the middle of a
/// silence is written over: a letter said softly, or the closure of one,
/// has louder sound beside it.
void hushSilence(
  Float32List lp,
  int first,
  int end,
  Float32List loudness,
  int count,
) {
  const around = 30;
  final kept = math.min(count, loudness.length);
  if (kept < 300) return;
  final all = Float32List.sublistView(loudness, 0, kept).toList()..sort();
  final quiet = all[kept * 4 ~/ 5] / 100;
  for (var frame = first; frame < end; frame++) {
    // A frame of the model is two hundredths of a second.
    final from = math.max(count - kept, frame * 2 - around);
    final to = math.min(count, frame * 2 + 2 + around);
    if (to - from < around) continue;
    var silent = true;
    for (var at = from; at < to && silent; at++) {
      silent = loudness[at % loudness.length] < quiet;
    }
    if (!silent) continue;
    final row = (frame - first) * recitationClasses;
    lp.fillRange(row, row + recitationClasses, -20);
    lp[row] = 0;
  }
}
