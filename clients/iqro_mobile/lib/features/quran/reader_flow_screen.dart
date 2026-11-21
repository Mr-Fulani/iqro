import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/text/arabic_digits.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../core/theme/iqro_theme.dart';
import '../dua/dua_arabic.dart';
import 'ayah_action_sheet.dart';
import 'mushaf_paper.dart';
import 'mushaf_script.dart';
import 'next_surah.dart';
import 'quran_models.dart';
import 'reader_anchored_list.dart';
import 'reader_page_turn.dart';
import 'reader_words.dart';
import 'recitation_follow.dart';
import 'recitation_match.dart';
import 'recitation_model/follow_core.dart' show FollowWhy;
import 'recitation_model/model_listener.dart';
import 'rub_mark.dart';
import 'word_range.dart';

/// Where the plain text was left: the surah, which the end of one may have
/// moved on, and the ayah at the top of the screen.
typedef ReaderFlowResult = ({int surah, int ayah});

/// The surah as plain Arabic text, running on as on a Mushaf page, in a
/// size the reader picks: for those who find the Mushaf too small and the
/// cards, translation and buttons in the way. A swipe to the right on the
/// reader opens it at the ayah under the finger; a swipe back to the left,
/// or the back button, returns that ayah at the top of the screen. At the
/// end of a surah the next one rises in from below.
class ReaderFlowScreen extends StatefulWidget {
  const ReaderFlowScreen({
    required this.surah,
    required this.initialAyah,
    super.key,
  });

  final int surah;
  final int initialAyah;

  /// Turns in from the left, the way the finger went; pops with the surah
  /// and the ayah at the top of the screen.
  static Route<ReaderFlowResult> route({
    required int surah,
    required int ayah,
  }) => PageRouteBuilder<ReaderFlowResult>(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) =>
        ReaderFlowScreen(surah: surah, initialAyah: ayah),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        ReaderPageTurn(
          animation: animation,
          hinge: ReaderPageHinge.left,
          child: child,
        ),
  );

  @override
  State<ReaderFlowScreen> createState() => _ReaderFlowScreenState();
}

class _ReaderFlowScreenState extends State<ReaderFlowScreen> {
  late var _surah = widget.surah;
  late var _initialAyah = widget.initialAyah;

  void _next() {
    if (_surah >= lastSurah) return;
    setState(() {
      _surah += 1;
      _initialAyah = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // The surah that ends goes up and fades, the next rises from below.
      transitionBuilder: (child, animation) {
        if (still) return FadeTransition(opacity: animation, child: child);
        final incoming = child.key == ValueKey<int>(_surah);
        return SlideTransition(
          position: Tween<Offset>(
            begin: incoming ? const Offset(0, 1) : const Offset(0, -.3),
            end: Offset.zero,
          ).animate(animation),
          child: incoming
              ? child
              : FadeTransition(opacity: animation, child: child),
        );
      },
      layoutBuilder: (current, previous) =>
          Stack(children: <Widget>[...previous, ?current]),
      child: _FlowPage(
        key: ValueKey<int>(_surah),
        surah: _surah,
        initialAyah: _initialAyah,
        onNext: _next,
        onLeave: (ayah) =>
            Navigator.of(context).pop((surah: _surah, ayah: ayah)),
      ),
    );
  }
}

class _FlowPage extends ConsumerStatefulWidget {
  const _FlowPage({
    required this.surah,
    required this.initialAyah,
    required this.onNext,
    required this.onLeave,
    super.key,
  });

  final int surah;
  final int initialAyah;
  final VoidCallback onNext;
  final ValueChanged<int> onLeave;

  @override
  ConsumerState<_FlowPage> createState() => _FlowPageState();
}

/// The microphone of the recitation check while it listens.
const _micOnColor = Color(0xFFB3261E);

/// The ayah numbers on the paper: the app's gold, apart from the ink.
const _markerColor = Color(0xFF9A6D22);

class _FlowPageState extends ConsumerState<_FlowPage> {
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final _stackKey = GlobalKey();
  final _wordRegistry = ReaderWordRegistry();
  final _selectionBounds = ValueNotifier<Rect?>(null);
  late final WordRangeController _words;
  late final _nextPull = NextSurahPull(onNext: _openNext);
  Offset? _loupe;
  late var _ayah = widget.initialAyah;
  QuranWordRange? _marked;
  Timer? _markTimer;
  final _rubMark = RubMarkController();
  var _dragged = false;

  /// The ayahs drawn in the plain font, not yet in the Mushaf's script.
  final _plainAyahs = <int>{};

  /// The size while the slider moves, ahead of the saved one.
  double? _fontSize;
  double? _width;
  var _placed = false;
  var _jumping = false;

  /// The text is on screen: the Mushaf's script of its first screen is in,
  /// or was not to be had within [mushafScriptWait].
  var _opened = false;
  Timer? _scriptTimer;

  /// The recitation check: the listener while the microphone is on, the
  /// surah's words in order, the word reached and its box in the stack.
  RecitationListener? _listener;
  RecitationMatcher? _matcher;
  var _followWords = const <QuranWord>[];
  QuranWord? _followWord;

  /// The place waits, in red, on a word the reader left out or said as another.
  var _followWrong = false;

  Timer? _missTimer;
  Offset? _tapped;

  /// The hint by the microphone is up: it comes a moment after the text
  /// opens and now and then after, to a reader who has not yet turned the
  /// microphone on.
  var _followHint = false;
  Timer? _followHintTimer;

