import 'dart:math' as math;
import 'dart:typed_data';

/// The trial follower of the recitation check that listens with a model on
/// the phone (docs/recitation-on-device-spike): the words are known, so
/// they are not recognised; the model's sound probabilities, 50 frames a
/// second, are aligned with the sounds a correct reading has.

/// Symbols the model writes, the CTC blank first.
const recitationClasses = 43;

/// Frames of the model in a second.
const recitationFrameRate = 50;

/// One ayah of the table of expected sounds
/// (tool/recitation_model/build_table.py).
class ExpectedAyah {
  ExpectedAyah(this.sounds, this.spans, this.units);

  /// Class of each sound, 1..42, as a correct reading has them: a long
  /// vowel once per count.
  final Uint8List sounds;

  /// Per word, where its sounds begin and end in [sounds].
  final List<(int, int)> spans;

  /// The places remarked on: kind (0 ghunnah, 1 idgham with ghunnah,
  /// 2 madd muttasil), start, end, word, counts expected.
  final List<(int, int, int, int, int)> units;

  static ExpectedAyah? fromJson(Object? json, List<String> symbols) {
    if (json is! List) return null;
    final text = json[0] as String;
    final flat = (json[1] as List).cast<int>();
    final unit = (json[2] as List).cast<int>();
    return ExpectedAyah(
      Uint8List.fromList(<int>[
        for (final rune in text.runes)
          symbols.indexOf(String.fromCharCode(rune)) + 1,
      ]),
      <(int, int)>[
        for (var i = 0; i < flat.length; i += 2) (flat[i], flat[i + 1]),
      ],
      <(int, int, int, int, int)>[
        for (var i = 0; i < unit.length; i += 5)
          (unit[i], unit[i + 1], unit[i + 2], unit[i + 3], unit[i + 4]),
      ],
    );
  }
}

/// The sounds of the ayahs to be read, in order, with a run of one sound
/// (a long vowel's counts, a held nasal) written once: how long it is held
/// is not what the follower asks.
class RecitationPassage {
  RecitationPassage(List<ExpectedAyah> ayahs) {
    final sounds = <int>[];
    for (final (number, ayah) in ayahs.indexed) {
      for (final (start, end) in ayah.spans) {
        wordStart.add(sounds.length);
        for (var i = start; i < end; i++) {
          if (i > start && ayah.sounds[i] == ayah.sounds[i - 1]) continue;
          sounds.add(ayah.sounds[i]);
          wordOf.add(wordStart.length - 1);
        }
        wordEnd.add(sounds.length);
        ayahOf.add(number);
      }
    }
    this.sounds = Uint8List.fromList(sounds);
  }

  late final Uint8List sounds;
  final wordStart = <int>[];
  final wordEnd = <int>[];
  final wordOf = <int>[];
  final ayahOf = <int>[];

  int get words => wordStart.length;
  bool silent(int word) => wordEnd[word] == wordStart[word];
}

/// What a step of the follower found.
sealed class FollowEvent {}

/// The reader is on [word], or has read it: the lens goes there.
class FollowPlace extends FollowEvent {
  FollowPlace(this.word);
  final int word;
}

/// [word] was left out or said as another: the lens waits on it.
class FollowMiss extends FollowEvent {
  FollowMiss(this.word);
  final int word;
}

/// An ayah was read through with no mistake of words, between these
/// frames: its tajweed may be looked at.
class FollowAyahRead extends FollowEvent {
  FollowAyahRead(this.ayah, this.fromFrame, this.toFrame);
  final int ayah;
  final int fromFrame;
  final int toFrame;
}

const _floor = -10.0; // the most a sound that does not fit costs
const _otherSound = -6.0; // a frame of speech that is not the text
const _skipPrice = -10.0; // going on with a later word
const _maxSkip = 14; // words that may be left out at once
const _ahead = 70; // sounds of the text looked at ahead of the place
const _settle = 10; // frames a word has been over before it is final
const _stallSounds = 10; // sounds of other speech that are a mistake
const _backSounds = 6; // … that may be two words read again
const _goodSound = -4.0;
const _never = -1e30;

class _Path {
  _Path(this.lo, this.frame, this.best, this.other, this.skips, this.endOther);

