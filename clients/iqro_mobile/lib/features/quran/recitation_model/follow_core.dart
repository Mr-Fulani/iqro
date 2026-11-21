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
  ExpectedAyah(
    this.sounds,
    this.spans,
    this.units, [
    this.loose = const {},
    this.added = const {},
  ]);

  /// Class of each sound, 1..42, as a correct reading has them: a long
  /// vowel once per count.
  final Uint8List sounds;

  /// Per word, where its sounds begin and end in [sounds].
  final List<(int, int)> spans;

  /// The places remarked on: kind (0 ghunnah, 1 idgham with ghunnah,
  /// 2 madd muttasil, 3 a letter with a shaddah, 4 a natural madd, 5 a
  /// clear nun before a throat letter), start, end, word, counts
  /// expected.
  final List<(int, int, int, int, int)> units;

  /// The sounds of [sounds] that need not be heard: those a word has only
  /// when the reader stops on it, only when the reading goes on from it,
  /// or only when it is begun after a stop. A reader may stop on any
  /// word.
  final Set<int> loose;

  /// Those of [loose] that the ayah read through does not have: the
  /// sounds of a stop (the "h" a ta marbuta is stopped on, the echo of a
  /// qalqalah) and of a word begun anew after one.
  final Set<int> added;

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
      json.length > 3 ? (json[3] as List).cast<int>().toSet() : const {},
      json.length > 4 ? (json[4] as List).cast<int>().toSet() : const {},
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
      final firstWord = wordStart.length;
      // Where each sound of the ayah as written is in [sounds].
      final at = List<int>.filled(ayah.sounds.length, 0);
      for (final (start, end) in ayah.spans) {
        wordStart.add(sounds.length);
        for (var i = start; i < end; i++) {
          if (i == start || ayah.sounds[i] != ayah.sounds[i - 1]) {
            sounds.add(ayah.sounds[i]);
            wordOf.add(wordStart.length - 1);
            optional.add(ayah.loose.contains(i));
            own.add(!ayah.added.contains(i));
          } else {
            if (!ayah.loose.contains(i)) optional.last = false;
            if (!ayah.added.contains(i)) own.last = true;
          }
          at[i] = sounds.length - 1;
        }
        wordEnd.add(sounds.length);
        ayahOf.add(number);
      }
      for (final (kind, start, end, word, golden) in ayah.units) {
        if (end <= start || end > at.length) continue;
        final unit = (
          kind: kind,
          first: at[start],
          last: at[end - 1],
          sound: ayah.sounds[start],
          golden: golden,
          word: firstWord + word,
        );
        (unitsOf[wordOf[unit.last]] ??= <TajweedPlace>[]).add(unit);
      }
    }
    this.sounds = Uint8List.fromList(sounds);
  }

  late final Uint8List sounds;
  final wordStart = <int>[];
  final wordEnd = <int>[];
  final wordOf = <int>[];
  final ayahOf = <int>[];

  /// Per sound: it need not be heard ([ExpectedAyah.loose]).
  final optional = <bool>[];

  /// Per sound: the ayah read through has it ([ExpectedAyah.added] does
  /// not list it).
  final own = <bool>[];

  /// The places whose tajweed is looked at, by the word their last sound
  /// is in.
  final unitsOf = <int, List<TajweedPlace>>{};

  int get words => wordStart.length;
  bool silent(int word) => wordEnd[word] == wordStart[word];
}

/// A place of one of the three rules the trial remarks on: its kind (as
/// in [ExpectedAyah.units]), the sounds of the passage it runs over, the
/// sound held, how many counts a right reading has, and the word it is
/// shown on.
typedef TajweedPlace = ({
  int kind,
  int first,
  int last,
  int sound,
  int golden,
  int word,
});

/// What a step of the follower found.
sealed class FollowEvent {}

/// The reader is on [word], or has read it: it is written as read.
class FollowPlace extends FollowEvent {
  FollowPlace(this.word);
  final int word;
}

/// [word] was left out or said as another: it is written in red and waited on.
class FollowMiss extends FollowEvent {
  FollowMiss(
    this.word, {
    this.why = FollowWhy.unknown,
    this.expected = 0,
    this.heard = 0,
  });
  final int word;

  /// Why, as far as the follower can say; [FollowWhy.unknown] when it
  /// cannot: a reason made up is worse than none.
  final FollowWhy why;

