import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'kashida.dart';
import 'word_range.dart';

/// The reader's ayahs on screen, so a drag that leaves one card finds the
/// word under the finger in another.
class ReaderWordRegistry {
  final _ayahs = <int, _ReaderAyahWordsState>{};

  /// Where [word] is on screen, in global coordinates, if its ayah is built.
  Rect? wordRect(QuranWord word) => _ayahs[word.ayah]?._globalRect(word);

  /// Where [word] is in [ancestor]: true while a page turning in tilts the
  /// screen, which global coordinates are not.
  Rect? wordRectIn(QuranWord word, RenderObject ancestor) =>
      _ayahs[word.ayah]?._rectIn(word, ancestor);

  /// The word at [global], else the nearest word of the nearest ayah.
  QuranWord? wordAt(Offset global) {
    QuranWord? best;
    var distance = double.infinity;
    for (final state in _ayahs.values) {
      final found = state._nearest(global);
      if (found == null) continue;
      if (found.distance < distance) {
        best = found.word;
        distance = found.distance;
      }
    }
    return best;
  }
}

/// One ayah's words in a [ReaderAyahWords.flow] paragraph.
class ReaderAyahText {
  const ReaderAyahText({
    required this.ayah,
    required this.words,
    this.firstPosition = 1,
    this.marker = '',
    this.spans,
    this.markerSpan,
  });

  final int ayah;

  /// The words in order; the first is at [firstPosition].
  final List<String> words;
  final int firstPosition;

  /// Text after the last word: the ayah's end marker.
  final String marker;

  /// The words as the selected Mushaf writes them, one span for each of
  /// [words], drawn in their place; [markerSpan] then stands for [marker].
  final List<InlineSpan>? spans;
  final InlineSpan? markerSpan;
}

/// The Arabic text of one ayah in the reader, word by word. A long press
/// selects its word, and moving the finger on selects the words up to
/// another one, also in a neighbouring ayah. Taps go to the card.
class ReaderAyahWords extends StatefulWidget {
  const ReaderAyahWords({
    required this.surah,
    required this.ayah,
    required this.words,
    required this.style,
    required this.registry,
    required this.onRange,
    this.marker = '',
    this.firstPosition = 1,
    this.spans,
    this.markerSpan,
    this.range,
    this.playingWord,
    this.onDrag,
    super.key,
  }) : flowAyahs = null,
       textAlign = TextAlign.center,
       markerStyle = null,
       kashida = false,
       marked = null;

  /// Several ayahs running on in one paragraph, as on a Mushaf page.
  ReaderAyahWords.flow({
    required this.surah,
    required List<ReaderAyahText> ayahs,
    required this.style,
    required this.registry,
    required this.onRange,
    this.textAlign = TextAlign.justify,
    this.markerStyle,
    this.kashida = false,
    this.range,
    this.marked,
    this.playingWord,
    this.onDrag,
    super.key,
  }) : flowAyahs = ayahs,
       ayah = ayahs.first.ayah,
       words = const <String>[],
       firstPosition = 1,
       marker = '',
       spans = null,
       markerSpan = null;

  final int surah;
  final int ayah;

  /// The words in order; the first is at [firstPosition].
  final List<String> words;
  final int firstPosition;

  /// Text after the last word: the ayah's end marker.
  final String marker;

  /// See [ReaderAyahText.spans].
  final List<InlineSpan>? spans;
  final InlineSpan? markerSpan;

  /// Set by [ReaderAyahWords.flow]: the ayahs in place of the one above.
  final List<ReaderAyahText>? flowAyahs;
  final TextAlign textAlign;

  /// The end markers' own style, over [style].
  final TextStyle? markerStyle;

  /// Lines of a single ayah filled to both edges by drawing out the joins
  /// between letters, as in a printed Mushaf ([kashidaLayout]).
  final bool kashida;

  /// Words shown for a moment in a soft tint: the place a reader came to.
  final QuranWordRange? marked;
  final TextStyle? style;
  final ReaderWordRegistry registry;
  final QuranWordRange? range;
  final QuranWord? playingWord;
  final ValueChanged<QuranWordRange> onRange;

  /// Follows the finger while it pulls the selection, in global coordinates.
  final ValueChanged<Offset>? onDrag;

  @override
  State<ReaderAyahWords> createState() => _ReaderAyahWordsState();
}

class _ReaderAyahWordsState extends State<ReaderAyahWords> {
  TextPainter? _painter;

  /// Every word of the paragraph in order, with its text.
  var _words = const <({QuranWord word, String text})>[];