  void _showFollowHint() {
    if (!mounted || _listener != null) return;
    setState(() => _followHint = true);
    _followHintTimer = Timer(recitationHintTime, () {
      if (!mounted) return;
      setState(() => _followHint = false);
      _followHintTimer = Timer(recitationHintPause, _showFollowHint);
    });
  }

  @override
  void initState() {
    super.initState();
    _words = WordRangeController(ref)..addListener(_onWords);
    wordRangePulling.addListener(_onWords);
    _rubMark.addListener(_onRubMark);
    if (!ref.read(appPreferencesProvider).recitationNoticeSeen) {
      _followHintTimer = Timer(recitationHintDelay, _showFollowHint);
    }
  }

  void _onRubMark() => setState(() {});

  /// Announces the quarter of a hizb whose first ayah the reader has
  /// scrolled to.
  Future<void> _markVisibleRub() async {
    final List<QuranDivision> rubs;
    try {
      rubs = await ref.read(quranRubElHizbProvider.future);
    } on Object {
      return;
    }
    if (!mounted) return;
    _rubMark.reached(
      rubVisibleIn(
        surah: widget.surah,
        rubs: rubs,
        viewportKey: _viewportKey,
        ayahRect: _ayahRect,
      ),
    );
  }

  @override
  void dispose() {
    _markTimer?.cancel();
    _scriptTimer?.cancel();
    _followHintTimer?.cancel();
    _missTimer?.cancel();
    if (_listener case final listener?) {
      listener.dispose();
      unawaited(WakelockPlus.disable());
    }
    _rubMark
      ..removeListener(_onRubMark)
      ..dispose();
    wordRangePulling.removeListener(_onWords);
    _selectionBounds.dispose();
    _words
      ..removeListener(_onWords)
      ..dispose();
    _nextPull.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onWords() {
    if (!mounted) return;
    setState(() {
      if (!wordRangePulling.value) _loupe = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBounds());
  }

  void _reportBounds() {
    final range = _words.range;
    Rect? bounds;
    if (mounted && range != null) {
      for (final word in <QuranWord>[range.start, range.end]) {
        final rect = _wordRegistry.wordRect(word);
        if (rect == null) continue;
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
    }
    if (_selectionBounds.value != bounds) _selectionBounds.value = bounds;
  }

  void _selectWords(List<QuranAyah> items, QuranWordRange range) {
    var count = 0;
    for (final ayah in items) {
      if (ayah.number < range.start.ayah || ayah.number > range.end.ayah) {
        continue;
      }
      final words = ayahWords(ayah).length;
      final from = ayah.number == range.start.ayah ? range.start.position : 1;
      final to = ayah.number == range.end.ayah ? range.end.position : words;
      count += math.max(0, to - from + 1);
    }
    _words.select(range, wordCount: count);
  }

  /// Scrolls while the finger pulls a selection near the top or bottom, and
  /// moves the loupe with it.
  void _followWordDrag(Offset global) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack != null && stack.attached && wordRangePulling.value) {
      setState(() => _loupe = stack.globalToLocal(global));
    }
    final box = _viewportBox;
    if (box == null || !_scrollController.hasClients) return;
    final local = box.globalToLocal(global);
    const edge = 56.0;
    final step = local.dy < edge
        ? -(edge - local.dy) / 2
        : local.dy > box.size.height - edge
        ? (local.dy - box.size.height + edge) / 2
        : 0.0;
    if (step == 0) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  RenderBox? get _viewportBox {
    final box = _viewportKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Where [ayah] is on screen, from its first word to the end of its
  /// last: ayahs share their lines, and none has a box of its own.
  Rect? _ayahRect(int ayah) {
    final first = _wordRegistry.wordRect(QuranWord(widget.surah, ayah, 1));
    if (first == null) return null;
    final next = _wordRegistry.wordRect(QuranWord(widget.surah, ayah + 1, 1));
    final bottom = next == null || next.top <= first.top
        ? first.bottom
        : next.top;
    final box = _viewportBox;
    final left = box?.localToGlobal(Offset.zero).dx ?? first.left;
    return Rect.fromLTRB(
      left,
      first.top,
      left + (box?.size.width ?? first.width),
      bottom,
    );
  }

  /// Brings [ayah]'s first word to the top of the screen.
  void _alignTo(int ayah) {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (ayah <= 1) {
      _jump(position.minScrollExtent);
      return;
    }
    final box = _viewportBox;
    if (box == null) return;
    // Measured in the list, not on screen: the page may still be turning in.
    final rect = _wordRegistry.wordRectIn(
      QuranWord(widget.surah, ayah, 1),
      box,
    );
    if (rect == null) return;
    _jump(position.pixels + rect.top - 8);
  }

  void _jump(double pixels) {
    final position = _scrollController.position;
    _jumping = true;
    try {
      _scrollController.jumpTo(
        pixels.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    } finally {
      _jumping = false;
    }
  }

  var _keepScheduled = false;

  /// Keeps the ayah at the top in place while the text reflows: once a
  /// frame, as a second jump would measure the text before the first moved it.
  void _keepPlace() {
    if (!_placed || _keepScheduled) return;
    _keepScheduled = true;
    final ayah = _ayah;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keepScheduled = false;
      _alignTo(ayah);
      _reportBounds();
      if (_followWord == null) return;
      // The place stays in view, once the text has moved.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _showPlace())
        ..scheduleFrame();
    });
  }

  /// The fingers on the text. Two of them pulled apart or together change
  /// the size of the text, as a pinch does a picture.
  final _fingers = <int, Offset>{};
  ({double distance, double size})? _pinch;
  ScrollHoldController? _pinchHold;

  double get _fingerDistance {
    final points = _fingers.values.toList();
    return (points[0] - points[1]).distance;
  }

  /// A tap, to tell two of them in a row: where and when the one finger
  /// went down, and the tap before it. Told from the touches themselves: a
  /// double-tap recogniser over the text would hold back every tap in it.
  ({Offset at, Duration time})? _tapDown;
  ({Offset at, Duration time})? _lastTap;

  void _fingerDown(PointerDownEvent event, double size) {
    _fingers[event.pointer] = event.position;
    _tapDown = _fingers.length == 1
        ? (at: event.position, time: event.timeStamp)
        : null;
    if (_fingers.length != 2 ||
        _words.range != null ||
        wordRangePulling.value ||
        _fingerDistance < 1) {
      return;
    }
    // The text does not scroll under two fingers.
    _pinchHold = _scrollController.hasClients
        ? _scrollController.position.hold(() {})
        : null;
    setState(() => _pinch = (distance: _fingerDistance, size: size));
  }

  void _fingerMove(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.position;
    final pinch = _pinch;
    if (pinch == null || _fingers.length != 2) return;
    final size = (pinch.size * _fingerDistance / pinch.distance).clamp(
      minReaderFlowFontSize,
      maxReaderFlowFontSize,
    );
    if (size == _fontSize) return;
    setState(() => _fontSize = size);
    _keepPlace();
  }

  void _fingerUp(PointerEvent event) {
    _fingers.remove(event.pointer);
    final down = _tapDown;
    _tapDown = null;
    if (down != null &&
        event is PointerUpEvent &&
        _pinch == null &&
        (event.position - down.at).distance < kTouchSlop &&
        event.timeStamp - down.time < kLongPressTimeout) {
      final before = _lastTap;
      if (before != null &&
          down.time - before.time < kDoubleTapTimeout &&
          (down.at - before.at).distance < kDoubleTapSlop &&
          _words.range == null) {
        _lastTap = null;
        _resetSize();
      } else {
        _lastTap = (at: event.position, time: event.timeStamp);
      }
    }
    if (_pinch == null) return;
    _pinchHold?.cancel();
    _pinchHold = null;
    setState(() => _pinch = null);
    final size = _fontSize;
    if (size != null) _saveSize(size);
  }

  void _saveSize(double size) => unawaited(
    ref.read(appPreferencesProvider.notifier).setReaderFlowFontSize(size),
  );

  /// A double tap: the size the text has from the start.
  void _resetSize() {
    setState(() => _fontSize = defaultReaderFlowFontSize);
    _keepPlace();
    _saveSize(defaultReaderFlowFontSize);
  }

  var _placeUpdateScheduled = false;

  /// Looks after the frame: the text has moved by then.
  void _schedulePlaceUpdate() {
    if (_placeUpdateScheduled) return;
    _placeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeUpdateScheduled = false;
      if (mounted) _updatePlace();
    });
  }

