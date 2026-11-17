import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/text/arabic_digits.dart';
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

/// The ayah numbers on the paper: the app's gold, apart from the ink.
const _markerColor = Color(0xFF9A6D22);

class _FlowPageState extends ConsumerState<_FlowPage> {
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final _stackKey = GlobalKey();
  final _ayahKeys = <int, GlobalKey>{};
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

  /// The trial of following a recitation ([recitationFollowEnabled]): the
  /// listener while the microphone is on, the surah's words in order, the
  /// word reached and its box in the stack.
  RecitationListener? _listener;
  RecitationMatcher? _matcher;
  var _followWords = const <QuranWord>[];
  QuranWord? _followWord;
  Rect? _followRect;
  var _followGlide = true;

  /// The hint by the microphone is up: it comes a moment after the text
  /// opens and now and then after, until the microphone is tried.
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
    if (recitationFollowEnabled) {
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
        ayahKeys: _ayahKeys,
      ),
    );
  }

  @override
  void dispose() {
    _markTimer?.cancel();
    _scriptTimer?.cancel();
    _followHintTimer?.cancel();
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
      // The lens goes with its word, once the text has moved.
      _followGlide = false;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _placeLens())
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

  void _fingerDown(PointerDownEvent event, double size) {
    _fingers[event.pointer] = event.position;
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
  Future<void> _toggleFollow(List<QuranAyah> items) async {
    // The microphone is found: no more hints.
    _followHintTimer?.cancel();
    _followHint = false;
    final listening = _listener;
    if (listening != null) {
      setState(() {
        _listener = null;
        _followWord = null;
        _followRect = null;
      });
      unawaited(WakelockPlus.disable());
      await listening.stop();
      listening.dispose();
      return;
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
    final listener = RecitationListener(onHeard: _onHeard);
    setState(() {
      _listener = listener;
      // The lens shows where to read from.
      _followWord = words.isEmpty ? null : words[start < 0 ? 0 : start];
      _followGlide = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _placeLens());
    unawaited(WakelockPlus.enable());
    if (await listener.start() || !mounted || !identical(_listener, listener)) {
      return;
    }
    setState(() {
      _listener = null;
      _followWord = null;
      _followRect = null;
    });
    unawaited(WakelockPlus.disable());
    listener.dispose();
    // The trial's one message, not translated.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Распознавание речи недоступно или нет доступа к микрофону',
        ),
      ),
    );
  }

  void _onHeard(String transcript) {
    final index = _matcher?.hear(transcript);
    if (index == null || !mounted || _listener == null) return;
    setState(() {
      _followWord = _followWords[index];
      _followGlide = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _placeLens());
  }

  /// Puts the lens on its word and keeps that word in the upper part of the
  /// screen, so the lines to come are in view.
  void _placeLens() {
    final word = _followWord;
    final stack = _stackKey.currentContext?.findRenderObject();
    if (!mounted || word == null || stack is! RenderBox) return;
    final rect = _wordRegistry.wordRectIn(word, stack);
    if (rect == null) return;
    setState(() => _followRect = rect);
    final height = stack.size.height;
    if (!_scrollController.hasClients ||
        (rect.top > 0 && rect.bottom < height * .6)) {
      return;
    }
    final position = _scrollController.position;
    unawaited(
      _scrollController.animateTo(
        (position.pixels + rect.top - height * .25).clamp(
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
                      if (recitationFollowEnabled && items.isNotEmpty)
                        Flexible(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              key: const ValueKey('reader-flow-follow-hint'),
                              opacity: _followHint ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: const RecitationHint(),
                            ),
                          ),
                        ),
                      if (recitationFollowEnabled && items.isNotEmpty)
                        RecitationMicPulse(
                          key: const ValueKey('reader-flow-follow-pulse'),
                          active: _followHint,
                          child: IconButton(
                            key: const ValueKey('reader-flow-follow'),
                            onPressed: () => unawaited(_toggleFollow(items)),
                            color: _listener != null
                                ? const Color(0xFFB3261E)
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
                        ? _FollowEar(ear: _listener!.ear)
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

  Widget _text(
    List<QuranAyah> items,
    double size,
    Map<String, List<int>>? versePages,
  ) {
    _schedulePlace(items);
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineMedium?.copyWith(
      color: mushafInkColor,
      fontFamily: IqroTheme.arabicFontFamily,
      fontWeight: FontWeight.normal,
      fontSize: size,
      height: 2,
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
              onTap: _words.range == null ? null : _words.clear,
              onDoubleTap: _words.range == null ? _resetSize : null,
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
                          // The lens stays on its word as the text moves.
                          if (_followRect case final rect?) {
                            setState(() {
                              _followGlide = false;
                              _followRect = rect.shift(
                                Offset(0, -(notification.scrollDelta ?? 0)),
                              );
                            });
                          }
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
                            : items.indexWhere(
                                    (item) => item.number == widget.initialAyah,
                                  ) +
                                  1,
                        padding: EdgeInsets.fromLTRB(
                          side,
                          0,
                          side,
                          _words.range == null ? 32 : 280,
                        ),
                        itemCount: items.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _FlowHeader(
                              name: surah?.nameAr,
                              opening: opening,
                              size: size,
                              style: style,
                            );
                          }
                          if (index == items.length + 1) {
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
                          final ayah = items[index - 1];
                          final words = ayahWords(ayah);
                          final page = pageOf(ayah);
                          final pageEnded =
                              index > 1 &&
                              page != null &&
                              page != pageOf(items[index - 2]);
                          final text = Consumer(
                            builder: (context, ref, _) {
                              final script = watchMushafAyahScript(
                                ref,
                                surah: widget.surah,
                                ayah: ayah.number,
                                wordCount: words.length,
                              );
                              // The Mushaf's script reflows the text when it
                              // arrives: the ayah at the top stays there.
                              // Once the reader scrolls, pages load ahead of
                              // the screen and move nothing on it.
                              if (script == null) {
                                _plainAyahs.add(ayah.number);
                              } else if (_plainAyahs.remove(ayah.number) &&
                                  !_dragged) {
                                _keepPlace();
                              }
                              return ReaderAyahWords.flow(
                                key: ValueKey(
                                  'reader-flow-ayah-${ayah.number}',
                                ),
                                surah: widget.surah,
                                ayahs: <ReaderAyahText>[
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
                                ],
                                textAlign: TextAlign.start,
                                markerStyle: const TextStyle(
                                  color: _markerColor,
                                ),
                                kashida: true,
                                style: style,
                                registry: _wordRegistry,
                                range: _words.range,
                                // The ayah a quarter of a hizb starts at, while
                                // it is announced.
                                marked:
                                    _marked ??
                                    (_rubMark.mark?.startAyah.ayah ==
                                                ayah.number &&
                                            words.isNotEmpty
                                        ? QuranWordRange.between(
                                            QuranWord(
                                              widget.surah,
                                              ayah.number,
                                              1,
                                            ),
                                            QuranWord(
                                              widget.surah,
                                              ayah.number,
                                              words.length,
                                            ),
                                          )
                                        : null),
                                playingWord: _words.playingWord,
                                onRange: (range) => _selectWords(items, range),
                                onDrag: _followWordDrag,
                              );
                            },
                          );
                          // Each ayah a paragraph of its own, a blank line
                          // between them.
                          return Padding(
                            key: _ayahKeys.putIfAbsent(
                              ayah.number,
                              GlobalKey.new,
                            ),
                            padding: EdgeInsets.only(bottom: size * .9),
                            child: pageEnded
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
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
                                  )
                                : text,
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
                  if (_followRect case final rect?)
                    RecitationLens(word: rect, glide: _followGlide),
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
      padding: EdgeInsets.only(bottom: size * .5),
      child: Column(
        children: <Widget>[
          if (name?.isNotEmpty ?? false)
            Text(
              'سُورَةُ $name',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: style?.copyWith(fontSize: size * .7, color: color),
            ),
          if (opening != null)
            Text(
              opening!,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: style?.copyWith(fontSize: size * .8, color: color),
            ),
        ],
      ),
    );
  }
}

/// What the phone hears, under the text while the trial listens: the last
/// words heard, or the recogniser's error.
class _FollowEar extends StatelessWidget {
  const _FollowEar({required this.ear});

  final ValueNotifier<RecitationEar> ear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RecitationEar>(
    valueListenable: ear,
    builder: (context, value, _) {
      final heard = value.heard.split(' ');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.hearing_rounded, size: 16, color: mushafAccentColor),
          const SizedBox(width: 8),
          Text(
            value.error ??
                heard.sublist(math.max(0, heard.length - 4)).join(' '),
            key: const ValueKey('reader-flow-follow-heard'),
            textDirection: TextDirection.rtl,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: mushafAccentColor),
          ),
        ],
      );
    },
  );
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