  /// With [FollowWhy.another]: the sound written and the sound heard in
  /// its place (classes of the model).
  final int expected;
  final int heard;
}

/// Why a word is waited on in red.
enum FollowWhy {
  /// What was said is not the word: no more can be said of it.
  unknown,

  /// The reader went on with a later word.
  skipped,

  /// Another letter or short vowel was heard for sure in a sound's place.
  another,

  /// A ghunnah all but left out; a madd held half as long as it is to be.
  ghunnah,
  madd,

  /// A letter with a shaddah said once; a nun held where it is said
  /// clearly and short (izhar).
  shaddah,
  izhar,
}

/// A word taken as read has a place whose tajweed may be looked at: its
/// held sound lies between these frames.
class FollowHeld extends FollowEvent {
  FollowHeld(this.place, this.fromFrame, this.toFrame);
  final TajweedPlace place;
  final int fromFrame;
  final int toFrame;
}

// The long vowel each short one is written as when it is held: َ ا, ُ ۥ, ِ ۦ.
const _heldAs = <int, int>{32: 29, 33: 31, 34: 30};
const _floor = -10.0; // the most a sound that does not fit costs
const _otherSound = -6.0; // a frame of speech that is not the text
const _skipPrice = -10.0; // going on with a later word
const _maxSkip = 14; // words that may be left out at once
const _ahead = 70; // sounds of the text looked at ahead of the place
// A sound of the ayah read through that a stop leaves unsaid: not free, or
// a word with a letter left out would sooner pass for read than for left
// out.
const _unsaidPrice = -10.0;
const _maxLoose = 7; // sounds in a row that need not be heard
const _overFrames = 50; // frames after which a word is over, whatever follows
const _settle = 10; // frames a word has been over before it is final
const _stallSounds = 10; // sounds of other speech that are a mistake
const _skipSounds = 3; // sounds of a later word that are a word left out
const _alikeSounds = 5; // … of one that begins as the word expected
const _backSounds = 6; // … that may be two words read again
const _pauseFrames = 10; // frames of silence that are a stop
const _qalqalah = 38; // ڇ
const _nun = 25;
const _ikhfa = 39; // ں
const _iqlab = 40; // ۾
const _longWord = 9; // sounds of a word that may have two unfit
const _goodSound = -4.0;
const _absentSound = -12.0; // a sound the model does not hear at all
const _sureSound = -.36; // log .7: the model is sure of what it hears
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

  /// The last sound heard of the word before [_sound], when the sounds
  /// after it in that word need not be heard and were not: the reading
  /// goes on from it.
  int? _heard;
  var _heardBefore = -1;
  var _now = 0;

  /// Sounds of the word being read that did not fit, among the final ones.
  var _bad = 0;

  /// Nothing read rightly since the start or [moveTo]: what is said
  /// before the first word (isti'adha, basmala) is no mistake.
  var fresh = true;
  var wrong = false;
  int? _shown;

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
    _heard = null;
    _bad = 0;
    fresh = true;
    wrong = false;
    _shown = null;
    _passSilent();
  }

  /// Sounds of a word that may not fit while it still counts as read:
  /// one, which is what the model mishears of a right reading.
  /// [word], taken as read, is to be read again (a ghunnah or a madd of
  /// it was held far too short): the place goes back to wait on it.
  void sayAgain(int word) {
    next = word;
    _sound = passage.wordStart[word];
    _frame = _now;
    _heard = null;
    _bad = 0;
    fresh = false;
    wrong = true;
    _shown = null;
  }

  static int _allowedBad(int sounds) => sounds >= _longWord
      ? 2
      : sounds >= 3
      ? 1
      : 0;

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
      _sound == 0
          ? 0
          : _heardBefore == _sound && _heard != null
          ? _heard!
          : _sound - 1,
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
      // A later word that begins as the one expected does ("yunfiquna",
      // and the "yu'minuna" after it) takes more: for a moment in the
      // middle of a word the model may hear that one.
      final alike =
          passage.wordEnd[next] - passage.wordStart[next] >= 2 &&
          passage.wordEnd[word] - passage.wordStart[word] >= 2 &&
          passage.sounds[passage.wordStart[next]] ==
              passage.sounds[passage.wordStart[word]] &&
          passage.sounds[passage.wordStart[next] + 1] ==
              passage.sounds[passage.wordStart[word] + 1];
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
          math.min(
            alike ? _alikeSounds : _skipSounds,
            passage.wordEnd[word] - passage.wordStart[word],
          )) {
        _miss(events, why: FollowWhy.skipped);
        _dropTo(first + from + _lastFrame(path) + 1);
      }
      return events;
    }
    // The frame of the last sound heard of the word before, in this step.
    var previousFrame = -1;
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
      // Sounds that need not be heard and were not: said with the next
      // one that was, or with the word's end.
      var passed = 0;
      int? heard;
      var firstFrame = -1;
      for (var i = begin; i <= end; i++) {
        if (i == end) {
          said += passed;
          break;
        }
        final at = path.frame[i - path.lo];
        if (at < 0) {
          if (!passage.optional[i]) break;
          passed += 1;
          continue;
        }
        said += passed + 1;
        passed = 0;
        heard = i;
        if (firstFrame < 0) firstFrame = at;
        lastFrame = at;
      }
      // How the word's ends are to sound: as a stop has them only where
      // the reader did stop. A word read on from, or on to, has the
      // sounds of reading on, and another short vowel there is a mistake
      // as anywhere.
      final whole = begin + said >= end;
      final joinedBefore =
          whole &&
          !fresh &&
          begin == start &&
          firstFrame >= 0 &&
          !_silent(lp, from, word == next ? -1 : previousFrame, firstFrame);
      // Null while it cannot be told yet: the word's last sound is still
      // held, or the silence after it is short so far.
      final stopped = whole && lastFrame >= 0 && heard != null
          ? _stoppedAfter(
              lp,
              from,
              lastFrame,
              last,
              <int>{
                // The next word begun; more of this word itself is not it.
                for (var i = end; i < end + 3 && i < passage.sounds.length; i++)
                  passage.sounds[i],
              }..removeAll(<int>[
                for (var i = heard; i < end; i++) passage.sounds[i],
              ]),
            )
          : null;
      final joinedAfter = stopped == false;
      // Final only once it is known, where it matters: the word has an
      // ending that a stop changes. Not for long: other speech after the
      // word is neither a stop nor the next word.
      var waiting = false;
      if (stopped == null && lastFrame > last - 2 * _settle) {
        for (var i = end - 1; i >= start && !waiting; i--) {
          if (!passage.optional[i]) break;
          waiting = passage.own[i];
        }
      }
      for (var i = begin; i < begin + said; i++) {
        final strict = _asReadOn(i, start, end, joinedBefore, joinedAfter);
        if (path.frame[i - path.lo] < 0) {
          // Passed over: unsaid, where reading on has it.
          if (strict && !_lastVowel(i)) bad += 1;
        } else if (_unfit(path, i, strict: strict)) {
          bad += 1;
        }
      }
      if (lastFrame >= 0) previousFrame = lastFrame;
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
      // Another letter or short vowel heard for sure in a sound's place,
      // or more than one sound that does not fit: said as another.
      int? otherAt;
      int? otherHeard;
      for (var i = begin; i < end && otherHeard == null; i++) {
        otherHeard = _saidAsAnother(
          path,
          i,
          lp,
          from,
          strict: _asReadOn(i, start, end, joinedBefore, joinedAfter),
        );
        if (otherHeard != null) otherAt = i;
      }
      // A qalqalah that is not there at all: the echo a letter of "qutb
      // jad" has when it stands with no vowel. Not at the end of an ayah,
      // where it is there only if the reader stops.
      if (otherHeard == null) {
        final ayahEnds =
            word + 1 >= passage.words ||
            passage.ayahOf[word + 1] != passage.ayahOf[word];
        for (var i = begin; i < end; i++) {
          if (passage.sounds[i] != _qalqalah || passage.optional[i]) continue;
          if (ayahEnds && i + 1 == end) continue;
          final at = path.frame[i - path.lo];
          if (at >= 0 && path.best[i - path.lo] < _absentSound) {
            otherAt = i;
            otherHeard = 0;
            break;
          }
        }
      }
      final other = otherHeard != null;
      final asAnother = other || bad > _allowedBad(end - start);
      if (asAnother || bad > allowed) {
        // Sounds that do not fit are no mistake while the word may still
        // be going on: read slowly, the model hears the middle of a word
        // wrongly for a while and puts it right as more of it comes.
        // (Another letter heard for sure is one at once: waiting for it
        // too lets a changed vowel by now and then.)
        if (word == next &&
            lastFrame <= last - _settle &&
            (other || _over(path, lp, from, end, lastFrame, last))) {
          trace?.call('rejected word=$word other=$other bad=$bad');
          _sound = start;
          _bad = 0;
          // Even as the first word read, when it is this word that was
          // said: a long word that began as written and has at least
          // half of its sounds ("alif lam ra" for "alif lam mim"). What
          // is said before the first word begins otherwise.
          if (asAnother) {
            var began = end - start >= 6 && bad * 2 <= end - start;
            for (var i = start; began && i < start + 3; i++) {
              began = !_unfit(path, i);
            }
            _miss(
              events,
              first: began,
              why: other ? FollowWhy.another : FollowWhy.unknown,
              expected: other ? passage.sounds[otherAt!] : 0,
              heard: otherHeard ?? 0,
            );
          }
          _dropTo(first + from + lastFrame + 1);
        }
        break;
      }
      _place(word, events, whole: true);
      if (word != next || lastFrame > last - _settle || waiting) {
        // Not final yet; the words after it are looked at all the same.
        word += 1;
        continue;
      }
      // Final: the place moves past it.
      _judge(
        word,
        begin,
        path,
        lp,
        first + from,
        from,
        last,
        lastFrame,
        events,
      );
      next = word + 1;
      _sound = end;
      _heard = heard;
      _heardBefore = end;
      _frame = first + from + lastFrame + 1;
      _bad = 0;
      fresh = false;
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
      _miss(events);
      _dropTo(_now - 4);
    }
    return events;
  }

  /// The word whose sounds end at [end] of the passage, the last of them
  /// on frame [lastFrame], is over: the reader went silent after it, the
  /// next word has begun, or a second has gone by.
  bool _over(
    _Path path,
    Float32List lp,
    int from,
    int end,
    int lastFrame,
    int last,
  ) {
    if (lastFrame <= last - _overFrames) return true;
    var silent = 0;
    for (var t = lastFrame + 1; t <= last; t++) {
      // What the microphone's silence is written as (hushSilence).
      final row = (from + t) * recitationClasses;
      silent = lp[row] == 0 && lp[row + 1] == -20 ? silent + 1 : 0;
      if (silent >= _settle) return true;
    }
    var begun = 0;
    for (var i = end; i - path.lo < path.frame.length && i < end + 6; i++) {
      if (path.frame[i - path.lo] > lastFrame &&
          path.best[i - path.lo] >= _goodSound) {
        begun += 1;
      }
    }
    return begun >= 2;
  }

  /// The sound at [i] of the passage was not heard where the path has it.
  /// A short vowel before its long one is let off when the long one is
  /// there: the model often writes the two as the long vowel alone.
  bool _unfit(_Path path, int i, {bool strict = false}) {
    if (path.best[i - path.lo] >= _goodSound) return false;
    // Nor is a sound that is said only with a stop, or only without one,
    // unless the reader did not stop ([strict]).
    if (passage.optional[i] && !strict) return false;
    // A word's last short vowel is not said when the reader stops on it.
    if (_lastVowel(i)) return false;
    const long = <int, int>{32: 29, 34: 30, 33: 31}; // َ ا, ِ ۦ, ُ ۥ
    final after = long[passage.sounds[i]];
    return after == null ||
        i + 1 >= passage.sounds.length ||
        passage.sounds[i + 1] != after ||
        i + 1 - path.lo >= path.best.length ||
        path.best[i + 1 - path.lo] < _goodSound;
  }

  /// The sound at [i] is the last short vowel its word has when read on.
  bool _lastVowel(int i) {
    final sound = passage.sounds[i];
    if (sound < 32 || sound > 34) return false;
    final end = passage.wordEnd[passage.wordOf[i]];
    for (var k = i + 1; k < end; k++) {
      if (passage.own[k]) return false;
    }
    return true;
  }

  /// The sound at [i] of the word from [start] to [end] is one that
  /// reading on has and a stop does not, at an end of the word the reader
  /// did not stop at: it is asked for as any sound is.
  bool _asReadOn(
    int i,
    int start,
    int end,
    bool joinedBefore,
    bool joinedAfter,
  ) {
    if (!passage.optional[i] || !passage.own[i]) return false;
    if (joinedAfter) {
      var trailing = true;
      for (var k = i + 1; k < end && trailing; k++) {
        trailing = passage.optional[k];
      }
      if (trailing) return true;
    }
    if (joinedBefore) {
      var leading = true;
      for (var k = start; k < i && leading; k++) {
        leading = passage.optional[k];
      }
      if (leading) return true;
    }
    return false;
  }

  /// Whether the reader was silent for a moment between the frames [after]
  /// and [before] of the path: a stop.
  bool _silent(Float32List lp, int from, int after, int before) {
    var run = 0;
    for (var t = after + 1; t < before; t++) {
      run = _top(lp, from + t) == 0 ? run + 1 : 0;
      if (run >= _pauseFrames) return true;
    }
    return false;
  }

  /// Whether the reader stopped after a word whose last sound heard was
  /// first on frame [after]: silence for a moment. False when one of
  /// [next], the sounds the next word begins with, comes before any such
  /// silence; null when neither has come by the frame [last].
  bool? _stoppedAfter(
    Float32List lp,
    int from,
    int after,
    int last,
    Set<int> next,
  ) {
    var run = 0;
    for (var t = after + 1; t <= last; t++) {
      final top = _top(lp, from + t);
      if (top == 0) {
        run += 1;
        if (run >= _pauseFrames) return true;
      } else if (next.contains(top)) {
        return false;
      } else {
        run = 0;
      }
    }
    return null;
  }

  /// What the model hears most on a frame; 0 is nothing.
  int _top(Float32List lp, int frame) {
    final row = frame * recitationClasses;
    var top = 0;
    for (var c = 1; c < recitationClasses; c++) {
      if (lp[row + c] > lp[row + top]) top = c;
    }
    return top;
  }

  /// What may be said of how a word just taken as read was read: where
  /// its ghunnah or madd was held, a sound that was not the text's.
  void _judge(
    int word,
    int begin,
    _Path path,
    Float32List lp,
    int first,
    int from,
    int last,
    int lastFrame,
    List<FollowEvent> events,
  ) {
    final end = passage.wordEnd[word];
    for (final unit in passage.unitsOf[word] ?? const <TajweedPlace>[]) {
      // From where its sound begins (the frames before this step's path
      // are those of the word before) to the next sound.
      var start = 0;
      if (unit.first >= path.lo && path.frame[unit.first - path.lo] >= 0) {
        start = path.frame[unit.first - path.lo];
      }
      final stop = unit.last + 1 < end
          ? path.frame[unit.last + 1 - path.lo]
          : math.min(last, lastFrame + _settle);
      if (stop > start) {
        events.add(FollowHeld(unit, first + start, first + stop));
      }
    }
  }

  /// The sound at [i] was said as another: where the path has it the
  /// model is sure of a different letter or short vowel, one that is not
  /// a neighbour of it in the word (a neighbour there means only that
  /// the sound was not heard). That sound, or null.
  int? _saidAsAnother(
    _Path path,
    int i,
    Float32List lp,
    int from, {
    bool strict = false,
  }) {
    final expected = passage.sounds[i];
    final letter = expected >= 1 && expected <= 28;
    final vowel = expected >= 32 && expected <= 34;
    // The nun that is hidden (ikhfa) or turned into a mim (iqlab).
    final hidden = expected == _ikhfa || expected == _iqlab;
    // A letter must not be heard at all where it is written (the model
    // half-hears a right one often enough), nor the hidden nun; a short
    // vowel is either there or not.
    if (!(letter || vowel || hidden) ||
        (passage.optional[i] && !strict) ||
        path.best[i - path.lo] >= (vowel ? _goodSound : _absentSound)) {
      return null;
    }
    final at = path.frame[i - path.lo];
    final row = (from + at) * recitationClasses;
    var top = 1;
    for (var c = 2; c < recitationClasses; c++) {
      if (lp[row + c] > lp[row + top]) top = c;
    }
    // A letter for a letter, a short vowel for a short vowel; for the
    // hidden nun a plain one, said clearly where it is to be hidden.
    final same = hidden
        ? top == _nun
        : letter
        ? top <= 28
        : top >= 32 && top <= 34;
    if (!same || top == expected || lp[row + top] < _sureSound) return null;
    // A nun read as a mim or a mim as a nun is the rules' doing.
    if ((expected == 24 && top == 23) || (expected == 23 && top == 24)) {
      return null;
    }
    for (var k = i - 2; k <= i + 2; k++) {
      if (k == i || k < path.lo || k - path.lo >= path.frame.length) continue;
      final frame = path.frame[k - path.lo];
      if (passage.sounds[k] == top && frame >= 0 && (frame - at).abs() <= 2) {
        return null;
      }
    }
    return top;
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

  /// [word] is the place. One waited for in red is read only when
  /// all of it has been heard ([whole]): its first sounds may be those of
  /// another word.
  void _place(int word, List<FollowEvent> events, {required bool whole}) {
    if (word == next && whole) wrong = false;
    if (wrong || _shown == word) return;
    _shown = word;
    events.add(FollowPlace(word));
  }

  void _miss(
    List<FollowEvent> events, {
    bool first = false,
    FollowWhy why = FollowWhy.unknown,
    int expected = 0,
    int heard = 0,
  }) {
    if (wrong || (fresh && !first)) return;
    wrong = true;
    _shown = null;
    events.add(FollowMiss(next, why: why, expected: expected, heard: heard));
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
          if (passage.optional[i]) continue;
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
    final starts = <int>[]; // word → its first sound, within the slice
    final wordIds = <int>[];
    for (
      var word = passage.wordOf[lo];
      word < passage.words && passage.wordStart[word] < hi;
      word++
    ) {
      // (After a sound said before, that sound's word has begun; so has
      // the word the path is to go on in the middle of.)
      if (passage.wordStart[word] < (prior ? lo + 1 : lo)) continue;
      if (!boundary && passage.wordStart[word] == lo) continue;
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
    // The word each sound is in, among [starts]; -1 before the first.
    final wordAt = Int32List(length)..fillRange(0, length, -1);
    for (var j = 0; j < starts.length; j++) {
      entry[starts[j]] = j;
      final end = j + 1 < starts.length ? starts[j + 1] : length;
      for (var i = starts[j]; i < end; i++) {
        wordAt[i] = j;
      }
    }
    final optional = passage.optional;
    for (var t = 0; t < count; t++) {
      final row = (from + t) * recitationClasses;
      // A frame on which the model hears a sound, however unsure of it,
      // is no silence: passing over it costs what a wrong sound does.
      // What the model writes on the frame; 0 is nothing.
      var top = 0;
      for (var c = 1; c < recitationClasses; c++) {
        if (lp[row + c] > lp[row + top]) top = c;
      }
      final heard = top != 0;
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
        // Past sounds that need not be heard, for nothing: from the sound
        // before them, or from before the word they begin.
        var price = 0.0;
        for (var k = i - 1; k >= 0 && i - k <= _maxLoose; k--) {
          if (!optional[lo + k]) break;
          if (passage.own[lo + k]) price += _unsaidPrice;
          final first = entry[k];
          if (first >= 0 && score[lattice + first] + price > best) {
            best = score[lattice + first] + price;
            source = lattice + first;
          }
          if (k == 0) break;
          final before = 2 * (k - 1) + 1;
          if (sounds[lo + i] != sounds[lo + k - 1] &&
              score[before] + price > best) {
            best = score[before] + price;
            source = before;
          }
          if (score[before + 1] + price > best) {
            best = score[before + 1] + price;
            source = before + 1;
          }
        }
        // A short vowel held is written by the model as its long one
        // ("bi-i-him" read slowly): more of the same sound, not speech
        // that the text does not have.
        // Not where the text has that long vowel after it: there it is
        // the long vowel's own sound, whose length is looked at.
        var said = lp[row + sounds[lo + i]];
        final held = _heldAs[sounds[lo + i]];
        // And only on a frame where the long vowel is what the model
        // writes: a guess at one, on a nasal that is held, is not it.
        // Nor a sound that need not be said at all (the vowel a word is
        // begun with after a stop): it would take the long vowels of the
        // word before for its own.
        if (held != null &&
            top == held &&
            !optional[lo + i] &&
            (lo + i + 1 >= sounds.length || sounds[lo + i + 1] != held)) {
          said = lp[row + held];
        }
        nextScore[symbol] = best + math.max(said, _floor);
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
        // After the word before it, whose last sounds need not all be
        // heard.
        var price = 0.0;
        for (var e = starts[j] - 1; e >= 0 && starts[j] - e <= _maxLoose; e--) {
          final end = 2 * e + 1;
          if (score[end] + price > best) {
            best = score[end] + price;
            source = end;
          }
          if (score[end + 1] + price > best) {
            best = score[end + 1] + price;
            source = end + 1;
          }
          if (!optional[lo + e]) break;
          if (passage.own[lo + e]) price += _unsaidPrice;
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
        final to = wordAt[state ~/ 2];
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