  /// The ayah at the top of the screen, for the line at the bottom and for
  /// the way back, as the reader scrolls: the one the first line starts
  /// with, or the next one if it begins on that line too.
  void _updatePlace() {
    final box = _viewportBox;
    if (box == null) return;
    // The right end of the first line: where an Arabic line starts.
    final word = _wordRegistry.wordAt(
      box.localToGlobal(Offset(box.size.width - 1, 12)),
    );
    if (word == null) return;
    var ayah = word.ayah;
    final line = _wordRegistry.wordRect(word);
    final next = _wordRegistry.wordRect(QuranWord(widget.surah, ayah + 1, 1));
    if (word.position > 1 &&
        line != null &&
        next != null &&
        next.top < line.bottom - 1) {
      ayah += 1;
    }
    if (ayah != _ayah) setState(() => _ayah = ayah);
  }

  void _schedulePlace(List<QuranAyah> items) {
    if (_placed || items.isEmpty) return;
    _placed = true;
    // The list opens at the ayah: only its first word is put in place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _alignTo(widget.initialAyah);
      final ayah = items
          .where((item) => item.number == widget.initialAyah)
          .firstOrNull;
      final count = ayah == null ? 0 : ayahWords(ayah).length;
      setState(() {
        _ayah = widget.initialAyah;
        _marked = count == 0
            ? null
            : QuranWordRange.between(
                QuranWord(widget.surah, widget.initialAyah, 1),
                QuranWord(widget.surah, widget.initialAyah, count),
              );
      });
      _markTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _marked = null);
      });
    });
  }

  bool _scriptSettled(List<QuranAyah> items) {
    if (_opened) return true;
    _scriptTimer ??= Timer(mushafScriptWait, () {
      if (mounted) setState(() => _opened = true);
    });
    return _opened = watchMushafScriptSettled(ref, items, widget.initialAyah);
  }

  void _leave() => widget.onLeave(_ayah);

  /// Turns the microphone on, to follow the reader from the ayah at the top
  /// of the screen, or off.
  /// A press on the microphone is being carried out, or was a moment ago:
  /// another one then, a finger's bounce, would undo it at once.
  var _followBusy = false;

  Future<void> _toggleFollow(List<QuranAyah> items) async {
    if (_followBusy) return;
    _followBusy = true;
    try {
      await _switchFollow(items);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _followBusy = false;
    }
  }

  Future<void> _switchFollow(List<QuranAyah> items) async {
    // The microphone is found: no more hints.
    _followHintTimer?.cancel();
    _followHint = false;
    final listening = _listener;
    if (listening != null) {
      _missTimer?.cancel();
      setState(() {
        _listener = null;
        _followWord = null;
        _followWrong = false;
      });
      unawaited(WakelockPlus.disable());
      await listening.stop();
      listening.dispose();
      return;
    }
    // Before the first time: what happens to the voice, and what is and
    // is not checked.
    if (!ref.read(appPreferencesProvider).recitationNoticeSeen) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => _RecitationNotice(onDevice: recitationByModel),
      );
      if (agreed != true || !mounted) return;
      unawaited(
        ref.read(appPreferencesProvider.notifier).markRecitationNoticeSeen(),
      );
    }
    final words = <QuranWord>[];
    final texts = <String>[];
    for (final ayah in items) {
      for (final (index, text) in ayahWords(ayah).indexed) {
        words.add(QuranWord(widget.surah, ayah.number, index + 1));
        texts.add(text);
      }
    }
    final start = words.indexWhere((word) => word.ayah >= _ayah);
    _followWords = words;
    _matcher = RecitationMatcher(texts)..moveTo(start < 0 ? 0 : start);
    // On Android a model on the phone listens: the sound stays there and
    // no network is needed. Elsewhere, and where the model cannot (it did
    // not load, or its table has not this surah's words as the screen
    // has), the phone's speech recognition does.
    var listener = recitationByModel
        ? ModelRecitationListener(
            surah: widget.surah,
            ayahs: <(int, int)>[
              for (final ayah in items) (ayah.number, ayahWords(ayah).length),
            ],
            words: texts,
            from: start < 0 ? 0 : start,
            onPlace: _onModelPlace,
          )
        : RecitationListener(onHeard: _onHeard);
    setState(() {
      _listener = listener;
      // Reading begins here; nothing is read yet.
      _followWord = words.isEmpty ? null : words[start < 0 ? 0 : start];
      _followWrong = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPlace());
    unawaited(WakelockPlus.enable());
    var on = await listener.start();
    if (!on &&
        listener is ModelRecitationListener &&
        mounted &&
        identical(_listener, listener)) {
      // The model cannot listen here: the phone's speech recognition does.
      listener.dispose();
      final spare = RecitationListener(onHeard: _onHeard);
      listener = spare;
      setState(() => _listener = spare);
      on = await spare.start();
    }
    if (on || !mounted || !identical(_listener, listener)) return;
    setState(() {
      _listener = null;
      _followWord = null;
    });
    unawaited(WakelockPlus.disable());
    listener.dispose();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.recitationUnavailable)));
  }

  void _onHeard(String transcript) {
    final matcher = _matcher;
    if (matcher == null || !mounted || _listener == null) return;
    final heard = matcher.hear(transcript);
    _missTimer?.cancel();
    if (heard.reached case final index?) {
      // At once: the word's place is known before the next frame.
      _read(index);
    } else if (heard.misses >= recitationMissesAtOnce) {
      _markWrong();
    } else if (heard.misses > 0) {
      // One word that is not the one expected may be the recogniser's
      // slip, which its next words put right: a mistake only if they do
      // not come.
      _missTimer = Timer(recitationMissPause, _markWrong);
    }
  }

  /// The model's follower says where the place is, and whether the word
  /// there was left out or said as another.
  void _onModelPlace(int index, bool wrong) {
    if (!mounted || _listener == null || index >= _followWords.length) return;
    if (!wrong) {
      _read(index);
      return;
    }
    _wait(index);
    if (ref.read(appPreferencesProvider).readerHaptics) {
      unawaited(HapticFeedback.vibrate());
    }
  }

  /// The reader left the expected word out or said another: the place waits
  /// on that word, in red, and the phone gives a short buzz.
  void _markWrong() {
    final index = _matcher?.expected;
    if (!mounted || _listener == null || index == null || _followWrong) return;
    _wait(index);
    if (ref.read(appPreferencesProvider).readerHaptics) {
      unawaited(HapticFeedback.vibrate());
    }
  }

  /// A tap on a word while the microphone is on: reading starts from it.
  void _followFrom(Offset global) {
    final word = _wordRegistry.wordAt(global);
    final index = word == null ? -1 : _followWords.indexOf(word);
    if (index < 0) return;
    _missTimer?.cancel();
    _matcher?.moveTo(index);
    if (_listener case final ModelRecitationListener model) model.moveTo(index);
    _followWord = word;
    _followWrong = false;
    _showPlace();
  }

  /// The reader is on the word at [index]: the plate goes under it.
  void _read(int index) {
    _followWord = _followWords[index];
    _followWrong = false;
    _showPlace();
  }

  /// The word at [index] was left out or read wrongly: the plate under it
  /// is red, and it is waited on.
  void _wait(int index) {
    _followWord = _followWords[index];
    _followWrong = true;
    _showPlace();
  }

  /// The plate under the word the reader is on, or is to read again. The
  /// rest of the text stays as it is.
  List<ReaderWordPlate> _followPlates() {
    final word = _followWord;
    if (_listener == null || word == null) return const <ReaderWordPlate>[];
    return <ReaderWordPlate>[
      _followWrong
          ? (word: word, fill: recitationWrongPlate, edge: recitationWrong)
          : (word: word, fill: recitationPlate, edge: recitationPlateEdge),
    ];
  }

  /// Puts the plate under its word and keeps that word's line about the
  /// middle of the screen, the lines read above it and those to come below.
  void _showPlace() {
    final word = _followWord;
    final stack = _stackKey.currentContext?.findRenderObject();
    if (!mounted) return;
    setState(() {});
    if (word == null || stack is! RenderBox) return;
    final rect = _wordRegistry.wordRectIn(word, stack);
    // Its ayah is not on screen.
    if (rect == null) return;
    final height = stack.size.height;
    // Left where it is while its line is near the middle; a line further
    // up or down is brought there.
    final at = rect.center.dy;
    if (!_scrollController.hasClients ||
        (at > height * .32 && at < height * .58)) {
      return;
    }
    final position = _scrollController.position;
    unawaited(
      _scrollController.animateTo(
        (position.pixels + at - height * .45).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _openNext() {
    if (_words.range == null && widget.surah < lastSurah) widget.onNext();
  }

  Future<void> _showMore(List<QuranAyah> items) async {
    final start = _words.range?.start;
    final ayah = items.where((item) => item.number == start?.ayah).firstOrNull;
    if (ayah == null) return;
    await showIqroSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) => AyahActionSheet(
        reference: QuranAyahReference(
          id: ayah.id,
          surah: ayah.surahNumber,
          ayah: ayah.number,
        ),
        page: ayah.pages.firstOrNull ?? 1,
      ),
    );
  }

  Future<void> _showTextSize(double size) async {
    final panel = _FlowFontSize(
      initial: size,
      onChanged: (value) {
        setState(() => _fontSize = value);
        _keepPlace();
      },
      onChangeEnd: _saveSize,
    );
    // A sheet on a phone; on a tablet a panel by the button.
    if (MediaQuery.sizeOf(context).shortestSide < 600) {
      await showIqroSheet<void>(
        context: context,
        barrierColor: Colors.black12,
        builder: (context) => SafeArea(child: panel),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Align(
          alignment: AlignmentDirectional.topEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: 56, end: 16),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(width: 340, child: panel),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ayahs = ref.watch(ayahsProvider(widget.surah));
    final saved = ref.watch(
      appPreferencesProvider.select((value) => value.readerFlowFontSize),
    );
    final size = _fontSize ?? saved;
    final items = ayahs.valueOrNull ?? const <QuranAyah>[];
    final versePages = ref.watch(mushafVersePagesProvider).valueOrNull;
    final current = items.where((item) => item.number == _ayah).firstOrNull;
    final page = current == null
        ? null
        : mushafPageOfAyah(versePages, widget.surah, _ayah, current.pages);
    final language = Localizations.localeOf(context).languageCode;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      // Ink on paper, as in the Mushaf, in a dark app theme too.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          key: const ValueKey('reader-flow'),
          backgroundColor: mushafPaperColor,
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6, top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (items.isNotEmpty)
                        Flexible(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              key: const ValueKey('reader-flow-follow-hint'),
                              opacity: _followHint ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: RecitationHint(
                                text: context.l10n.recitationHint,
                              ),
                            ),
                          ),
                        ),
                      if (items.isNotEmpty)
                        RecitationMicPulse(
                          key: const ValueKey('reader-flow-follow-pulse'),
                          active: _followHint || _listener != null,
                          color: _listener != null
                              ? _micOnColor
                              : recitationGold,
                          child: IconButton(
                            key: const ValueKey('reader-flow-follow'),
                            tooltip: _listener == null
                                ? context.l10n.recitationCheck
                                : context.l10n.recitationStop,
                            onPressed: () => unawaited(_toggleFollow(items)),
                            color: _listener != null
                                ? _micOnColor
                                : _followHint
                                ? recitationGold
                                : mushafInkColor,
                            icon: Icon(
                              _listener == null
                                  ? Icons.mic_none_rounded
                                  : Icons.mic_rounded,
                            ),
                          ),
                        ),
                      IconButton(
                        key: const ValueKey('reader-flow-text-size'),
                        tooltip: context.l10n.arabicTextSize,
                        onPressed: () => _showTextSize(size),
                        color: mushafInkColor,
                        icon: const Icon(Icons.tune),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ayahs.when(
                    loading: () => const IqroLoading(),
                    error: (error, stack) => IqroAsyncError(
                      title: context.l10n.noQuranData,
                      onRetry: () =>
                          ref.invalidate(ayahsProvider(widget.surah)),
                    ),
                    data: (items) => _scriptSettled(items)
                        ? _text(items, size, versePages)
                        : const SizedBox.expand(),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: Center(
                    child: _listener != null
                        ? _FollowEar(
                            ear: _listener!.ear,
                            hint: switch (_listener) {
                              final ModelRecitationListener model => model.hint,
                              _ => null,
                            },
                            onDevice: _listener is ModelRecitationListener,
                          )
                        : page == null
                        ? null
                        : Text(
                            context.l10n.readerPlainTextPlace(
                              readerDigits(language, _ayah),
                              readerDigits(language, page),
                            ),
                            key: const ValueKey('reader-flow-place'),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: mushafAccentColor),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<QuranAyah>? _groupedItems;
  Map<String, List<int>>? _groupedPages;
  var _groups = const <List<QuranAyah>>[];

  /// The ayahs as the paragraphs they are written in: those of one page
  /// of the Mushaf run on in the same lines, an ayah beginning where the
  /// one before it ends, as on the page. A paragraph of very many words
  /// is laid out too slowly, so a long page is two or three.
  List<List<QuranAyah>> _paragraphs(
    List<QuranAyah> items,
    Map<String, List<int>>? versePages,
  ) {
    if (identical(items, _groupedItems) &&
        identical(versePages, _groupedPages)) {
      return _groups;
    }
    final groups = <List<QuranAyah>>[];
    int? page;
    var words = 0;
    for (final ayah in items) {
      final on = mushafPageOfAyah(
        versePages,
        widget.surah,
        ayah.number,
        ayah.pages,
      );
      final count = ayahWords(ayah).length;
      if (groups.isEmpty ||
          (on != null && page != null && on != page) ||
          words + count > _paragraphWords) {
        groups.add(<QuranAyah>[]);
        words = 0;
      }
      groups.last.add(ayah);
      words += count;
      page = on ?? page;
    }
    // The paragraphs changed under the reader: the ayah read stays put.
    if (_groupedItems != null) _keepPlace();
    _groupedItems = items;
    _groupedPages = versePages;
    return _groups = groups;
  }

  static const _paragraphWords = 120;

  Widget _text(
    List<QuranAyah> items,
    double size,
    Map<String, List<int>>? versePages,
  ) {
    _schedulePlace(items);
    final groups = _paragraphs(items, versePages);
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineMedium?.copyWith(
      color: mushafInkColor,
      fontFamily: IqroTheme.arabicFontFamily,
      fontWeight: FontWeight.normal,
      fontSize: size,
      // Room for the marks over and under a line, and no more: a large
      // text is not to leave the screen half empty.
      height: 1.8,
    );
    int? pageOf(QuranAyah ayah) =>
        mushafPageOfAyah(versePages, widget.surah, ayah.number, ayah.pages);
    final language = Localizations.localeOf(context).languageCode;
    final first = items.firstOrNull;
    // Every surah but al-Fatiha and at-Tawba opens with the basmala, which
    // is not counted as its first ayah: it stands on its own line.
    final opening =
        first == null || first.surahNumber == 1 || first.surahNumber == 9
        ? null
        : splitDuaArabic(
            first.textUthmani,
          ).where((part) => part.opening).firstOrNull?.text;
    final surahs =
        ref.watch(quranCatalogProvider).valueOrNull?.surahs ?? const <Surah>[];
    final surah = surahs
        .where((item) => item.number == widget.surah)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_width != null && _width != constraints.maxWidth) _keepPlace();
        _width = constraints.maxWidth;
        // Lines no longer than a page of a book, on a tablet too. The
        // margin grows with the text: the tail of a letter that ends a line
        // is drawn past the word's own box.
        final side = math.max(
          20 + math.max(0, size - defaultReaderFlowFontSize) * .6,
          (constraints.maxWidth - 820) / 2,
        );
        return Listener(
          onPointerDown: (event) => _fingerDown(event, size),
          onPointerMove: _fingerMove,
          onPointerUp: _fingerUp,
          onPointerCancel: _fingerUp,
          child: ReaderSwipeArea(
            background: mushafPaperColor,
            enabled:
                _words.range == null &&
                !wordRangePulling.value &&
                _pinch == null,
            left: ReaderSwipeTarget(
              icon: Icons.subject_rounded,
              label: context.l10n.textMode,
            ),
            onSwipe: (direction, start) {
              if (direction == ReaderSwipeDirection.left) _leave();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // While the microphone listens a tap on a word starts the
              // reading from it.
              onTapUp: (details) => _tapped = details.globalPosition,
              onTap: _words.range != null
                  ? _words.clear
                  : _listener != null
                  ? () {
                      final at = _tapped;
                      if (at != null) _followFrom(at);
                    }
                  : null,
              child: Stack(
                key: _stackKey,
                children: <Widget>[
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth != 0) return false;
                        if (notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          _dragged = true;
                        }
                        if (notification is ScrollEndNotification && _dragged) {
                          unawaited(_markVisibleRub());
                        }
                        if (notification is ScrollUpdateNotification) {
                          if (_words.range != null) _reportBounds();
                          // A jump to keep the place reports nothing new.
                          if (!_jumping && _pinch == null) {
                            _schedulePlaceUpdate();
                          }
                        }
                        _nextPull.handle(
                          notification,
                          enabled:
                              _words.range == null && widget.surah < lastSurah,
                        );
                        return false;
                      },
                      child: ReaderAnchoredList(
                        key: _viewportKey,
                        controller: _scrollController,
                        // The surah's title comes with its first ayah.
                        initialIndex: widget.initialAyah <= 1
                            ? 0
                            : groups.indexWhere(
                                    (group) => group.any(
                                      (item) =>
                                          item.number == widget.initialAyah,
                                    ),
                                  ) +
                                  1,
                        padding: EdgeInsets.fromLTRB(
                          side,
                          0,
                          side,
                          _words.range == null ? 32 : 280,
                        ),
                        itemCount: groups.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _FlowHeader(
                              name: surah?.nameAr,
                              opening: opening,
                              size: size,
                              style: style,
                            );
                          }
                          if (index == groups.length + 1) {
                            return widget.surah >= lastSurah
                                ? QuranEndCard(surah: surah, paper: true)
                                : NextSurahCard(
                                    number: widget.surah + 1,
                                    surah: surahs
                                        .where(
                                          (item) =>
                                              item.number == widget.surah + 1,
                                        )
                                        .firstOrNull,
                                    progress: _nextPull.progress,
                                    onTap: _words.range == null
                                        ? _openNext
                                        : null,
                                    paper: true,
                                  );
                          }
                          final group = groups[index - 1];
                          final plates = _followPlates();
                          final page = pageOf(group.first);
                          final pageEnded =
                              index > 1 &&
                              page != null &&
                              page != pageOf(groups[index - 2].last);
                          final marked = _rubMark.mark?.startAyah.ayah;
                          final text = Consumer(
                            builder: (context, ref, _) {
                              final texts = <ReaderAyahText>[];
                              QuranWordRange? rub;
                              for (final ayah in group) {
                                final words = ayahWords(ayah);
                                final script = watchMushafAyahScript(
                                  ref,
                                  surah: widget.surah,
                                  ayah: ayah.number,
                                  wordCount: words.length,
                                );
                                // The Mushaf's script reflows the text when
                                // it arrives: the ayah at the top stays
                                // there. Once the reader scrolls, pages
                                // load ahead of the screen and move nothing
                                // on it.
                                if (script == null) {
                                  _plainAyahs.add(ayah.number);
                                } else if (_plainAyahs.remove(ayah.number) &&
                                    !_dragged) {
                                  _keepPlace();
                                }
                                // The ayah a quarter of a hizb starts at,
                                // while it is announced.
                                if (marked == ayah.number && words.isNotEmpty) {
                                  rub = QuranWordRange.between(
                                    QuranWord(widget.surah, ayah.number, 1),
                                    QuranWord(
                                      widget.surah,
                                      ayah.number,
                                      words.length,
                                    ),
                                  );
                                }
                                texts.add(
                                  ReaderAyahText(
                                    ayah: ayah.number,
                                    words: words,
                                    marker:
                                        '\u00A0﴿${arabicIndicDigits(ayah.number)}﴾',
                                    spans: script?.words,
                                    markerSpan: script == null
                                        ? null
                                        : TextSpan(
                                            children: <InlineSpan>[
                                              const TextSpan(text: '\u00A0'),
                                              ?script.marker,
                                            ],
                                          ),
                                  ),
                                );
                              }
                              return ReaderAyahWords.flow(
                                key: ValueKey(
                                  'reader-flow-ayah-${group.first.number}',
                                ),
                                surah: widget.surah,
                                ayahs: texts,
                                // Lines from edge to edge of the screen at
                                // any size, the room their words leave
                                // shared out between them; the last line
                                // of a page in the middle.
                                textAlign: TextAlign.center,
                                fill: true,
                                markerStyle: const TextStyle(
                                  color: _markerColor,
                                ),
                                style: style,
                                registry: _wordRegistry,
                                range: _words.range,
                                plates: plates,
                                marked: _marked ?? rub,
                                playingWord: _words.playingWord,
                                onRange: (range) => _selectWords(items, range),
                                onDrag: _followWordDrag,
                              );
                            },
                          );
                          if (!pageEnded) return text;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ReaderPageBreak(
                                key: ValueKey(
                                  'reader-flow-page-end-${page - 1}',
                                ),
                                paper: true,
                                label:
                                    '${context.l10n.page} ${readerDigits(language, page - 1)}',
                              ),
                              SizedBox(height: size * .5),
                              text,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (_words.range != null)
                    Positioned.fill(
                      child: WordRangePanelLayer(
                        controller: _words,
                        selection: _selectionBounds,
                        onMore: () => unawaited(_showMore(items)),
                      ),
                    ),
                  if (_loupe case final point?) WordRangeLoupe(point: point),
                  RubMarkToast(controller: _rubMark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlowHeader extends StatelessWidget {
  const _FlowHeader({
    required this.name,
    required this.opening,
    required this.size,
    required this.style,
  });

  final String? name;
  final String? opening;
  final double size;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    const color = _markerColor;
    return Padding(
      padding: EdgeInsets.only(bottom: size * .15),
      child: Column(
        children: <Widget>[
          if (name?.isNotEmpty ?? false)
            Text(
              'سُورَةُ $name',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: style?.copyWith(
                fontSize: size * .7,
                color: color,
                height: 1.5,
              ),
            ),
          if (opening != null)
            Text(
              opening!,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: style?.copyWith(
                fontSize: size * .8,
                color: color,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// Why a word is waited on in red, in the reader's language. A sound is
/// named as the Mushaf writes it: a letter by itself, a short vowel by its
/// name.
String recitationWhyText(AppLocalizations l10n, RecitationWhy why) {
  String vowel(String mark) => switch (mark) {
    'َ' => l10n.recitationVowelFatha,
    'ِ' => l10n.recitationVowelKasra,
    'ُ' => l10n.recitationVowelDamma,
    _ => mark,
  };
  bool isVowel(String mark) => mark == 'َ' || mark == 'ِ' || mark == 'ُ';
  return switch (why.why) {
    FollowWhy.skipped => l10n.recitationHintSkipped,
    FollowWhy.ghunnah => l10n.recitationHintGhunnah,
    FollowWhy.madd => l10n.recitationHintMadd,
    FollowWhy.shaddah => l10n.recitationHintShaddah,
    FollowWhy.izhar => l10n.recitationHintIzhar,
    // The hidden nun said clearly (the model's own marks for it).
    FollowWhy.another when why.expected == 'ں' => l10n.recitationHintIkhfa,
    FollowWhy.another when why.expected == '۾' => l10n.recitationHintIqlab,
    FollowWhy.another when why.expected == 'ڇ' => l10n.recitationHintQalqalah,
    FollowWhy.another when isVowel(why.expected) && isVowel(why.heard) =>
      l10n.recitationHintVowel(vowel(why.heard), vowel(why.expected)),
    FollowWhy.another when why.expected.isNotEmpty && why.heard.isNotEmpty =>
      l10n.recitationHintLetter(why.heard, why.expected),
    _ => l10n.recitationHintUnknown,
  };
}

/// The line under the text while the microphone is on: the last words
/// heard; that it listens, before any; that none have come for a while;
/// or what is wrong.
class _FollowEar extends StatelessWidget {
  const _FollowEar({required this.ear, required this.onDevice, this.hint});

  final ValueNotifier<RecitationEar> ear;

  /// Why the word waited on in red is waited on, where the listener can
  /// say: shown while it is waited on, in place of the words heard.
  final ValueListenable<RecitationWhy?>? hint;

  /// The model on the phone listens: no network is to be checked.
  final bool onDevice;

  @override
  Widget build(BuildContext context) => hint == null
      ? _line(context, null)
      : ValueListenableBuilder<RecitationWhy?>(
          valueListenable: hint!,
          builder: (context, why, _) => _line(context, why),
        );

  Widget _line(BuildContext context, RecitationWhy? why) =>
      ValueListenableBuilder<RecitationEar>(
        valueListenable: ear,
        builder: (context, value, _) {
          final l10n = context.l10n;
          final heard = value.heard.trim().split(RegExp(r'\s+'));
          // Why the word is waited on, while it is: more to the point than
          // that the reader is heard, or is not.
          final reason = why == null ? null : recitationWhyText(l10n, why);
          final message = switch (value.trouble) {
            RecitationTrouble.network => l10n.recitationNoNetwork,
            RecitationTrouble.language => l10n.recitationNoArabic,
            RecitationTrouble.unavailable => l10n.recitationUnavailable,
            _ when reason != null => reason,
            RecitationTrouble.unrecognised => l10n.recitationNotRecognised,
            null when value.deaf =>
              onDevice
                  ? l10n.recitationNotHearingOnDevice
                  : l10n.recitationNotHearing,
            null when value.heard.trim().isEmpty => l10n.recitationListening,
            null => null,
          };
          // (Heard, though not taken for the word: the ear is not crossed out.)
          final quiet =
              value.deaf ||
              (value.trouble != null &&
                  value.trouble != RecitationTrouble.unrecognised);
          final warning = quiet || value.trouble != null || reason != null;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  quiet
                      ? Icons.hearing_disabled_rounded
                      : Icons.hearing_rounded,
                  size: 16,
                  color: warning ? recitationWrong : mushafAccentColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message ??
                        heard.sublist(math.max(0, heard.length - 4)).join(' '),
                    key: const ValueKey('reader-flow-follow-heard'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: message == null ? TextDirection.rtl : null,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: warning ? recitationWrong : mushafAccentColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// What the recitation check does with the voice and what it checks,
/// before its microphone is turned on for the first time.
class _RecitationNotice extends StatelessWidget {
  const _RecitationNotice({required this.onDevice});

  /// The model on the phone listens, not the phone's speech recognition.
  final bool onDevice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return AlertDialog(
      key: const ValueKey('recitation-notice'),
      title: Text(l10n.recitationCheck),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            line(Icons.mic_none_rounded, l10n.recitationNoticeHow),
            line(
              Icons.privacy_tip_outlined,
              onDevice
                  ? l10n.recitationNoticeVoiceOnDevice
                  : l10n.recitationNoticeVoice,
            ),
            line(
              Icons.info_outline_rounded,
              onDevice
                  ? l10n.recitationNoticeLimitsOnDevice
                  : l10n.recitationNoticeLimits,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('recitation-notice-start'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.recitationNoticeStart),
        ),
      ],
    );
  }
}

/// The one setting of the plain text: the size of its Arabic.
class _FlowFontSize extends StatefulWidget {
  const _FlowFontSize({
    required this.initial,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double initial;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_FlowFontSize> createState() => _FlowFontSizeState();
}

class _FlowFontSizeState extends State<_FlowFontSize> {
  late var _value = widget.initial;

  void _set(double value, {bool end = false}) {
    setState(() => _value = value);
    widget.onChanged(value);
    if (end) widget.onChangeEnd(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.arabicTextSize,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text('${_value.round()}', style: theme.textTheme.titleMedium),
            ],
          ),
          Slider(
            key: const ValueKey('reader-flow-text-size-slider'),
            value: _value,
            min: minReaderFlowFontSize,
            max: maxReaderFlowFontSize,
            divisions: 24,
            label: '${_value.round()}',
            onChanged: _set,
            onChangeEnd: widget.onChangeEnd,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => _set(defaultReaderFlowFontSize, end: true),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(context.l10n.reset),
            ),
          ),
        ],
      ),
    );
  }
}
