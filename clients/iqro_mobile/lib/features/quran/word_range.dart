import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../audio/audio_models.dart';
import '../audio/audio_repository.dart';
import '../audio/recitation_style_label.dart';
import '../audio/reciter_catalog.dart';
import '../dua/dua_arabic.dart';
import 'quran_models.dart';

/// A word of the Quran: its ayah and its `position_in_verse`.
@immutable
class QuranWord implements Comparable<QuranWord> {
  const QuranWord(this.surah, this.ayah, this.position);

  final int surah;
  final int ayah;
  final int position;

  String get ayahKey => '$surah:$ayah';

  @override
  int compareTo(QuranWord other) {
    if (surah != other.surah) return surah.compareTo(other.surah);
    if (ayah != other.ayah) return ayah.compareTo(other.ayah);
    return position.compareTo(other.position);
  }

  @override
  bool operator ==(Object other) =>
      other is QuranWord &&
      other.surah == surah &&
      other.ayah == ayah &&
      other.position == position;

  @override
  int get hashCode => Object.hash(surah, ayah, position);

  @override
  String toString() => '$surah:$ayah:$position';
}

/// Words from [start] to [end], both included, inside one surah: word
/// timings are offsets in the reciter's surah track.
@immutable
class QuranWordRange {
  const QuranWordRange._(this.start, this.end);

  const QuranWordRange.single(QuranWord word) : start = word, end = word;

  /// The range between two words in either order; null across surahs.
  static QuranWordRange? between(QuranWord a, QuranWord b) {
    if (a.surah != b.surah) return null;
    return a.compareTo(b) <= 0
        ? QuranWordRange._(a, b)
        : QuranWordRange._(b, a);
  }

  final QuranWord start;
  final QuranWord end;

  bool get single => start == end;

  bool contains(QuranWord word) =>
      start.compareTo(word) <= 0 && word.compareTo(end) <= 0;

  /// The end marker of [ayah] stands between two selected words.
  bool spansAyahEnd(int surah, int ayah) =>
      surah == start.surah && ayah >= start.ayah && ayah < end.ayah;

  @override
  bool operator ==(Object other) =>
      other is QuranWordRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final _arabicLetter = RegExp(r'[ء-يٮ-ۓۺ-ۼ]');
final _spaces = RegExp(r'\s+');

/// The words of an ayah's Uthmani text by `position_in_verse`, the first at
/// index 0. A pause or sajda mark written apart belongs to the word before
/// it, as in the Quran Foundation word list.
List<String> quranWords(String text) {
  final words = <String>[];
  for (final token in text.trim().split(_spaces)) {
    if (token.isEmpty) continue;
    if (words.isNotEmpty && !_arabicLetter.hasMatch(token)) {
      words[words.length - 1] = '${words.last} $token';
    } else {
      words.add(token);
    }
  }
  return words;
}

/// The words of [ayah], without the basmala written before the first ayah
/// of most surahs: it is not one of the ayah's words.
List<String> ayahWords(QuranAyah ayah) {
  final parts =
      ayah.number == 1 && ayah.surahNumber != 1 && ayah.surahNumber != 9
      ? splitDuaArabic(ayah.textUthmani)
      : <DuaArabicPart>[DuaArabicPart(ayah.textUthmani)];
  return quranWords(
    parts.where((part) => !part.opening).map((part) => part.text).join(' '),
  );
}

/// The voices, in order, that play words of a reciter without their timings:
/// al-Husary's Muallim, the teaching recitation (else the catalog's teaching
/// reciter), then his Murattal for the ayahs the Muallim has no timings of:
/// where the sheikh repeats words after a pause (2:9, 2:20, 3:7). His Mujawwad
/// shares the `qf-12-` prefix but has no timings at all.
List<Recitation> wordTimingFallbackRecitations(
  Iterable<Recitation> recitations,
) {
  Recitation? byPrefix(String prefix) {
    for (final recitation in recitations) {
      if (recitation.code.startsWith(prefix)) return recitation;
    }
    return null;
  }

  final teaching = byPrefix('qf-12-muallim') ?? teachingRecitation(recitations);
  final murattal = byPrefix('qf-6-');
  return <Recitation>[?teaching, if (murattal?.id != teaching?.id) ?murattal];
}

/// Says whose voice plays the words when it is not the chosen reciter's.
String wordRangeVoiceNote(BuildContext context, Recitation voice) {
  final name = voice.reciter.nameFor(
    Localizations.localeOf(context).languageCode,
  );
  return voice.code.startsWith('qf-12-muallim') || voice.teachingDefault
      ? context.l10n.wordRangeTeachingVoice(name)
      : context.l10n.wordRangeOtherVoice(
          name,
          recitationStyleLabel(context, voice.style),
        );
}

/// Who plays a range: the reciter, its timings of the first and last words'
/// ayahs, and whether the teaching voice stands in for the chosen reciter.
typedef WordRangeVoice = ({
  Recitation recitation,
  AyahPlayback first,
  AyahPlayback last,
  bool teaching,
});

enum WordRepeat { once, three, forever }

/// True while a finger pulls a selection, by a long press or a handle: the
/// panel fades then, so the words under it show.
final wordRangePulling = ValueNotifier<bool>(false);

const wordRangeSelectionColor = Color(0x380B6B57);
const wordRangePlayingColor = Color(0x8CC49647);
const wordRangeHandleColor = Color(0xFF0B6B57);

/// The selected words of a reader and their playback: from the start of the
/// first word to the end of the last, in the Mushaf reciter's surah track.
class WordRangeController extends ChangeNotifier {
  WordRangeController(this._ref)
    : _audio = _ref.read(audioControllerProvider.notifier),
      _repository = _ref.read(audioRepositoryProvider) {
    _removeAudioListener = _audio.addListener(_onAudio, fireImmediately: false);
  }