  /// The text offset where each word starts, and the end of the last.
  var _offsets = const <int>[];
  QuranWord? _anchor;

  /// The handle a finger pulls, and where it was taken.
  ({bool start, Rect box})? _held;

  static List<ReaderAyahText> _texts(ReaderAyahWords widget) =>
      widget.flowAyahs ??
      <ReaderAyahText>[
        ReaderAyahText(
          ayah: widget.ayah,
          words: widget.words,
          firstPosition: widget.firstPosition,
          marker: widget.marker,
          spans: widget.spans,
          markerSpan: widget.markerSpan,
        ),
      ];

  void _register(ReaderAyahWords widget) {
    for (final text in _texts(widget)) {
      widget.registry._ayahs[text.ayah] = this;
    }
  }

  void _unregister(ReaderAyahWords widget) {
    for (final text in _texts(widget)) {
      if (identical(widget.registry._ayahs[text.ayah], this)) {
        widget.registry._ayahs.remove(text.ayah);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _register(widget);
  }

  @override
  void didUpdateWidget(covariant ReaderAyahWords oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unregister(oldWidget);
    _register(widget);
  }

  @override
  void dispose() {
    _unregister(widget);
    _painter?.dispose();
    super.dispose();
  }

  QuranWord _word(int index) => _words[index].word;

  int? _indexOf(QuranWord word) {
    if (word.surah != widget.surah) return null;
    final index = _words.indexWhere((item) => item.word == word);
    return index < 0 ? null : index;
  }

  ({QuranWord word, double distance})? _nearest(Offset global) {
    final painter = _painter;
    final box = context.findRenderObject() as RenderBox?;
    if (painter == null || box == null || !box.attached || _offsets.isEmpty) {
      return null;
    }
    final local = box.globalToLocal(global);
    // The text, not the room kept under it for a handle's knob.
    final size = Size(box.size.width, painter.height);
    final dy = local.dy < 0 ? -local.dy : math.max(0.0, local.dy - size.height);
    final point = Offset(
      local.dx.clamp(0.0, size.width),
      local.dy.clamp(0.0, size.height - 1),
    );
    final offset = painter.getPositionForOffset(point).offset;
    var index = 0;
    while (index < _words.length - 1 && offset >= _offsets[index + 1]) {
      index++;
    }
    return (word: _word(index), distance: dy);
  }

  void _pull(Offset global, QuranWord anchor) {
    widget.onDrag?.call(global);
    final word = widget.registry.wordAt(global);
    final range = word == null ? null : QuranWordRange.between(anchor, word);
    if (range != null && range != widget.range) widget.onRange(range);
  }

  TextSpan _span(double width) {
    final range = widget.range;
    final marked = widget.marked;
    final children = <InlineSpan>[];
    final words = <({QuranWord word, String text})>[];
    final offsets = <int>[];
    final texts = _texts(widget);
    // Glyphs of a Mushaf font are not letters to draw out.
    final layout =
        widget.kashida && texts.length == 1 && texts.single.spans == null
        ? kashidaLayout(
            words: texts.single.words,
            marker: texts.single.marker,
            style: widget.style,
            width: width,
            scaler: MediaQuery.textScalerOf(context),
          )
        : null;
    var length = 0;
    for (final ayah in texts) {
      for (final (index, original) in ayah.words.indexed) {
        final span = ayah.spans?[index];
        final text =
            span?.toPlainText(includeSemanticsLabels: false) ??
            layout?.words[index] ??
            original;
        final word = QuranWord(
          widget.surah,
          ayah.ayah,
          ayah.firstPosition + index,
        );
        final selected = range?.contains(word) ?? false;
        if (words.isNotEmpty) {
          final joined = selected && range!.contains(words.last.word);
          children.add(
            TextSpan(
              // A drawn-out line ends where the layout ended it.
              text: layout?.breaks.contains(index - 1) ?? false ? '\n' : ' ',
              style: joined
                  ? const TextStyle(backgroundColor: wordRangeSelectionColor)
                  : null,
            ),
          );
          length += 1;
        }
        offsets.add(length);
        words.add((word: word, text: text));
        children.add(
          TextSpan(
            text: span == null ? text : null,
            children: span == null ? null : <InlineSpan>[span],
            style: selected
                ? TextStyle(
                    backgroundColor: word == widget.playingWord
                        ? wordRangePlayingColor
                        : wordRangeSelectionColor,
                  )
                : marked?.contains(word) ?? false
                ? const TextStyle(backgroundColor: _markedColor)
                : null,
          ),
        );
        length += text.length;
      }
      final marker =
          ayah.markerSpan ??
          (ayah.marker.isEmpty
              ? null
              : TextSpan(text: ayah.marker, style: widget.markerStyle));
      if (marker != null) {
        // The end of the last word: the marker belongs to no word.
        if (identical(ayah, texts.last)) offsets.add(length);
        children.add(marker);
        length += marker.toPlainText(includeSemanticsLabels: false).length;
      }
    }
    if (offsets.length == words.length) offsets.add(length);
    _words = words;
    _offsets = offsets;
    return TextSpan(style: widget.style, children: children);
  }

  Rect? _globalRect(QuranWord word) {
    final index = _indexOf(word);
    if (index == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    final local = _wordBox(index);
    if (box == null || !box.attached || local == null) return null;
    return local.shift(box.localToGlobal(Offset.zero));
  }

  Rect? _rectIn(QuranWord word, RenderObject ancestor) {
    final index = _indexOf(word);
    if (index == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    final local = _wordBox(index);
    if (box == null || !box.attached || local == null) return null;
    return local.shift(box.localToGlobal(Offset.zero, ancestor: ancestor));
  }

  Rect? _wordBox(int index) {
    final painter = _painter;
    if (painter == null) return null;
    final boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: _offsets[index],
        extentOffset: _offsets[index] + _words[index].text.length,
      ),
    );
    if (boxes.isEmpty) return null;
    return boxes
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
  }

  List<Widget> _handles() {
    final range = widget.range;
    if (range == null) return const [];
    final start = _indexOf(range.start);
    final end = _indexOf(range.end);
    Widget? handle(int? index, {required bool start}) {
      final box = index == null ? null : _wordBox(index);
      // A handle pulled into another ayah stays here, unseen, until the
      // finger lifts: its gesture lives in this card.
      final held = _held?.start == start ? _held!.box : null;
      final at = box ?? held;
      if (at == null) return null;
      return Positioned(
        key: ValueKey(
          start ? 'word-range-start-handle' : 'word-range-end-handle',
        ),
        left: (start ? at.right : at.left) - WordRangeHandle.width / 2,
        top: at.top,
        child: Opacity(
          opacity: box == null ? 0 : 1,
          child: WordRangeHandle(
            start: start,
            lineHeight: at.height,
            onDrag: (point) {
              _held ??= (start: start, box: at);
              _pull(point, start ? range.end : range.start);
            },
            onEnd: () {
              if (_held == null) return;
              _held = null;
              if (mounted) setState(() {});
            },
          ),
        ),
      );
    }

    return <Widget>[?handle(start, start: true), ?handle(end, start: false)];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _painter?.dispose();
      final painter = TextPainter(
        text: _span(constraints.maxWidth),
        textAlign: widget.textAlign,
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth);
      _painter = painter;
      final handles = _handles();
      return Semantics(
        label: _texts(widget).expand((ayah) => ayah.words).join(' '),
        textDirection: TextDirection.rtl,
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(duration: wordPressDuration),
                  (recognizer) => recognizer
                    ..onLongPressStart = (details) {
                      final found = _nearest(details.globalPosition);
                      if (found == null) return;
                      _anchor = found.word;
                      wordRangePulling.value = true;
                      Feedback.forLongPress(context);
                      widget.onRange(QuranWordRange.single(found.word));
                    }
                    ..onLongPressMoveUpdate = (details) {
                      final anchor = _anchor;
                      if (anchor != null) _pull(details.globalPosition, anchor);
                    }
                    ..onLongPressEnd = (_) {
                      _anchor = null;
                      wordRangePulling.value = false;
                    }
                    ..onLongPressCancel = () => wordRangePulling.value = false,
                ),
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              CustomPaint(
                // A knob hangs under its line. A touch only reaches it inside
                // this box, so the box makes room for the knob of the last line.
                size: Size(
                  constraints.maxWidth,
                  painter.height + (handles.isEmpty ? 0 : _knobRoom),
                ),
                painter: _WordsPainter(painter),
              ),
              ...handles,
            ],
          ),
        ),
      );
    },
  );
}

/// The soft tint of [ReaderAyahWords.marked]: the app's gold, faint.
const _markedColor = Color(0x38C49647);

/// How far a handle's knob reaches under the line it marks.
const _knobRoom = WordRangeHandle.knob + 6;

class _WordsPainter extends CustomPainter {
  const _WordsPainter(this.painter);

  final TextPainter painter;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_WordsPainter oldDelegate) =>
      !identical(oldDelegate.painter, painter);
}