  /// First sound of the slice, in the passage.
  final int lo;

  /// Per sound of the slice: the frame it was first on the path, -1 if
  /// never; and the best log-probability it had there.
  final Int32List frame;
  final Float64List best;

  /// Per word start in the slice (passage word index → frames of other
  /// speech before it).
  final Map<int, List<int>> other;

  /// Words gone over: (word before which the path stood, word it went on
  /// with, frame).
  final List<(int, int, int)> skips;

  /// The word before which the path ends in other speech, or null.
  final int? endOther;
}

/// Follows a reader through a [RecitationPassage], strictly: the place
/// moves on only to the word expected next.
class RecitationFollowCore {
  RecitationFollowCore(this.passage) {
    _passSilent();
  }

  final RecitationPassage passage;

  /// For the harness: what each step's path was.
  void Function(String)? trace;

  /// The word expected next; [RecitationPassage.words] past the last.
  var next = 0;

  /// Sounds of the passage that are final, and the frame after the last.
  var _sound = 0;
  var _frame = 0;
  var _now = 0;

  /// Sounds of the word being read that did not fit, among the final ones.
  var _bad = 0;

  /// Nothing read rightly since the start or [moveTo]: what is said
  /// before the first word (isti'adha, basmala) is no mistake.
  var fresh = true;
  var wrong = false;
  int? _shown;
  int? _ayahFrom;
  int? _wordFrom;
  var _ayahClean = false;

  /// For the harness: where the follower stands.
  String get debugState =>
      'next=$next sound=$_sound frame=$_frame bad=$_bad fresh=$fresh wrong=$wrong';

  void _passSilent() {
    while (next < passage.words && passage.silent(next)) {
      next += 1;
    }
    if (next < passage.words && _sound < passage.wordStart[next]) {
      _sound = passage.wordStart[next];
    }
  }

  /// Reading starts from [word].
  void moveTo(int word) {
    next = word.clamp(0, passage.words);
    _sound = next < passage.words
        ? passage.wordStart[next]
        : passage.sounds.length;
    _frame = _now;
    _bad = 0;
    _wordFrom = null;
    fresh = true;
    wrong = false;
    _shown = null;
    _ayahFrom = null;
    _ayahClean = false;
    _passSilent();
  }

  static int _allowedBad(int sounds) => math.max(1, (sounds * .34).floor());