  final WidgetRef _ref;
  final AudioController _audio;
  final AudioRepository _repository;
  late final void Function() _removeAudioListener;

  QuranWordRange? _range;
  QuranWordRange? get range => _range;

  /// How many words [range] holds, as the reader counted them.
  int wordCount = 0;

  WordRepeat _repeat = WordRepeat.once;
  WordRepeat get repeat => _repeat;

  /// Null while the reciter's word timings are being checked.
  bool? available;
  bool loading = false;
  bool failed = false;
  bool playing = false;
  int round = 1;
  QuranWord? playingWord;

  /// The voice of the range: the Mushaf reciter, or the teaching al-Husary
  /// when [teachingVoice] (the chosen one has no timings of these words).
  Recitation? recitation;
  bool teachingVoice = false;

  final _requests = <String, Future<AyahPlayback?>>{};
  final _timings = <String, AyahPlayback>{};
  String? _mediaId;
  Duration _clipStart = Duration.zero;
  var _wasPlaying = false;
  var _starting = false;
  var _generation = 0;
  var _disposed = false;

  /// True while a clip of this controller is the current audio.
  bool get active => _mediaId != null;

  void select(QuranWordRange range, {required int wordCount}) {
    this.wordCount = wordCount;
    if (range == _range) return;
    final sameStartAyah =
        _range?.start.surah == range.start.surah &&
        _range?.start.ayah == range.start.ayah;
    _range = range;
    if (active) _stopClip();
    // Within the same first ayah the answer stays on screen while the new
    // ends are checked: the voice may change with the last word.
    if (!sameStartAyah || available != true) available = null;
    unawaited(_checkAvailability());
    notifyListeners();
  }

  void clear() {
    if (_range == null && !active) return;
    _generation++;
    _range = null;
    wordCount = 0;
    available = null;
    loading = false;
    failed = false;
    if (active) _stopClip();
    notifyListeners();
  }

  Future<void> setRepeat(WordRepeat value) async {
    if (value == _repeat) return;
    _repeat = value;
    round = 1;
    notifyListeners();
    final id = _mediaId;
    final standalone = _ref.read(audioControllerProvider).standalone;
    if (id != null &&
        standalone?.mediaItem.id == id &&
        standalone!.repeatEnabled != (value == WordRepeat.forever)) {
      await _audio.toggleStandaloneRepeat(id, owner: this);
    }
  }

  /// Plays the range, or pauses and resumes the clip it already plays.
  Future<void> toggle({required String title}) async {
    final id = _mediaId;
    if (id != null &&
        _ref.read(audioControllerProvider).standalone?.mediaItem.id == id) {
      await _audio.toggleStandalone(id, owner: this);
      return;
    }
    await play(title: title);
  }