  /// [lp]: log-probabilities of [frames] frames, the first being frame
  /// [first] since the microphone was turned on.
  List<FollowEvent> step(Float32List lp, int frames, int first) {
    final events = <FollowEvent>[];
    _now = first + frames;
    if (next >= passage.words) return events;
    if (_frame < first) _frame = first;
    final from = _frame - first;
    final count = frames - from;
    if (count < 2) return events;
    final midWord = _sound > passage.wordStart[next];
    final soundBefore = _sound;
    // From the sound said last: more counts of it are no other speech.
    final path = _align(
      lp,
      from,
      count,
      _sound > 0 ? _sound - 1 : 0,
      prior: _sound > 0,
      boundary: !midWord,
      skip: !fresh && !midWord,
    );
    final last = count - 1;
    trace?.call(
      'now=$_now from=$from count=$count lo=${path.lo} '
      'frames=${path.frame.take(14).toList()} '
      'best=${path.best.take(14).map((v) => v < -99 ? '-' : v.toStringAsFixed(1)).toList()} '
      'skips=${path.skips} endOther=${path.endOther} '
      'other=${path.other.map((k, v) => MapEntry(k, v.length))}',
    );
    var word = next;
    var skipped = false;
    if (path.skips.isNotEmpty) {
      final (_, to, _) = path.skips.first;
      if (path.skips.first.$1 == next) {
        skipped = true;
        word = to;
      }
    }
    if (skipped) {
      // The reader went on with a later word: enough of it to be sure.
      final start = passage.wordStart[word] - path.lo;
      var sure = 0;
      for (
        var i = start;
        i < passage.wordEnd[word] - path.lo && i < path.frame.length;
        i++
      ) {
        // Not the newest frames: the model may yet hear them otherwise.
        if (path.frame[i] >= 0 &&
            path.frame[i] <= last - _settle &&
            path.best[i] >= _goodSound) {
          sure += 1;
        }
      }
      if (sure >=
          math.min(3, passage.wordEnd[word] - passage.wordStart[word])) {
        _miss(events);
        _dropTo(first + from + _lastFrame(path) + 1);
      }
      return events;
    }
    while (word < passage.words) {
      if (passage.silent(word)) {
        word += 1;
        continue;
      }
      final start = passage.wordStart[word];
      final end = passage.wordEnd[word];
      if (end - path.lo > path.frame.length) break;
      final begin = word == next ? _sound : start;
      final before = word == next ? _bad : 0;
      var said = 0;
      var bad = before;
      var lastFrame = -1;
      for (var i = begin; i < end; i++) {
        final at = path.frame[i - path.lo];
        if (at < 0) break;
        said += 1;
        lastFrame = at;
        if (_unfit(path, i)) bad += 1;
      }
      // The first word after silence has no word before it to vouch for
      // it: its first sound must be there.
      final allowed =
          fresh && said > 0 && path.best[begin - path.lo] < _goodSound
          ? -1
          : _allowedBad(end - start);
      if (begin + said < end) {
        // On this word now, if what is heard of it fits.
        if ((begin > start || said - (bad - before) >= 2) &&
            bad <= (said >= 5 ? math.min(1, allowed) : 0)) {
          _place(word, events, whole: false);
        }
        break;
      }
      if (bad > allowed) {
        // All its sounds are past, and too few fit: said as another.
        if (word == next && lastFrame <= last - _settle) {
          _sound = start;
          _bad = 0;
          _wordFrom = null;
          _miss(events);
          _dropTo(first + from + lastFrame + 1);
        }
        break;
      }
      _place(word, events, whole: true);
      if (word != next || lastFrame > last - _settle) {
        // Not final yet; the words after it are looked at all the same.
        word += 1;
        continue;
      }
      // Final: the place moves past it.
      final ayah = passage.ayahOf[word];
      final wordFrom = _wordFrom ?? first + from + path.frame[begin - path.lo];
      if (begin == start || _wordFrom != null) {
        if (word == 0 || passage.ayahOf[word - 1] != ayah) {
          _ayahFrom = wordFrom;
          _ayahClean = true;
        }
      }
      next = word + 1;
      _sound = end;
      _frame = first + from + lastFrame + 1;
      _bad = 0;
      _wordFrom = null;
      fresh = false;
      if (next >= passage.words || passage.ayahOf[next] != ayah) {
        if (_ayahClean && _ayahFrom != null) {
          events.add(FollowAyahRead(ayah, _ayahFrom!, _frame));
        }
        _ayahFrom = null;
        _ayahClean = false;
      }
      _passSilent();
      word = next;
    }
    if (next >= passage.words) return events;
    // Speech that is none of the text, where the next word should be.
    final stalled = path.endOther;
    if (stalled != null && stalled == next) {
      final other = path.other[next] ?? const <int>[];
      final sounds = _soundsIn(lp, from, other);
      if (sounds >= _stallSounds) {
        if (fresh || wrong) {
          _dropTo(first + from + other.last - 4);
        } else {
          _stall(lp, from, other, first, events, mistake: true);
        }
      } else if (sounds >= _backSounds && !fresh && !wrong) {
        // Too little to call a mistake, enough to be two short words
        // read again.
        _stall(lp, from, other, first, events, mistake: false);
      }
    } else if (midWord &&
        _sound == soundBefore &&
        path.frame[_sound - path.lo] < 0 &&
        _soundsIn(lp, from, <int>[for (var t = 0; t < count; t++) t]) >=
            _stallSounds) {
      // The word was begun and something else followed.
      _sound = passage.wordStart[next];
      _bad = 0;
      _wordFrom = null;
      _miss(events);
      _dropTo(_now - 4);
    }
    return events;
  }

  /// The sound at [i] of the passage was not heard where the path has it.
  /// A short vowel before its long one is let off when the long one is
  /// there: the model often writes the two as the long vowel alone.
  bool _unfit(_Path path, int i) {
    if (path.best[i - path.lo] >= _goodSound) return false;
    const long = <int, int>{32: 29, 34: 30, 33: 31}; // َ ا, ِ ۦ, ُ ۥ
    final after = long[passage.sounds[i]];
    return after == null ||
        i + 1 >= passage.sounds.length ||
        passage.sounds[i + 1] != after ||
        i + 1 - path.lo >= path.best.length ||
        path.best[i + 1 - path.lo] < _goodSound;
  }

  int _lastFrame(_Path path) {
    var last = 0;
    for (final frame in path.frame) {
      if (frame > last) last = frame;
    }
    return last;
  }

  void _dropTo(int frame) {
    if (frame > _frame) _frame = frame;
  }

  /// The lens goes to [word]. One waited for in red is read only when
  /// all of it has been heard ([whole]): its first sounds may be those of
  /// another word.
  void _place(int word, List<FollowEvent> events, {required bool whole}) {
    if (word == next && whole) wrong = false;
    if (wrong || _shown == word) return;
    _shown = word;
    events.add(FollowPlace(word));
  }

  void _miss(List<FollowEvent> events) {
    _ayahClean = false;
    if (wrong || fresh) return;
    wrong = true;
    _shown = null;
    events.add(FollowMiss(next));
  }

  /// Sounds the model hears in these frames, whatever they are.
  int _soundsIn(Float32List lp, int from, List<int> frames) {
    var sounds = 0;
    var previous = 0;
    for (final t in frames) {
      final row = (from + t) * recitationClasses;
      var top = 0;
      for (var c = 1; c < recitationClasses; c++) {
        if (lp[row + c] > lp[row + top]) top = c;
      }
      if (top != 0 && top != previous && lp[row + top] > -.7) sounds += 1;
      previous = top;
    }
    return sounds;
  }

  /// Other speech where the next word should be: the last word said
  /// again (no mistake), two words from before (the reader went back), or
  /// a mistake.
  void _stall(
    Float32List lp,
    int from,
    List<int> other,
    int first,
    List<FollowEvent> events, {
    required bool mistake,
  }) {
    var back = next;
    var words = 0;
    while (back > 0 && words < 10) {
      back -= 1;
      if (!passage.silent(back)) words += 1;
    }
    final begin = other.first;
    final count = other.last - begin + 1;
    final drop = first + from + other.last - 4;
    if (passage.wordStart[back] >= passage.wordStart[next]) {
      if (mistake) {
        _miss(events);
        _dropTo(drop);
      }
      return;
    }
    final path = _align(
      lp,
      from + begin,
      count,
      passage.wordStart[back],
      prior: false,
      boundary: true,
      skip: false,
      anyStart: true,
      until: next,
    );
    int? firstRead;
    int? lastRead;
    for (var word = back; word < next; word++) {
      if (passage.silent(word)) continue;
      var bad = 0;
      var done = true;
      for (var i = passage.wordStart[word]; i < passage.wordEnd[word]; i++) {
        if (path.frame[i - path.lo] < 0) {
          done = false;
          break;
        }
        if (_unfit(path, i)) bad += 1;
      }
      final read =
          done &&
          bad <=
              _allowedBad(passage.wordEnd[word] - passage.wordStart[word]) -
                  (passage.wordEnd[word] - passage.wordStart[word] < 4 ? 1 : 0);
      if (read) {
        firstRead ??= word;
        lastRead = word;
      } else if (firstRead != null) {
        break;
      }
    }
    if (firstRead != null && lastRead! > firstRead) {
      // Back to after the words read again.
      next = lastRead + 1;
      _sound = passage.wordEnd[lastRead];
      _bad = 0;
      _wordFrom = null;
      _ayahFrom = null;
      _ayahClean = false;
      _shown = null;
      _passSilent();
      _frame = drop;
      events.add(FollowPlace(lastRead));
    } else if (!mistake) {
      return;
    } else if (firstRead != null && lastRead == next - 1) {
      _dropTo(drop);
    } else {
      _miss(events);
      _dropTo(drop);
    }
  }