  Future<void> play({required String title}) async {
    final range = _range;
    if (range == null || loading) return;
    final generation = ++_generation;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final voice = await _voice(range);
      if (!_current(generation, range)) return;
      if (voice == null) {
        available = false;
        return;
      }
      available = true;
      final (:recitation, :first, :last, teaching: _) = voice;
      final from = first.words[range.start.position]!.start;
      final to = last.words[range.end.position]!.end;
      for (
        var ayah = range.start.ayah + 1;
        ayah < range.end.ayah && ayah <= range.start.ayah + 40;
        ayah++
      ) {
        unawaited(_ayah(recitation.id, range.start.surah, ayah));
      }
      final id = 'quran-words:${recitation.id}:${range.start}-${range.end}';
      _mediaId = id;
      _clipStart = from;
      round = 1;
      _wasPlaying = false;
      _starting = true;
      await _audio.loadStandalone(
        id: id,
        url: first.track.url,
        title: title,
        album: 'IQRO · Quran',
        contentType: 'quran-words',
        artist: recitation.reciter.nameEn,
        owner: this,
        clipStart: from,
        clipEnd: to,
      );
      _starting = false;
      if (!_current(generation, range)) return;
      final standalone = _ref.read(audioControllerProvider).standalone;
      if (standalone?.mediaItem.id == id &&
          standalone!.repeatEnabled != (_repeat == WordRepeat.forever)) {
        await _audio.toggleStandaloneRepeat(id, owner: this);
      }
    } on Object {
      _starting = false;
      if (_current(generation, range)) {
        failed = true;
        _mediaId = null;
      }
    } finally {
      if (_current(generation, range)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// The voice that plays [range]: the Mushaf reciter when it has the timings
  /// of its first and last words, else the teaching al-Husary; null when
  /// neither has them (or they did not load).
  Future<WordRangeVoice?> _voice(QuranWordRange range) async {
    final recitations = await _repository.recitationsForRole(
      AudioRecitationRole.ayahPlayback,
    );
    final current = _ref.read(audioControllerProvider);
    final chosen = preferredRecitation(
      recitations,
      preferredId:
          _ref.read(appPreferencesProvider).mushafRecitationId ??
          (current.channel == AudioPlaybackChannel.mushaf
              ? current.track?.recitationId
              : null),
      role: AudioRecitationRole.ayahPlayback,
    );
    for (final candidate in <Recitation?>[
      chosen,
      for (final voice in wordTimingFallbackRecitations(recitations))
        if (voice.id != chosen?.id) voice,
    ]) {
      if (candidate == null) continue;
      final first = await _ayah(
        candidate.id,
        range.start.surah,
        range.start.ayah,
      );
      final last = await _ayah(candidate.id, range.end.surah, range.end.ayah);
      final from = first?.words[range.start.position]?.start;
      final to = last?.words[range.end.position]?.end;
      if (first == null || last == null || from == null || to == null) {
        continue;
      }
      if (to <= from) continue;
      final teaching = candidate.id != chosen?.id;
      recitation = candidate;
      teachingVoice = teaching;
      return (
        recitation: candidate,
        first: first,
        last: last,
        teaching: teaching,
      );
    }
    recitation = chosen;
    teachingVoice = false;
    return null;
  }

  /// Whether [word] can be played, in the reciter's voice or the teaching
  /// one: the Mushaf menu asks this.
  Future<bool> wordAvailable(QuranWord word) async =>
      await _voice(QuranWordRange.single(word)) != null;

  bool _current(int generation, QuranWordRange range) =>
      !_disposed && generation == _generation && range == _range;

  Future<void> _checkAvailability() async {
    final range = _range;
    if (range == null) return;
    final generation = _generation;
    bool result;
    try {
      result = await _voice(range) != null;
    } on Object {
      result = false;
    }
    if (_disposed || generation != _generation || range != _range) return;
    available = result;
    notifyListeners();
  }

  Future<AyahPlayback?> _ayah(String recitationId, int surah, int ayah) {
    final key = '$recitationId:$surah:$ayah';
    return _requests.putIfAbsent(key, () async {
      try {
        final playback = await _repository.ayahPlayback(
          recitationId: recitationId,
          surah: surah,
          ayah: ayah,
        );
        _timings[key] = playback;
        return playback;
      } on Object {
        unawaited(Future<void>(() => _requests.remove(key)));
        return null;
      }
    });
  }

  void _stopClip() {
    _mediaId = null;
    playing = false;
    playingWord = null;
    unawaited(_audio.stopStandaloneOf(this));
  }

  void _onAudio(IqroAudioState state) {
    final id = _mediaId;
    if (id == null || _disposed) return;
    final standalone = state.standalone;
    if (standalone == null || standalone.mediaItem.id != id) {
      // Loading the clip first stops whatever played before it.
      if (_starting) return;
      _mediaId = null;
      playing = false;
      playingWord = null;
      notifyListeners();
      return;
    }
    final position = _clipStart + standalone.position;
    final word = playingWordAt(position);
    final finished =
        _wasPlaying &&
        !standalone.playing &&
        !standalone.loading &&
        standalone.duration > Duration.zero &&
        standalone.position >=
            standalone.duration - const Duration(milliseconds: 120);
    _wasPlaying = standalone.playing;
    var nextPlaying = standalone.playing || standalone.loading;
    QuranWord? nextWord = nextPlaying ? word : null;
    if (finished && _repeat == WordRepeat.three && round < 3) {
      round++;
      nextPlaying = true;
      unawaited(_audio.toggleStandalone(id, owner: this));
    }
    if (nextPlaying == playing && nextWord == playingWord) return;
    playing = nextPlaying;
    playingWord = nextWord;
    notifyListeners();
  }

  /// The 1-based number of [playingWord] in the range, once its ayahs'
  /// timings are known.
  int? get playingOrdinal {
    final word = playingWord;
    final range = _range;
    final recitationId = recitation?.id;
    if (word == null || range == null || recitationId == null) return null;
    var count = 0;
    for (var ayah = range.start.ayah; ayah <= word.ayah; ayah++) {
      final timings = _timings['$recitationId:${range.start.surah}:$ayah'];
      if (timings == null) return null;
      count += timings.words.keys.where((position) {
        final item = QuranWord(range.start.surah, ayah, position);
        return range.contains(item) && item.compareTo(word) <= 0;
      }).length;
    }
    return count;
  }

  /// The selected word sounding at [position] of the surah track.
  @visibleForTesting
  QuranWord? playingWordAt(Duration position) {
    final range = _range;
    final recitationId = recitation?.id;
    if (range == null || recitationId == null) return null;
    for (var ayah = range.start.ayah; ayah <= range.end.ayah; ayah++) {
      final timings = _timings['$recitationId:${range.start.surah}:$ayah'];
      if (timings == null) continue;
      for (final MapEntry(key: index, value: timing) in timings.words.entries) {
        if (position < timing.start || position >= timing.end) continue;
        final word = QuranWord(range.start.surah, ayah, index);
        return range.contains(word) ? word : null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _removeAudioListener();
    if (_mediaId != null) unawaited(_audio.stopStandaloneOf(this));
    super.dispose();
  }
}

/// The label of [range]: «1:5, word 3 — 1:6, word 3».
String wordRangeLabel(BuildContext context, QuranWordRange range) {
  final start = context.l10n.wordAt(range.start.ayahKey, range.start.position);
  if (range.single) return start;
  return '$start — ${context.l10n.wordAt(range.end.ayahKey, range.end.position)}';
}

/// The bar under a reader with a selection: listen, repeat and clear.
class WordRangePanel extends StatelessWidget {
  const WordRangePanel({required this.controller, super.key});

  final WordRangeController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final range = controller.range;
      if (range == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final locale = Localizations.localeOf(context).languageCode;
      final unavailable = controller.available == false;
      final reciter = controller.recitation?.reciter.nameFor(locale);
      final ordinal = controller.playing ? controller.playingOrdinal : null;
      final subtitle = ordinal != null
          ? context.l10n.wordNumberOf(ordinal, controller.wordCount)
          : [
              context.l10n.noteWordCount(controller.wordCount),
              ?reciter,
            ].join(' · ');
      final title = wordRangeLabel(context, range);
      return ValueListenableBuilder<bool>(
        valueListenable: wordRangePulling,
        builder: (context, pulling, panel) => IgnorePointer(
          ignoring: pulling,
          child: AnimatedOpacity(
            opacity: pulling ? .15 : 1,
            duration: const Duration(milliseconds: 120),
            child: panel,
          ),
        ),
        child: Material(
          key: const ValueKey('word-range-panel'),
          color: scheme.surface,
          elevation: 6,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            controller.repeat == WordRepeat.three &&
                                    controller.playing
                                ? '$subtitle · ${context.l10n.repeatRound(controller.round, 3)}'
                                : subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey('word-range-clear'),
                      tooltip: context.l10n.clearSelection,
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (controller.teachingVoice && !unavailable) ...<Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.record_voice_over_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          wordRangeVoiceNote(context, controller.recitation!),
                          key: const ValueKey('word-range-teaching-voice'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (unavailable) ...<Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: scheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.wordTimingsUnavailable,
                          key: const ValueKey('word-range-unavailable'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (controller.failed) ...<Widget>[
                  Text(
                    context.l10n.wordRangeError,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const ValueKey('word-range-play'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: unavailable || controller.available == null
                      ? null
                      : () => controller.toggle(
                          title: '${context.l10n.ayah} $title',
                        ),
                  icon: controller.loading || controller.available == null
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          controller.playing ? Icons.pause : Icons.play_arrow,
                        ),
                  label: Text(
                    controller.playing
                        ? context.l10n.pause
                        : range.single
                        ? context.l10n.listenWord
                        : context.l10n.listenSelection,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.repeat_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.repeat,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SegmentedButton<WordRepeat>(
                        key: const ValueKey('word-range-repeat'),
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 4),
                          ),
                          textStyle: WidgetStatePropertyAll(
                            theme.textTheme.labelMedium,
                          ),
                        ),
                        segments: <ButtonSegment<WordRepeat>>[
                          ButtonSegment(
                            value: WordRepeat.once,
                            label: Text(context.l10n.repeatOnce),
                          ),
                          ButtonSegment(
                            value: WordRepeat.three,
                            label: Text(context.l10n.repeatThreeTimes),
                          ),
                          ButtonSegment(
                            value: WordRepeat.forever,
                            label: Text(context.l10n.repeatForever),
                          ),
                        ],
                        selected: <WordRepeat>{controller.repeat},
                        onSelectionChanged: (value) =>
                            controller.setRepeat(value.single),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A selection handle: a line along the word and a knob under it. The drag
/// claims the pointer at once, so the page under it does not turn.
class WordRangeHandle extends StatelessWidget {
  const WordRangeHandle({
    required this.start,
    required this.lineHeight,
    required this.onDrag,
    this.onEnd,
    super.key,
  });

  /// The handle before the first word (its right side: the text is RTL).
  final bool start;
  final double lineHeight;

  /// Gets the global point of the text the handle is pulled to.
  final ValueChanged<Offset> onDrag;
  final VoidCallback? onEnd;

  static const width = 44.0;
  static const knob = 18.0;

  /// The handle's height beyond the line it marks.
  static const extra = knob + 14;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.wordRangeHint,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _HandleDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_HandleDragRecognizer>(
              _HandleDragRecognizer.new,
              (recognizer) {
                recognizer.onStart = (pointer) {
                  final box = context.findRenderObject() as RenderBox?;
                  final anchor = box?.localToGlobal(
                    Offset(width / 2, lineHeight / 2),
                  );
                  return _HandleDrag(
                    pointer: pointer,
                    grab: anchor == null ? Offset.zero : pointer - anchor,
                    onDrag: onDrag,
                    onEnd: onEnd,
                  );
                };
              },
            ),
      },
      child: CustomPaint(
        size: Size(width, lineHeight + extra),
        painter: _HandlePainter(start: start, lineHeight: lineHeight),
      ),
    ),
  );
}

/// Takes the finger the moment it touches a handle. A drag recognizer that
/// waits for its slop loses a moving finger to the page swipe or the list
/// scroll: they use the device's touch slop, which on Android phones is
/// smaller than the 18 px default of a recognizer without gesture settings.
class _HandleDragRecognizer extends MultiDragGestureRecognizer {
  _HandleDragRecognizer() : super(debugOwner: null);

  _HandlePointerState? _added;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _added = _HandlePointerState(event.position, event.kind, gestureSettings);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // The arena entry exists only now: claim it before anything can move.
    _added?.claim();
    _added = null;
  }

  @override
  String get debugDescription => 'word range handle';
}

class _HandlePointerState extends MultiDragPointerState {
  _HandlePointerState(super.initialPosition, super.kind, super.gestureSettings);

  void claim() => resolve(GestureDisposition.accepted);

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

class _HandleDrag extends Drag {
  _HandleDrag({
    required Offset pointer,
    required this.grab,
    required this.onDrag,
    this.onEnd,
  }) : _pointer = pointer {
    wordRangePulling.value = true;
  }

  final Offset grab;
  final ValueChanged<Offset> onDrag;
  final VoidCallback? onEnd;

  /// The finger, followed by its deltas: the first update after the slop
  /// still reports where the finger went down.
  Offset _pointer;

  @override
  void update(DragUpdateDetails details) {
    _pointer += details.delta;
    onDrag(_pointer - grab);
  }

  @override
  void end(DragEndDetails details) => _done();

  @override
  void cancel() => _done();

  void _done() {
    wordRangePulling.value = false;
    onEnd?.call();
  }
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter({required this.start, required this.lineHeight});

  final bool start;
  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = wordRangeHandleColor;
    final x = size.width / 2;
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, lineHeight + 4), paint);
    const r = WordRangeHandle.knob / 2;
    final center = Offset(start ? x + r - 1 : x - r + 1, lineHeight + 4 + r);
    canvas.drawCircle(center, r, paint);
    // The corner that points at the text, as on a text selection handle.
    canvas.drawRect(
      Rect.fromLTWH(start ? x - 1 : x - r + 1, lineHeight + 4, r, r),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.lineHeight != lineHeight;
}