  /// The best path of [count] frames from [from] over the text from sound
  /// [lo]; it may end anywhere. Before each word there may be speech that
  /// is not the text; with [skip], words may be left out; with [anyStart]
  /// the path begins with any word.
  _Path _align(
    Float32List lp,
    int from,
    int count,
    int lo, {
    required bool prior,
    required bool boundary,
    required bool skip,
    bool anyStart = false,
    int? until,
  }) {
    final sounds = passage.sounds;
    var hi = math.min(sounds.length, lo + _ahead);
    if (until != null) {
      hi = passage.wordStart[until];
    } else if (hi < sounds.length) {
      hi = passage.wordEnd[passage.wordOf[hi - 1]];
    }
    final length = hi - lo;
    // Words that begin in the slice.
    final firstWord = passage.wordOf[prior ? lo + 1 : lo];
    final starts = <int>[]; // word → its first sound, within the slice
    final wordIds = <int>[];
    for (
      var word = boundary ? firstWord : firstWord + 1;
      word < passage.words && passage.wordStart[word] < hi;
      word++
    ) {
      if (passage.silent(word)) continue;
      starts.add(passage.wordStart[word] - lo);
      wordIds.add(word);
    }
    final lattice = 2 * length + 1;
    final states = lattice + starts.length;
    var score = Float64List(states)..fillRange(0, states, _never);
    var nextScore = Float64List(states);
    final back = Int16List(count * states);
    if (prior) {
      score[1] = 0;
      score[2] = 0;
    }
    if (anyStart) {
      for (var j = 0; j < starts.length; j++) {
        score[lattice + j] = 0;
      }
    } else if (boundary && starts.isNotEmpty) {
      score[lattice] = 0;
    }
    final entry = Int32List(length)..fillRange(0, length, -1);
    for (var j = 0; j < starts.length; j++) {
      entry[starts[j]] = j;
    }
    for (var t = 0; t < count; t++) {
      final row = (from + t) * recitationClasses;
      // A frame on which the model hears a sound, however unsure of it,
      // is no silence: passing over it costs what a wrong sound does.
      var heard = false;
      for (var c = 1; c < recitationClasses; c++) {
        if (lp[row + c] > lp[row]) {
          heard = true;
          break;
        }
      }
      final blank = heard ? _floor : math.max(lp[row], _floor);
      final at = t * states;
      nextScore[0] = score[0] + blank;
      back[at] = 0;
      for (var i = 0; i < length; i++) {
        final symbol = 2 * i + 1;
        final after = symbol + 1;
        // The sound: held, begun after silence, after the sound before
        // it, or said again (one more count).
        var best = score[symbol];
        var source = symbol;
        if (score[symbol - 1] > best) {
          best = score[symbol - 1];
          source = symbol - 1;
        }
        if (i > 0 &&
            sounds[lo + i] != sounds[lo + i - 1] &&
            score[symbol - 2] > best) {
          best = score[symbol - 2];
          source = symbol - 2;
        }
        if (score[after] > best) {
          best = score[after];
          source = after;
        }
        final j = entry[i];
        if (j >= 0) {
          if (score[lattice + j] > best) {
            best = score[lattice + j];
            source = lattice + j;
          }
          if (skip) {
            for (var k = j - 1; k >= 0 && j - k <= _maxSkip; k--) {
              final jump = score[lattice + k] + _skipPrice;
              if (jump > best) {
                best = jump;
                source = lattice + k;
              }
            }
          }
        }
        nextScore[symbol] = best + math.max(lp[row + sounds[lo + i]], _floor);
        back[at + symbol] = source;
        if (score[after] >= score[symbol]) {
          nextScore[after] = score[after] + blank;
          back[at + after] = after;
        } else {
          nextScore[after] = score[symbol] + blank;
          back[at + after] = symbol;
        }
      }
      final other = heard ? _otherSound : math.max(lp[row], _otherSound);
      for (var j = 0; j < starts.length; j++) {
        final state = lattice + j;
        var best = score[state];
        var source = state;
        if (starts[j] > 0) {
          final end = 2 * (starts[j] - 1) + 1;
          if (score[end] > best) {
            best = score[end];
            source = end;
          }
          if (score[end + 1] > best) {
            best = score[end + 1];
            source = end + 1;
          }
        }
        nextScore[state] = best + other;
        back[at + state] = source;
      }
      final swap = score;
      score = nextScore;
      nextScore = swap;
    }
    var state = 0;
    for (var s = 1; s < states; s++) {
      if (score[s] > score[state]) state = s;
    }
    final frame = Int32List(length)..fillRange(0, length, -1);
    final best = Float64List(length)..fillRange(0, length, _never);
    final other = <int, List<int>>{};
    final skips = <(int, int, int)>[];
    final endOther = state >= lattice ? wordIds[state - lattice] : null;
    for (var t = count - 1; t >= 0; t--) {
      if (state >= lattice) {
        (other[wordIds[state - lattice]] ??= <int>[]).add(t);
      } else if (state.isOdd) {
        final i = state ~/ 2;
        frame[i] = t;
        final value = lp[(from + t) * recitationClasses + sounds[lo + i]];
        if (value > best[i]) best[i] = value;
      }
      final source = back[t * states + state];
      if (source >= lattice && state < lattice) {
        final to = entry[state ~/ 2];
        if (to != source - lattice) {
          skips.add((wordIds[source - lattice], wordIds[to], t));
        }
      }
      state = source;
    }
    for (final frames in other.values) {
      frames.sort();
    }
    return _Path(lo, frame, best, other, skips.reversed.toList(), endOther);
  }
}

/// A tajweed remark of the trial build: kind as in [ExpectedAyah.units],
/// the word in its ayah, counts heard.
typedef TajweedRemark = ({int kind, int word, int heard, int expected});

/// Reads an ayah's tajweed from the model's frames of the whole ayah,
/// the way the rule engine shipped with the model does (imam.py), for the
/// three rules the trial remarks on. Nothing when the ayah as heard is
/// far from its text.
List<TajweedRemark> tajweedRemarks(
  Float32List lp,
  int frames,
  ExpectedAyah ayah,
) {
  final heard = <int>[];
  final sure = <double>[];
  var previous = 0;
  for (var t = 0; t < frames; t++) {
    final row = t * recitationClasses;
    var top = 0;
    for (var c = 1; c < recitationClasses; c++) {
      if (lp[row + c] > lp[row + top]) top = c;
    }
    if (top != 0 && top != previous) {
      heard.add(top);
      sure.add(math.exp(lp[row + top]));
    }
    previous = top;
  }
  final text = ayah.sounds;
  final n = text.length;
  final m = heard.length;
  if (m == 0) return const <TajweedRemark>[];
  // Edit distance, then where each sound of the text falls in the heard.
  final cost = List<Int32List>.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = 0; i <= n; i++) {
    cost[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    cost[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      cost[i][j] = math.min(
        cost[i - 1][j - 1] + (text[i - 1] == heard[j - 1] ? 0 : 1),
        math.min(cost[i - 1][j] + 1, cost[i][j - 1] + 1),
      );
    }
  }
  if (cost[n][m] > n * .15) return const <TajweedRemark>[];
  final at = Int32List(n + 1);
  var i = n;
  var j = m;
  at[n] = m;
  while (i > 0) {
    if (j > 0 &&
        cost[i][j] ==
            cost[i - 1][j - 1] + (text[i - 1] == heard[j - 1] ? 0 : 1)) {
      i -= 1;
      j -= 1;
    } else if (j > 0 && cost[i][j] == cost[i][j - 1] + 1) {
      j -= 1;
      continue;
    } else {
      i -= 1;
    }
    at[i] = j;
  }
  int run(int from, int to, int sound) {
    var k = -1;
    for (var x = from; x < to; x++) {
      if (heard[x] == sound) {
        k = x;
        break;
      }
    }
    if (k < 0) return 0;
    var s = k;
    var e = k;
    while (s > 0 && heard[s - 1] == sound) {
      s -= 1;
    }
    while (e < m && heard[e] == sound) {
      e += 1;
    }
    return e - s;
  }

  final remarks = <TajweedRemark>[];
  for (final (kind, start, end, word, golden) in ayah.units) {
    final from = math.max(0, at[start] - 1);
    final to = math.min(m, at[end] + 1);
    var unsure = false;
    for (var x = from; x < to; x++) {
      if (sure[x] < .3) unsure = true;
    }
    if (unsure) continue;
    final count = run(from, to, text[start]);
    final short = kind == 2 ? count <= 2 : count < golden;
    if (short) {
      remarks.add((kind: kind, word: word, heard: count, expected: golden));
    }
  }
  return remarks;
}
